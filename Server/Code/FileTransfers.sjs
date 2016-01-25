// High level algorithms to deal with transferring (uploading and deleting) files to cloud storage. This is independent of the  details of the specific cloud storage system.

'use strict';

var Common = require('./Common');
var CloudStorage = require('./CloudStorage.sjs');
var Operation = require('./Operation');
var PSOutboundFileChange = require('./PSOutboundFileChange.sjs');
var logger = require('./Logger');
var PSFileIndex = require('./PSFileIndex.sjs')
var File = require('./File.sjs');
var PSFileTransferLog = require('./PSFileTransferLog');
var ServerConstants = require('./ServerConstants');
var PSInboundFile = require('./PSInboundFile');

const maxNumberSendAttempts = 3;
const maxNumberReceiveAttempts = 3;

/* Constructor
    Parameters: 
        1) op of type Operation
        2) psOperationId of type PSOperationId
*/
function FileTransfers(op, psOperationId) {
    // always initialize all instance properties
    
    this.cloudStorage = new CloudStorage(op.userCreds);
    this.op = op;
    this.psOperationId = psOperationId;
}

// instance methods

// Do post-constructor initialization/setup. It's assumed that this is called prior to any other instance methods.
// My rationale for having this method is that with Google Drive, I seem unable to replace an existing file without first doing a listing of existing files. It's awkward to have a callback on a constructor, so I'm having a separate setup method, so I can call CloudStorage setup, which in the case of Google Drive, will do a directory/folder listing.
// Callback: One param: error
FileTransfers.prototype.setup = function (callback) {
    var self = this;
    
    self.cloudStorage.setup(function (error) {
        callback(error);
    });
}

// "send" in "sendFiles" includes both uploading and deletion.
// The files are specified in the PSOutboundFileChanges for the user/device.
// This will try each file transfer a specific number of times before giving up.
// Each time a file is transferred, the specific entry will be removed from PSOutboundFileChange's.
// Callback: One parameter: Error.
FileTransfers.prototype.sendFiles = function (callback) {
    var self = this;
    
    PSOutboundFileChange.getAllCommittedFor(self.op.userId(), self.op.deviceId(),
        function (error, outboundFileChanges) {
            if (error) {
                callback(error);
            }
            else if (outboundFileChanges.length == 0 ) {
                logger.trace("No outbound file operations to send.");
                callback(null);
            }
            else {
                logger.trace(outboundFileChanges.length + " outbound file operations to send.");
                self.sendEachFile(outboundFileChanges, function (error) {
                    callback(error);
                });
            }
        });
}

// PRIVATE (only part of the prototype so I can access member variables).
// Recursively sends each file in the outboundFileChanges array
// Callback: One param: error
FileTransfers.prototype.sendEachFile = function (outboundFileChanges, callback) {
    var self = this;
    
    if (!isDefined(outboundFileChanges)) {
        callback("**** Error: No outboundFileChanges were given");
        return;
    }
    
    self.sendFileUsingMultipleAttempts(outboundFileChanges[0], maxNumberSendAttempts,
        function (error) {
            if (error) {
                callback(error);
            }
            else {
                if (outboundFileChanges.length > 1) {
                    // Remove the 0th element from outboundFileChanges. i.e., leaves outboundFileChanges as the tail of outboundFileChanges.
                    outboundFileChanges.shift()
                    
                    self.sendEachFile(outboundFileChanges, callback);
                }
                else {
                    callback(null);
                }
            }
        });
}

// PRIVATE (only part of the prototype so I can access member variables).
// Callback: One param: error
FileTransfers.prototype.sendFileUsingMultipleAttempts =
    function (outboundFileChange, remainingSendAttempts, callback) {
        var self = this;

        if (!isDefined(outboundFileChange)) {
            callback(new Error("**** Error: No outboundFileChange was given"));
            return;
        }
    
        var currentSendAttempt = maxNumberSendAttempts - remainingSendAttempts + 1;
        
        logger.info("Send attempt " + currentSendAttempt + " for file: " + JSON.stringify(outboundFileChange));
        
        var fileToSend = new File(outboundFileChange.userId, outboundFileChange.deviceId, outboundFileChange.fileId);
        fileToSend.cloudFileName = outboundFileChange.cloudFileName;
        fileToSend.mimeType = outboundFileChange.mimeType;
        
        // Increment operationCount of the PSOperationId so we can distinguish between two main kinds of failures and recovery for the app/client: Errors that occurred prior to any transfer of data to cloud storage and errors that occurred after possible transfer of data.
        // Note that the accuracy of the operationCount field of the PSOperationId is by no means guaranteed. E.g., if the psOperationId update succeeds, but the sendFile fails, and then later a recovery redoes this process, the PSOperationId operationCount will be inaccurate.
        
        // TODO: What happens if we get an error right after committing the outbound file changes, but before any transfer to cloud storage? I had been having a problem doing a file changes recovery with committed outbound files. How am I dealing with this?
        
        self.psOperationId.operationCount++;
        self.psOperationId.error = null;
        
        self.psOperationId.update(function (error) {
            if (error) {
                callback(error);
                return;
            }
            
            if (outboundFileChange.toDelete) {
                self.cloudStorage.deleteFile(fileToSend, function (err, fileProperties) {
                    self.finishSendFile(err, remainingSendAttempts, currentSendAttempt, outboundFileChange, fileProperties, callback);
                });
            }
            else {
                self.cloudStorage.outboundTransfer(fileToSend, function (err, fileProperties) {
                    self.finishSendFile(err, remainingSendAttempts, currentSendAttempt, outboundFileChange, fileProperties, callback);
                });
            }
        });
    }

// PRIVATE
FileTransfers.prototype.finishSendFile = function (err, remainingSendAttempts, currentSendAttempt, outboundFileChange, fileProperties, callback) {

    var self = this;
    
    if (err) {
        logger.error("Error sending/removing file on attempt %d: %j", currentSendAttempt, err);
        
        if (remainingSendAttempts <= 0) {
            callback(new Error("*** Error sending/removing file to cloud storage"));
        }
        else {
            self.sendFileUsingMultipleAttempts(outboundFileChange,
                remainingSendAttempts - 1, callback);
        }
    }
    else {
        // Success sending the file from the SyncServer to cloud storage.
        // Delete the outboundFileChange object from PS, and delete the file in the local file system corresponding to that outboundFileChange. (Default operation of remove below is to remove the local file).
        /* 
        Failure mode analysis for the following code:
        1) The remove of the outbound file change could fail, leaving us with:
            a) possibly a removed oubound file change entry.
            b) no new/changed PSFileIndex entry
            
            If there is no outbound file entry, how can we recover? An app/client would find that the file wasn't in the outbound file change entries, and might conclude that the file transfer was done for that file. And yet, the PSFileIndex info would be consistent with that conclusion.
         
        2) The file index add/change could fail leaving us with:
            a) a removed outbound file change entry.
            b) possibly no new/changed PSFileIndex entry.
            
            This is similar to issues with recover as in 1). E.g., with a removed outbound file change entry, and no new/changed PSFileIndex entry.
            
        What if we create an additional Mongo collection that acts as a log. We'd write the (outbound file changes, and PSFileIndex) changes we're about to make to that log, and remove the entry from that log if we succeeded in these two operations. This log would have simple, less likely to fail operations. On a failure in 1) or 2) from above, we could later use that log to recover.
        */
        
        var fileIndexData = {
            fileId: outboundFileChange.fileId,
            userId: outboundFileChange.userId,
            cloudFileName: outboundFileChange.cloudFileName,
            mimeType:outboundFileChange.mimeType,
            deleted: outboundFileChange.toDelete,
            fileVersion: outboundFileChange.fileVersion,
            appFileType: outboundFileChange.appFileType
        };
        
        // Don't have this when deleting.
        if (fileProperties) {
            fileIndexData.fileSizeBytes = fileProperties.fileSizeBytes;
        }
        
        logger.debug("Updating from outboundFileChange: %j", outboundFileChange);
        logger.debug("Updating with: %j", fileIndexData);
        
        var logFileObjData = {
            fileIndex: fileIndexData,
            outboundFileChange: outboundFileChange.dataProps()
        };
        
        var fileTransferLogObj = null;
        try {
            fileTransferLogObj = new PSFileTransferLog(logFileObjData);
        } catch (error) {
            callback(error);
            return;
        }
        
        fileTransferLogObj.storeNew(function (error) {
            if (error) {
                callback(error);
            }
            else {
                var fileIndexObj = null;
                
                try {
                    fileIndexObj = new PSFileIndex(fileIndexData);
                } catch (error) {
                    callback(error);
                    return;
                }

                var sameFileIndexVersionIfExists = false;
                self.updatePSFileDescrs(sameFileIndexVersionIfExists, outboundFileChange, fileIndexObj, function (error) {
                
                    if (error) {
                        callback(error);
                    }
                    else {
                        fileTransferLogObj.remove(function (error) {
                            // [1] I'm not going to call this an error if we fail on the log entry removal. If we've failed here we have just have to later clean up the log. The only question is: How do we detect, in the log, that we don't have to do any changes to other Mongo collections to clean this instance up? Answer: We can check the outbound file change _id in the log instance. If this _id is not present, then we'll assume we don't need to clean up. Since removing the outbound file change was the last step in finishSend, we should be OK then.
                            if (error) {
                                logger.error("Failed in removing log file entry: " + error);
                            }
                            callback(null);
                        });
                    }
                });
            }
        });
    }
}

// PRIVATE
// Instance method only so that we can access instance vars.
// Remove the outbound file change, and add/update the PSFileIndex.
// The callback has one parameter: Error
FileTransfers.prototype.updatePSFileDescrs = function (sameFileIndexVersionIfExists, outboundFileChangeObj, fileIndexObj, callback) {

    var self = this;
    
    fileIndexObj.updateOrStoreNew(sameFileIndexVersionIfExists, function (error) {
        if (objOrInject(error, self.op, ServerConstants.dbTcSendFilesUpdate)) {
            logger.debug("updateOrStoreNew: Error: " + error);
            callback(error);
        }
        else {
            outboundFileChangeObj.remove(function (error) {
                callback(error);
                
                // Getting an error removing the PSOutboundFileChange entry doesn't necessarily mean that the entry was not removed from PSOutboundFileChanges. The remove method in PSOutboundFileChange can fail for other reasons, such as failing to remove the local file.
            });
        }
    });
}

// Assuming that a lock is held by self.op.userId(), checks if there are any entries in the PSFileTransferLog that reflect an error. Given [1] above, not all entries will *necessarily* reflect an error. If the entry doesn't reflect an error, it is removed. If it does reflect an error, this means that we need to bring the PSFileIndex and/or PSOutboundFileChange collections into consistency.
// Callback takes one parameter: Error.
FileTransfers.prototype.ensureLogConsistency = function (callback) {
    var self = this;
    
    logger.debug("ensureLogConsistency...");

    PSFileTransferLog.getAllFor(self.op.userId(), function (error, logEntries) {
        if (error) {
            callback(error);
        }
        else {
            logger.debug("Number of log entries: " + logEntries.length);

            function elec(logEntry, callback) {
                self.ensureLogEntryConsistency(logEntry, callback);
            }
            
            Common.applyFunctionToEach(elec, logEntries, callback);
        }
    });
}

FileTransfers.prototype.ensureLogEntryConsistency = function (logEntry, callback) {
    var self = this;
    
    // Does the log entry reflect an error? From [1] above: We can check the outbound file change _id in the log instance. If this _id is not present, then we'll assume we don't need to clean up.
    var outboundFileChangeObj = logEntry.getOutboundFileChange();
    if (!outboundFileChangeObj) {
        var msg = "Could not get outboundFileChangeObj";
        logger.error(msg);
        callback(new Error(msg));
        return;
    }
    
    outboundFileChangeObj.lookup(function (error, objPresent) {
        if (error) {
            callback(error);
        }
        else if (!objPresent) {
            logger.debug("Log entry doesn't reflect an error: " + JSON.stringify(logEntry));
            // Just remove the log entry and we should be good.

            logEntry.remove(function (error) {
                callback(error);
            });
        } else {
            logger.debug("Log entry indicates outbound file change was still there: " + JSON.stringify(logEntry));
            // Retry the updatePSFileDescrs.

            var fileIndexObj = logEntry.getFileIndex();
            if (!fileIndexObj) {
                var msg = "Could not get fileIndexObj";
                logger.error(msg);
                callback(new Error(msg));
                return;
            }
            
            var sameFileIndexVersionIfExists = true;
            self.updatePSFileDescrs(sameFileIndexVersionIfExists, outboundFileChangeObj, fileIndexObj, function (error) {
                if (error) {
                    callback(error);
                }
                else {
                    logEntry.remove(function (error) {
                        callback(error);
                    });
                }
            });
        }
    });
}

// The files are specified in the PSInboundFile's for the user/device.
// This will try each file transfer a specific number of times before giving up.
// Each time a file is transferred, the specific entry will be removed from PSInboundFile's.
// Callback: One parameter: Error.
FileTransfers.prototype.receiveFiles = function (callback) {
    var self = this;
    
    PSInboundFile.getAllFor(self.op.userId(), self.op.deviceId(),
        function (error, inboundFiles) {
            if (error) {
                callback(error);
            }
            else if (inboundFiles.length == 0 ) {
                logger.trace("No inbound files to receive.");
                callback(null);
            }
            else {
                logger.trace(inboundFiles.length + " inbound files to receive.");
                self.receiveEachFile(inboundFiles, function (error) {
                    callback(error);
                });
            }
        });
}

// PRIVATE (only part of the prototype so I can access member variables).
// Recursively receives each file in the inboundFiles array
// Callback: One param: error
FileTransfers.prototype.receiveEachFile = function (inboundFiles, callback) {
    var self = this;
    
    if (!isDefined(inboundFiles)) {
        callback(new Error("**** Error: No inboundFiles were given"));
        return;
    }
    
    self.receiveFileUsingMultipleAttempts(inboundFiles[0], maxNumberReceiveAttempts,
        function (error) {
            if (error) {
                callback(error);
            }
            else {
                if (inboundFiles.length > 1) {
                    // Remove the 0th element from inboundFiles.
                    inboundFiles.shift()
                    
                    self.receiveEachFile(inboundFiles, callback);
                }
                else {
                    callback(null);
                }
            }
        });
}

// PRIVATE (only part of the prototype so I can access member variables).
// Callback: One param: error
FileTransfers.prototype.receiveFileUsingMultipleAttempts =
    function (inboundFile, remainingReceiveAttempts, callback) {
        var self = this;

        if (!isDefined(inboundFile)) {
            callback(new Error("**** Error: No inboundFile was given"));
            return;
        }
    
        var currentReceiveAttempt = maxNumberReceiveAttempts - remainingReceiveAttempts + 1;
        
        logger.info("Receive attempt " + currentReceiveAttempt + " for file: " + JSON.stringify(inboundFile));
        
        var fileToReceive = new File(inboundFile.userId, inboundFile.deviceId, inboundFile.fileId);
        
        // Add cloudFileName and mimeType to the File object.
        var fileIndexData = {
            fileId: inboundFile.fileId,
            userId: inboundFile.userId,
        };
        
        var fileIndexObj = null;
        
        try {
            fileIndexObj = new PSFileIndex(fileIndexData);
        } catch (error) {
            callback(error);
            return;
        }
        
        fileIndexObj.lookup(function (error, objectFound) {
            if (error) {
                callback(error);
            }
            else {
                fileToReceive.cloudFileName = fileIndexObj.cloudFileName;
                fileToReceive.mimeType = fileIndexObj.mimeType;
 
                // Increment operationCount of the PSOperationId so we can distinguish between two main kinds of failures and recovery for the app/client: Errors that occurred prior to any transfer of data from cloud storage and errors that occurred after possible transfer of data.
                // Note that the accuracy of the operationCount field of the PSOperationId is by no means guaranteed. E.g., if the psOperationId update succeeds, but the receiveFile fails, and then later a recovery redoes this process, the PSOperationId operationCount will be inaccurate.
                
                self.psOperationId.operationCount++;
                self.psOperationId.error = null;
                
                self.psOperationId.update(function (error) {
                    if (error) {
                        callback(error);
                        return;
                    }

                    self.cloudStorage.inboundTransfer(fileToReceive,
                        function (error, fileProperties) {

                            if (error) {
                                logger.error("Error receiving file on attempt %d: %j", currentReceiveAttempt, error);
                                
                                if (remainingReceiveAttempts <= 0) {
                                    callback(new Error("*** Error receiving file from cloud storage"));
                                }
                                else {
                                    self.receiveFileUsingMultipleAttempts(inboundFile,
                                        remainingReceiveAttempts - 1, callback);
                                }
                            }
                            else {
                                // Success receiving the file from cloud storage.
                                // Mark the inbound file as tranferred from cloud storage-- we'll be downloading the file from the sync server to the client in an unlocked state, so the PSInboundFile object now just indicates the presence of of the file in local temporary, sync server, storage.
                                
                                logger.debug("Updating inboundFile: %j", inboundFile);

                                inboundFile.received = true;
                                inboundFile.update(function (error) {
                                    callback(error);
                                });
                            }
                        });
                });
            }
        });
    }

// export the class
module.exports = FileTransfers;

/* Notes on recovery:

You can use a two phase commit, but that looks more complex than my algorithms already https://docs.mongodb.org/manual/tutorial/perform-two-phase-commits/
*/

// High level algorithms to deal with transferring (uploading and deleting) files to cloud storage. This is independent of the  details of the specific cloud storage system.

'use strict';

var Common = require('./Common');
var Operation = require('./Operation');
var logger = require('./Logger');
var PSFileIndex = require('./PSFileIndex.sjs')
var File = require('./File.sjs');
var ServerConstants = require('./ServerConstants');
var Mongo = require('./Mongo');
var PSUpload = require('./PSUpload');

var GoogleCloudStorage = require('./GoogleCloudStorage.sjs');

const maxNumberSendAttempts = 3;
const maxNumberReceiveAttempts = 3;

/* Constructor
    Parameter:
        op of type Operation
*/
function FileTransfers(op) {
    // always initialize all instance properties
    
    this.cloudStorage = new GoogleCloudStorage(op.psUserCreds, op.psUserCreds.cloudFolderPath);
    this.op = op;
}

FileTransfers.methodNameReceiveFiles = "receiveFiles";
FileTransfers.methodNameSendFiles = "sendFiles";

// instance methods

// Do post-constructor initialization/setup. It's assumed that this is called prior to any other instance methods.
// My rationale for having this method is that with Google Drive, I seem unable to replace an existing file without first doing a listing of existing files. It's awkward to have a callback on a constructor, so I'm having a separate setup method, so I can call GoogleCloudStorage setup, which in the case of Google Drive, will do a directory/folder listing.
// Callback: One param: error
FileTransfers.prototype.setup = function (callback) {
    var self = this;
    
    self.cloudStorage.setup(function (error) {
        callback(error);
    });
}

// Handles both file-uploads and upload-deletions.
// Parameters:
//  1) psUpload: Type PSUpload
//  2) fileReadStream: (optional)-- required for file-uploads only.
//  3) Callback: One param: error
FileTransfers.prototype.sendFile = function (psUpload, fileReadStream, callback) {
    var self = this;
    
    if (typeof fileReadStream === 'function') {
        callback = fileReadStream;
        fileReadStream = null;
    }
    
    if (!isDefined(psUpload)) {
        callback("**** Error: No psUpload was given");
        return;
    }
    
    self.sendFileUsingMultipleAttempts(psUpload, fileReadStream, maxNumberSendAttempts, function (error) {
        callback(error);
    });
}

// PRIVATE (only part of the prototype so I can access member variables).
// Callback: One param: error
FileTransfers.prototype.sendFileUsingMultipleAttempts =
    function (psUpload, fileReadStream, remainingSendAttempts, callback) {
        var self = this;
    
        var currentSendAttempt = maxNumberSendAttempts - remainingSendAttempts + 1;
        
        logger.info("Send attempt " + currentSendAttempt + " for file: " + JSON.stringify(psUpload));
        
        var fileToSend = new File(psUpload.userId, psUpload.deviceId, psUpload.fileId);
        fileToSend.cloudFileName = psUpload.cloudFileName;
        fileToSend.mimeType = psUpload.mimeType;
        fileToSend.fileReadStream = fileReadStream;
            
        if (psUpload.fileUpload) {
           self.cloudStorage.outboundTransfer(fileToSend, function (err, fileProperties) {
                self.finishSendFile(err, fileReadStream, remainingSendAttempts, currentSendAttempt, psUpload, fileProperties, callback);
            });
        }
        else {
            self.cloudStorage.deleteFile(fileToSend, function (err, fileProperties) {
                self.finishSendFile(err, fileReadStream, remainingSendAttempts, currentSendAttempt, psUpload, fileProperties, callback);
            });
        }
    }

// PRIVATE
FileTransfers.prototype.finishSendFile = function (err, fileReadStream, remainingSendAttempts, currentSendAttempt, psUpload, fileProperties, callback) {

    var self = this;
    
    if (err) {
        logger.error("Error sending/removing file on attempt %d: %j", currentSendAttempt, err);
        
        if (remainingSendAttempts <= 0) {
            callback("*** Error sending/removing file to cloud storage");
        }
        else {
            self.sendFileUsingMultipleAttempts(psUpload, fileReadStream,
                remainingSendAttempts - 1, callback);
        }
    }
    else {
        // Success sending the file from the SyncServer to cloud storage.

        var query = {
            fileId: psUpload.fileId,
            userId: psUpload.userId,
            cloudFileName: psUpload.cloudFileName
        };
        
        var updatedProperties = {};
        
        if (psUpload.fileUpload) {
            updatedProperties.state = PSUpload.uploadedState;
            updatedProperties.fileSizeBytes = fileProperties.fileSizeBytes;
        }
        else { // upload-deletion
            updatedProperties.state = PSUpload.toPurgeState;
        }
        
        var update = {
            $set: updatedProperties
        };
        
        Mongo.Upload.findOneAndUpdate(query, update, function (err, psUpload) {
            if (err || !psUpload) {
                var message = "Error updating PSUpload." + " error: " + JSON.stringify(err);
                logger.error(message);
                callback(message);
            }
            else {
                callback(null);
            }
        });
    }
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
        fileToReceive.cloudFileName = inboundFile.cloudFileName;
        fileToReceive.mimeType = inboundFile.mimeType;

        // Increment operationCount of the PSOperationId so we can distinguish between two main kinds of failures and recovery for the app/client: Errors that occurred prior to any transfer of data from cloud storage and errors that occurred after possible transfer of data.
        // Note that the accuracy of the operationCount field of the PSOperationId is by no means guaranteed. E.g., if the psOperationId update succeeds, but the receiveFile fails, and then later a recovery redoes this process, the PSOperationId operationCount will be inaccurate.
        
        self.psOperationId.operationCount++;
        self.psOperationId.error = null;
        
        self.psOperationId.update(function (error) {
            if (error) {
                callback(error);
                return;
            }

            self.cloudStorage.inboundTransfer(fileToReceive, function (error, fileProperties) {
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
                    
                    logger.trace("Success receiving file from cloud storage!");
                    logger.info("Updating inboundFile: %j", inboundFile);

                    inboundFile.received = true;
                    inboundFile.update(function (error) {
                        callback(error);
                    });
                }
            });
        });
    }

// export the class
module.exports = FileTransfers;

/* Notes on recovery:

You can use a two phase commit, but that looks more complex than my algorithms already https://docs.mongodb.org/manual/tutorial/perform-two-phase-commits/
*/

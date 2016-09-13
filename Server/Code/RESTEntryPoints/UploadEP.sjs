var logger = require('../Logger');
var Operation = require('../Operation');
var ServerConstants = require('../ServerConstants');
var Busboy = require('busboy');
var inspect = require('util').inspect;
var fs = require('fs');
var Mongo = require('../Mongo');
var PSUpload = require('../PSUpload');
var FileTransfers = require('../FileTransfers');
var ClientFile = require('../ClientFile');
var PSFileIndex = require('../PSFileIndex');
var File = require('../File');

// Not used, but needed to define name.
function UploadEP() {
}

// START DEBUGGING
/*
app.post('/' + ServerConstants.operationUploadFile, upload, function (request, response) {
	console.log(JSON.stringify(request.file));
	var result = {};
	response.end(JSON.stringify(result));
});
*/
// END DEBUGGING

// Going to allow two (sequential) uploads of the same file, in order to enable recovery on the client. The second upload will not duplicate info in PSOutboundFileChange's.
UploadEP.uploadFile = function (request, response) {
    
    // I'm using Busboy to make it easier to get the file as a stream.
    // By the time we get to the Busboy `finish` event, the fileStream is no longer valid. So, it seems we have to use the stream in the `file` event directly.
    // I'm sending the parameters in the HTTP headers because I don't think I can be assured of the ordering of the Busboy `field` event versus the `file` event.
    // Earlier I was having another issue with parameters. See also https://stackoverflow.com/questions/37449472/afnetworking-v3-1-0-multipartformrequestwithmethod-uploads-json-numeric-values-w/37684827#37684827
    
    var busboy = new Busboy({ headers: request.headers });
    busboy.on('file', function(fieldname, fileStream, filename, encoding, mimetype) {
        logger.debug('File [' + fieldname + ']: filename: ' + filename);
        
        // fileStream.pipe(fs.createWriteStream("./OUTPUT_FILE.txt"));
              
        var paramsForUpload = request.headers[ServerConstants.httpUploadParamHeader];
        
        // I got an issue: "SyntaxError: Unexpected token u in JSON at position 0" at this position in the code. Which came from bad upload parameters.  See http://stackoverflow.com/questions/13022178/uncaught-syntaxerror-unexpected-token-u-json
        // Putting in an error test case for that.
    
        if (!isDefined(paramsForUpload)) {
            var message = "Undefined upload parameters";
            logger.error(message);
            op.endWithErrorDetails(message);
            return;
        }
        
        request.body = JSON.parse(paramsForUpload);
        
        operationUploadFile(fileStream, request, response);
    });
    
    request.pipe(busboy);
};

function operationUploadFile(fileStream, request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    const undeleteFileKey = request.body[ServerConstants.undeleteFileKey];
    
    op.validateUser(function () {
        // User is on the system.
                
        var clientFile = null;
        try {
            clientFile = new ClientFile(request.body);
        } catch (error) {
            logger.error(error);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, error);
            return;
        }
        
        if (!op.endIfUserNotAuthorizedFor(ServerConstants.sharingUploader)) {
            return;
        }
        
        /* Need to do some basic checking on this file in the PSFileIndex.
            a) Has this cloudFileName been used before for a different clientFileId?
                TODO: Actually, we may want to allow this. If a file is deleted, we will want to be able to reuse its cloudFileName.
            b) Is the version number +1 from the last?
        */
        // Need also to make similar checks in PSOutboundFileChange -- i.e., not only must the file we're uploading not exist in the file index but it also mustn't already exist in the set of files we're currently uploading.
        
        // This fileData is used across PSFileIndex and PSUpload in checkIfFileExists
        var fileData = {
            userId: op.userId(),
            fileId: clientFile[ServerConstants.fileUUIDKey]
        };
        
        // 1) Do this first, with the userId and file UUID.
        checkIfFileExists(fileData, function (error, fileIndexObj, psUploadObj) {
            if (error) {
                logger.error(error);
                op.endWithErrorDetails(error);
                return;
            }
                          
            if (isDefined(fileIndexObj)) {
                if (fileIndexObj.deleted && !isDefined(undeleteFileKey)) {
                    var errorMessage = "File was already deleted!";
                    logger.error(errorMessage);
                    op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, errorMessage);
                    return;
                }
                
                var errorMessage = fileIndexObj.checkNewFileVersion(clientFile[ServerConstants.fileVersionKey]);
                if (isDefined(errorMessage)) {
                    logger.error(errorMessage);
                    op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, errorMessage);
                    return;
                }
            }
            
            // I'm not going to make it an error to attempt an undeletion when a file hasn't already been marked for deletion. This is because we can have a race condition where multiple apps could try to do the undeletion.

            if (isDefined(fileIndexObj) && fileIndexObj.deleted && isDefined(undeleteFileKey)) {
            
                // Need to undelete file in file index before completing the upload.
                
                fileIndexObj.deleted = false;
                
                var sameFileIndexVersionIfExists = true
                fileIndexObj.updateOrStoreNew(sameFileIndexVersionIfExists, function (error) {
                    if (error) {
                        var errorMessage = "updateOrStoreNew: Error: " + error;
                        logger.debug(errorMessage);
                        op.endWithErrorDetails(errorMessage);
                    }
                    else {
                        completeOperationUploadFile(op, psUploadObj, fileStream, clientFile, request);
                    }
                });
            }
            else {
                // Complete the upload.
                completeOperationUploadFile(op, psUploadObj, fileStream, clientFile, request);
            }
        });
    });
}

function completeOperationUploadFile(op, psUploadObj, fileStream, clientFile, request) {
    var createUploadObj = true;
    
    if (psUploadObj) {
        // To enable recovery, not going to consider this an error, as long as the cloud file name matches up too.
        if (clientFile[ServerConstants.cloudFileNameKey] == psUploadObj.cloudFileName) {
            createUploadObj = false;
            logger.info("Uploading two instances with same file id and cloud file name");
        }
        else {
            var message = "Attempting to upload two instances of the same file id, but without the same cloud file name";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError,
                        message);
            return;
        }
    }
    
    // This fileData is used across PSFileIndex and PSUpload in checkIfFileExists
    var fileData = {
        userId: op.userId(),
        cloudFileName: clientFile[ServerConstants.cloudFileNameKey]
    };
    
    // 2) Then, a second time with userId and cloudFileName
    checkIfFileExists(fileData, function (error, fileIndexObj, psUploadObj) {
        if (error) {
            logger.error(error);
            op.endWithErrorDetails(error);
            return;
        }
        
        if (fileIndexObj) {
            // Make sure the fileId of this file is the same as clientFileId-- since the files have the same cloudFileName they must have the same UUID.
            if (fileIndexObj.fileId != clientFile[ServerConstants.fileUUIDKey]) {
                // This is a rcServerAPIError error because the API client made an error-- they shouldn't have given the same cloudFileName with different UUID's.
                var message = "Two files with same cloudFileName, but different UUID's; cloudFileName: " + clientFile[ServerConstants.cloudFileNameKey];
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError,
                    message);
                return;
            }
        }
        
        if (psUploadObj) {
            if (clientFile[ServerConstants.fileUUIDKey] == psUploadObj.fileId && !createUploadObj) {
                logger.info("Uploading two instances with same file id and cloud file name");
            }
            else {
                var message = "Attempting to upload two files with the same cloudFileName";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError,
                        message);
                return;
            }
        }
        
        // TODO: Validate that the mimeType is from an acceptable list of MIME types (e..g, so we don't get an injection error with someone injecting a special Google Drive object such as a folder).
                      
        var localFile = new File(op.userId(), op.deviceId(), clientFile[ServerConstants.fileUUIDKey]);
        localFile.cloudFileName = clientFile[ServerConstants.cloudFileNameKey];

        if (createUploadObj) {
            var upload = new Mongo.Upload({
                fileId: clientFile[ServerConstants.fileUUIDKey],
                userId: op.userId(),
                deviceId: op.deviceId(),
                cloudFileName: localFile.cloudFileName,
                mimeType:clientFile[ServerConstants.fileMIMEtypeKey],
                appMetaData: clientFile[ServerConstants.appMetaDataKey],
                fileUpload: true,
                fileVersion: clientFile[ServerConstants.fileVersionKey],
                state: PSUpload.uploadingState
            });
            
            upload.save(function (err, upload) {
                if (err) {
                    logger.error("Failed attempting to save new PSUpload: %j", err);
                    op.endWithErrorDetails(err);
                }
                else {
                    logger.debug("New PSUpload: %j", upload);
                    sendFileToCloudStorage(op, fileStream, upload);
                }
            });
        }
        else {
            sendFileToCloudStorage(op, fileStream, psUploadObj);
        }
    });
}

function sendFileToCloudStorage(op, fileReadStream, psUpload) {
    var fileTransfers = new FileTransfers(op);
    fileTransfers.setup(function (error) {
        if (error) {
            logger.error("Failed doing setup for FileTransfer object: %j", error);
            op.endWithErrorDetails(error);
        }
        else {
            fileTransfers.sendFile(psUpload, fileReadStream, function (error) {
                if (error) {
                    logger.error("Failed doing sendFile: %j", error);
                    op.endWithErrorDetails(error);
                }
                else {
                    const query = {
                        fileId: psUpload.fileId,
                        userId: op.userId(),
                        deviceId: op.deviceId()
                    };
                    const update = { $set: {state: PSUpload.uploadedState} };
                    
                    Mongo.Upload.findOneAndUpdate(query, update, function (err, updatedDoc) {
                        if (err || !isDefined(updatedDoc)) {
                            var message = "Error updating PSUpload: " + JSON.stringify(err);
                            logger.error(message);
                            op.endWithErrorDetails(message);
                        }
                        else {
                            logger.debug("Successfully sent file to cloud storage.");
                            op.endWithRC(ServerConstants.rcOK);
                        }
                    });
                }
            });
        }
    });
}

/* 
Check to see if the file exists in the PSFileIndex or PSUpload. The parameter fileData doesn't have the deleted or toDelete property set, but has userId and optionally fileId and cloudFileName properties.
Callback has four parameters: 
    1) error, 
    2) if error is null, PSFileIndex object -- if the file exists in PSFileIndex
    3) if error is null, PSUpload -- if the file exists in PSUpload
*/
function checkIfFileExists(fileData, callback) {

    fileData.deleted = false;
    
    var fileIndexObj = null;
    try {
        fileIndexObj = new PSFileIndex(fileData);
    } catch (error) {
        callback(error, null, null);
        return;
    }
    
    fileIndexObj.lookup(function (error, fileExists) {
        if (error) {
            callback(error, null, null);
        }
        else {
            if (!fileExists) {
                fileIndexObj = null;
            }
            
            delete fileData.deleted;
                        
            Mongo.Upload.findOne(fileData, function (error, psUpload) {
                if (error) {
                    callback(error, null, null);
                }
                else {
                    callback(null, fileIndexObj, psUpload);
                }
            });
        }
    });
}

/* This doesn't remove any PSOperationId on an uplod error because the client/app may be in the middle of a long series of uploads/deletes and may need to retry a specific upload.
    This can be called multiple times from the client with the same parameters. Once the info for a specific file to be deleted is entered into the PSOutboundFileChange, it will not be entered a second time. E.g., with no failure the first time around, calling this a second time has no effect and doesn't cause an error.
*/
UploadEP.deleteFiles = function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        if (isDefined(psOperationId) && (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus)) {
            // This check is to deal with error recovery.
            var message = "Error: Operation is already in progress!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId) && (psOperationId.operationType != "Outbound")) {
            var message = "Error: Not doing outbound operation!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            if (!op.endIfUserNotAuthorizedFor(ServerConstants.sharingUploader)) {
                return;
            }
            
            // We're getting an array of file descriptions from the client.

            var clientFileArray = null;
            try {
                clientFileArray =
                    ClientFile.objsFromArray(request.body[ServerConstants.filesToDeleteKey]);
            } catch (error) {
                logger.error(error);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, error);
                return;
            }
            
            if (clientFileArray.length == 0) {
                var message = "No files given to delete.";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }
            
            // Only adds the upload-deletion into the PSOutboundFileChanges if it is not already there.
            function addToOutboundIfNew(clientFile, callback) {
                addDeletionToOutboundIfNew(op, clientFile, function (error) {
                    callback(error);
                });
            }
            
            Common.applyFunctionToEach(addToOutboundIfNew, clientFileArray, function (error) {
                if (error) {
                    op.endWithErrorDetails(error);
                }
                else {
                    op.endWithRC(ServerConstants.rcOK);
                }
            });
        }
    });
};

// The callback has one parameter: error.
function addDeletionToOutboundIfNew(op, clientFile, callback) {
    // This fileData is used across PSFileIndex and PSUpload in checkIfFileExists
    var fileData = {
        userId: op.userId(),
        fileId: clientFile[ServerConstants.fileUUIDKey]
    };
    
    checkIfFileExists(fileData, function (error, fileIndexObj, psUploadObj) {
        if (error) {
            callback(error);
            return;
        }
        
        // Make sure this file isn't deleted already. i.e., that it's not marked as deleted in the PSFileIndex.
        if (fileIndexObj) {
            if (fileIndexObj.deleted) {
                callback(new Error("File was already deleted in the PSFileIndex"));
                return;
            }
        }
        
        // Check if the file is already scheduled for deletion in the outbound file changes.
        if (psUploadObj) {
            logger.info("Attempting to upload-delete two instances of the same file id");
            callback(null);
        }
        else {
            var markForDeletion = true;
            addToOutboundFileChanges(op, clientFile, markForDeletion, function (error) {
                callback(error);
            });
        }
    });
}

// Record the fact of this upload or delete using PSOutboundFileChange.
// Callback takes a single parameter, error.
function addToOutboundFileChanges(op, clientFile, deleteIfTrue, callback) {
    
    var fileMetaData = {
        fileId: clientFile[ServerConstants.fileUUIDKey],
        userId: op.userId(),
        deviceId: op.deviceId(),
        toDelete: deleteIfTrue,
        cloudFileName: clientFile[ServerConstants.cloudFileNameKey],
        mimeType: clientFile[ServerConstants.fileMIMEtypeKey],
        fileVersion: clientFile[ServerConstants.fileVersionKey]
    };
    
    if (isDefined(clientFile[ServerConstants.appMetaDataKey])) {
        fileMetaData.appMetaData = clientFile[ServerConstants.appMetaDataKey];
    }

    var outboundFileChange = null;
    
    try {
        outboundFileChange = new PSOutboundFileChange(fileMetaData);
    } catch (error) {
        callback(error);
        return;
    }
    
    outboundFileChange.storeNew(function (err) {
        callback(err);
    });
}

UploadEP.finishUploads = function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        // User is on the system.
        
        if (!op.endIfUserNotAuthorizedFor(ServerConstants.sharingUploader)) {
            return;
        }
        
        const expectedFileIndexVersion = request.body[ServerConstants.fileIndexVersionKey];
        if (!isDefined(expectedFileIndexVersion)) {
            var message = "No fileIndexVersion given."
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        /*
         Algorithm:
         
         1) Get lock on PSFileIndex.
            a) Check to see if the global version number for the owning user matches that given as an upload parameter.
            b) If it does, go forward.
            c) If not, then mark the file-uploads in PSUpload as "to purge".
                    And Delete any upload-deletion entries in PSUpload
                    And release lock on PSFileIndex.
         
         2) Do the updates:
            a) For file-uploads in PSUpload,
                i) Enter that data or update the entries in the PSFileIndex
                ii) Remove these PSUpload entries
         
            b) For upload-deletions in PSUpload,
                i) Mark the entries as `deleted` in the PSFileIndex.
                ii) Mark the entries in the PSUpload as "to purge"
         
         3) Increment the global version number for the owning user.
         
         4) Release lock on PSFileIndex.
         
         Assumption:
            Since a lock is held during this entire process, we assume that this process will not take "too long". What I mean by this is that this process should take place in effectively constant time, not time directly related to the number of uploads that has taken place.
        */
        
        finishUploadsGetLock(op, expectedFileIndexVersion, function (versionAsExpected, error) {
            if (error) {
                op.endWithErrorDetails(error);
                return;
            }
            else if (!versionAsExpected) {
                op.endWithRCAndErrorDetails(
                    ServerConstants.rcFileIndexVersionDifferentThanExpected,
                    "file index version different than expected");
                return;
            }
            
            // Got the lock and the global version was as expected: We can make the updates to the PSUpload, and then release the lock.
                        
            finishUploadsDoUpdates(op, function (error) {
                if (error) {
                    op.endWithErrorDetails(error);
                    return;
                }
    
                const update = { $inc: { version: 1} };
                
                Mongo.GlobalVersion.findOneAndUpdate({ userId: op.userId() }, update, function (err, doc) {
                    if (err || !doc) {
                        const message =
                            "Could not update GlobalVersion: " + JSON.stringify(err);
                        logger.error(message);
                        op.endWithErrorDetails(message);
                        return;
                    }
                    
                    Mongo.fileIndexLock.release(function(err, lockTimedOut) {
                        if (err || lockTimedOut) {
                            const message = "Could not release lock at end of operation: " + JSON.stringify(err);
                            logger.error(message);
                            op.endWithErrorDetails(message);
                            return;
                        }
                        
                        op.endWithRC(ServerConstants.rcOK);
                    });
                });
            });
        });
    });
};

// Callback has two parameters:
// 1) Boolean: true iff global version number was as expected (but null if there is an error).
// 2) error
// TODO: Currently, when I get an error condition *after* obtaining the lock, I'm not releasing the lock. Probably I should release the lock in those conditions.
function finishUploadsGetLock(op, expectedVersion, callback) {
    Mongo.fileIndexLock.pollAquire(function(err, lockAcquired) {
        if (err || !lockAcquired) {
            var message = "Could not acquire the lock: " + JSON.stringify(err);
            logger.error(message);
            callback(null, message);
            return;
        }

        logger.debug("Lock was successfully acquired.");
        
        Mongo.GlobalVersion.findOne({ userId: op.userId() }, function (err, globalVersionDoc) {
            if (err) {
                callback(null, err);
                return;
            }
            else if (!isDefined(globalVersionDoc)) {
                callback(null, "No global version for: " + op.userId());
                return;
            }
            else if (globalVersionDoc.version == expectedVersion) {
                // This our typical expected use/return case.
                logger.trace("Got expected file index version for: " + op.userId());
                callback(true, null);
                return;
            }
            
            // We didn't get the expected global version: Presumably there was an update to the PSFileIndex between the time of a download and the time of the attempted operationFinishUploads.
            
            // Need to cleanup:
            // a) mark the file-uploads in PSUpload as "to purge".
            // b) delete any upload-deletion entries in PSUpload
            // c) release lock on PSFileIndex.
            
            const query = {
                userId: op.userId(),
                deviceId: op.deviceId(),
                state: PSUpload.uploadedState,
                fileUpload: true
            };
            const update = { state: PSUpload.toPurgeState };
            
            Mongo.Upload.update(query, update, { multi: true }, function (err) {
                if (err) {
                    const message = "Could not mark uploaded files as `to purge`: " + JSON.stringify(err);
                    logger.error(message);
                    callback(null, message);
                    return;
                }

                const query = {
                    userId: op.userId(),
                    deviceId: op.deviceId(),
                    fileUpload: false // upload-deletions
                };
                
                Mongo.Upload.remove(query, function (err) {
                    if (err) {
                        const message = "Could not remove upload-deletion entries: " + JSON.stringify(err);
                        logger.error(message);
                        callback(null, message);
                        return;
                    }
                    
                    Mongo.fileIndexLock.release(function(err, lockTimedOut) {
                        if (err || lockTimedOut) {
                            const message = "Could not release lock: " + JSON.stringify(err);
                            logger.error(message);
                            callback(null, message);
                            return;
                        }
                        
                        // Note that the 1st parameter is false-- indicating that the global version number was not that expected. The error parameter is null indicating we didn't get an error-- we were able to clean up appropriately.
                        callback(false, null);
                    });
                });
            });
        });
    });
}

// Single parameter on callback-- error
function finishUploadsDoUpdates(op, callback) {
    // Fetch the documents we need to update from PSUpload:
    
    var query = {
        userId: op.userId(),
        deviceId: op.deviceId()
    };
                
    Mongo.Upload.find(query, function (err, uploadDocs) {
        if (err) {
            callback(err);
            return;
        }
        
        // Prepare the bulk upsert for the PSFileIndex based on the PSUpload documents.
        // TODO: Can we make sure this upsert takes place in an all-or-nothing atomic manner?
        var fileIndexUpsert = PSFileIndex.collection().initializeUnorderedBulkOp();
        
        // At the same time, prepare the update for the PSUpload collection.
        var uploadUpdate = Mongo.Upload.collection.initializeUnorderedBulkOp();
        
        uploadDocs.forEach(function (uploadDoc, index, array) {
            // I've been getting an infinite loop if I use `uploadDoc` directly as the query below.
            const fileIndexQuery = {
                userId: uploadDoc.userId,
                fileId: uploadDoc.fileId,
                deleted: false
            };
            
            const uploadQuery = {
                userId: uploadDoc.userId,
                fileId: uploadDoc.fileId,
                deviceId: uploadDoc.deviceId
            };
            
            if (uploadDoc.fileUpload) {
                var fileIndexDoc = {
                    userId: uploadDoc.userId,
                    fileId: uploadDoc.fileId,
                    cloudFileName: uploadDoc.cloudFileName,
                    mimeType: uploadDoc.mimeType,
                    appMetaData: uploadDoc.appMetaData,
                    deleted: false,
                    fileVersion: uploadDoc.fileVersion,
                    lastModified: Date(),
                    fileSizeBytes: uploadDoc.fileSizeBytes
                };

                fileIndexUpsert.find(fileIndexQuery).upsert().updateOne({$set: fileIndexDoc});
                
                // These entries are removed because the referenced files are now referenced from the PSFileIndex.
                uploadUpdate.find(uploadQuery).remove();
            }
            else {
                // upload-deletion
                fileIndexUpsert.find(fileIndexQuery).updateOne({ $set: {deleted: true}});
                
                // These entries are marked as "to purge" because later, the referenced files need to be removed from cloud storage.
                const update = { $set: {state: PSUpload.toPurgeState}};
                uploadUpdate.find(uploadQuery).updateOne(update);
            }
        });
        
        function bulkExecute(operationCount, bulk, callback) {
            if (operationCount > 0) {
                bulk.execute(callback);
            }
            else {
                callback(null, null);
            }
        }
                
        bulkExecute(uploadDocs.length, fileIndexUpsert, function (error, result) {
            if (error) {
                const message =
                    "Could not execute the fileIndexUpsert: " + JSON.stringify(error);
                logger.error(message);
                callback(message);
                return;
            }

            // TODO: What if we get a failure after this but before we are able to update the Uploads collection to indicate that file-uploads have been transfered to the PSFileIndex? The Upload documents haven't yet been marked as toPurgeState and are marked as uploadedState. So, we ought to be able to, later, do a consistency check to see if there are entries in the PSFileIndex with the same version that are marked as uploadedState.
                    
            bulkExecute(uploadDocs.length, uploadUpdate, function (error, result) {
                if (error) {
                    const message =
                        "Could not execute the uploadUpdate: " + JSON.stringify(error);
                    logger.error(message);
                    callback(message);
                    return;
                }
                
                callback(null);
            });
        });
    });
}

// export the class
module.exports = UploadEP;

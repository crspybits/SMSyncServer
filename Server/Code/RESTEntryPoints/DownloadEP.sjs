var logger = require('../Logger');
var Operation = require('../Operation');
var ServerConstants = require('../ServerConstants');
var File = require('../File.sjs')

// Not used, but needed to define name.
function DownloadEP() {
}

if (! "DEBUG") {

// Makes entries in PSInboundFile for each of the inbound files. Doesn't start the inbound transfers. This server API entry point can be called multiple times with the same parameters-- for recovery purposes. The 2nd time, etc., has no effect and doesn't fail.
app.post('/' + ServerConstants.operationSetupInboundTransfers, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        // User is on the system.

        var localFiles = new File(op.userId(), op.deviceId());
        
        if (isDefined(psOperationId)) {
            // Should not already have an operationId because this is is going to create an operationId.
            var message = "There is already an operationId!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            if (!op.endIfUserNotAuthorizedFor(ServerConstants.sharingDownloader)) {
                return;
            }
            
            logger.info("Parameters for files to transfer from cloud storage: %j", request.body[ServerConstants.filesToTransferFromCloudStorageKey]);

            var clientFileArray = null;
            const requiredProps = [ServerConstants.fileUUIDKey];
            try {
                clientFileArray = ClientFile.objsFromArray(request.body[ServerConstants.filesToTransferFromCloudStorageKey], requiredProps);
            } catch (error) {
                logger.error(error);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, error);
                return;
            }
            
            logger.info("Files to transfer from cloud storage: %j", clientFileArray);
            
            if (clientFileArray.length == 0) {
                var message = "No files given to transfer from cloud storage.";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }
            
            // Need to create PSInboundFile's for each of the files to be transferred.
            function createInboundFile(clientFile, callback) {
                var inboundFile = null;
                
                var fileMetaData = {
                    fileId: clientFile[ServerConstants.fileUUIDKey],
                    userId: op.userId(),
                    deviceId: op.deviceId()
                };
                
                // We want to generally lookup the inbound file at [4] below, so don't provide a .received property. But, we'll provide it, later, at [5] below if the lookup doesn't find the inbound file.
                const mustHaveReceivedProperty = false;
                
                try {
                    inboundFile = new PSInboundFile(fileMetaData, mustHaveReceivedProperty);
                } catch (error) {
                    op.endWithErrorDetails(error);
                    return;
                }

                /* Look up the corresponding PSFileIndex object for two reasons:
                    1) To add cloudFileName and mimeType to the PSInboundFile object.
                    2) To make sure we actually have this file in our file index. It wouldn't make sense to try to do an inbound file transfer with a file not in our file index.
                */
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
                    else if (!objectFound) {
                        callback(new Error("File not found: %j", fileIndexObj));
                    }
                    else if (fileIndexObj.deleted) {
                        callback(new Error("File marked as deleted: %j", fileIndexObj));
                    }
                    else {
                        // [4]. SO, we *do* have this file in our file index. Let's make sure it's not already in our PSInboundFile files. This check is both an error check and a recovery check. In some recovery situations (e.g., when we try to do two inbound transfers back to back), without this check, we'll get double entries in the PSInboundFile collection.
                        
                        inboundFile.lookup(function (error, inboundFileAlreadyExists) {
                            if (error) {
                                callback(error);
                            }
                            else if (inboundFileAlreadyExists) {
                                logger.trace("File is already inbound: %j", inboundFile);
                                callback(null);
                            }
                            else {
                                // This is a new inbound file! Store it in the PSInboundFile's.
                                logger.trace("New inbound file: %j", inboundFile);
                                
                                inboundFile.cloudFileName = fileIndexObj.cloudFileName;
                                inboundFile.mimeType = fileIndexObj.mimeType;
                                
                                // [5]. We didn't provide the .received property on the inbound file when we created the object. Provide it now.
                                inboundFile.received = false;
                                
                                inboundFile.storeNew(function (error) {
                                    callback(error);
                                });
                            }
                        });
                    }
                });
            }
            
            Common.applyFunctionToEach(createInboundFile, clientFileArray, function (error) {
                if (error) {
                    op.endWithErrorDetails(error);
                }
                else {
                    op.endWithRC(ServerConstants.rcOK);
                }
            });
        }
    });
});

// Initiates an asynchronous operation transferring files from cloud storage. REST/API caller provides the list of files to be transferred. operationSetupInboundTransfers must have already been called or this will fail.
app.post('/' + ServerConstants.operationStartInboundTransfer, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        // User is on the system.

        var localFiles = new File(op.userId(), op.deviceId());
        
        if (!isDefined(psLock)) {
            // Recovery case. Check to see if there is an operationId-- look it up by userId/deviceId.
            noLockRecoveryForTransfer(op, "Inbound");
        }
        else if (isDefined(psOperationId)) {
            // Recovery case. If there is a lock and there is an operationId, then we've already started the operation.
            
            if (psOperationId.operationType != "Inbound") {
                var message = "Error: Not doing inbound operation!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            }
            else {
                inboundTransferRecovery(op, psLock, psOperationId);
            }
        }
        else {
            PSInboundFile.getAllFor(op.userId(), op.deviceId(), function (error, inboundFiles) {
                if (error) {
                   op.endWithErrorDetails(error);
                }
                else if (inboundFiles.length == 0 ) {
                    logger.error("No inbound files to receive.");
                     // This is an API error because we should not get here without some files ready to start on inbound transfer.
                    op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                }
                else {
                    var psOperationId = null;
                    
                    // Default for PSOperationId operationStatus will be rcOperationStatusNotStarted. We'll set the status to InProgress below (see [1]), just before we actually spin off the operation as asynchronous.
                    const operationData = {
                        operationType: "Inbound",
                        userId: op.userId(),
                        deviceId: op.deviceId()
                    };
                    
                    try {
                        psOperationId = new PSOperationId(operationData);
                    } catch (error) {
                        op.endWithErrorDetails(error);
                        return;
                    };
                    
                    psOperationId.storeNew(function (error) {
                        if (error) {
                            op.endWithErrorDetails(error);
                        }
                        else {
                            // Need to add the operationId into the psLock.
                            psLock.operationId = psOperationId._id;
                            psLock.update(function (error) {
                                if (error) {
                                    op.endWithErrorDetails(error);
                                }
                                else {
                                    // [1]. Using startTransferOfFiles method so we can use the dbTcInProgress test.
                                    startTransferOfFiles(op, psLock, psOperationId, FileTransfers.methodNameReceiveFiles);
                                }
                            });
                        }
                    });
                }
            });
        }
    });
});

// transferDirection can be "Inbound" or "Outbound"
function noLockRecoveryForTransfer(op, transferDirection) {
    PSOperationId.getFor(null, op.userId(), op.deviceId(), function (error, psOperationId) {
        if (error) {
            op.endWithErrorDetails(error);
        }
        else if (!isDefined(psOperationId)) {
        
            // No lock and no operation id. A misuse of the server API.
            var message = "Error: Don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            
        }
        else if ((ServerConstants.rcOperationStatusFailedAfterTransfer ==
                psOperationId.operationStatus ||
                ServerConstants.rcOperationStatusSuccessfulCompletion ==
                psOperationId.operationStatus) &&
                transferDirection == psOperationId.operationType) {
                
            // Recovery situation: No lock, we do have an Operation Id, and we (may have) had a failure after outbound transfer.
            
            logger.info("Returning operationId to client: " + psOperationId._id);
            op.result[ServerConstants.resultOperationIdKey] = psOperationId._id;
            
            // Call this "Successful" so that the app can be move on and remove the operation id.
            
            updateOperationId(psOperationId,
                ServerConstants.rcOperationStatusSuccessfulCompletion, null);
            logger.trace("Successfully completed operation!");
            op.endWithRC(ServerConstants.rcOK);
            
        } else {
            op.endWithErrorDetails("Operation Id present, no lock, but unknown situation!");
        }
    });
}

function inboundTransferRecovery(op, psLock, psOperationId) {
    // Always returning operationId, just for uniformity.
    
    logger.info("Returning operationId to client: " + psOperationId._id);
    op.result[ServerConstants.resultOperationIdKey] = psOperationId._id;
    
    switch (psOperationId.operationStatus) {
    case ServerConstants.rcOperationStatusNotStarted:
    case ServerConstants.rcOperationStatusFailedBeforeTransfer:
    case ServerConstants.rcOperationStatusFailedDuringTransfer:
        // startTransferOfFiles sends back completion info to the server API callee.
        startTransferOfFiles(op, psLock, psOperationId, FileTransfers.methodNameReceiveFiles);
        break;

    case ServerConstants.rcOperationStatusFailedAfterTransfer:
        psLock.removeLock(function (error) {
            if (objOrInject(error, op,
                ServerConstants.dbTcRemoveLockAfterCloudStorageTransfer)) {
                var errorMessage = "Failed to remove the lock: " + JSON.stringify(error);
                logger.error(errorMessage);
                op.endWithErrorDetails(errorMessage);
            }
            else {
                logger.trace("Removed the lock.");
                updateOperationId(psOperationId, ServerConstants.rcOperationStatusSuccessfulCompletion, null);
                logger.trace("Successfully completed operation!");
                op.endWithRC(ServerConstants.rcOK);
            }
        });
        break;
        
    case ServerConstants.rcOperationStatusInProgress:
    case ServerConstants.rcOperationStatusSuccessfulCompletion:
        var message = "Operation was InProgress or Completed -- Not doing transfer recovery.";
        logger.debug(message);
        op.endWithRC(ServerConstants.rcOK);
        break;
        
    default:
        var message = "Yikes: Unknown operationStatus: " + psOperationId.operationStatus;
        logger.error(message);
        op.endWithErrorDetails(message);
        break;
    }
}

} // End "DEBUG"

DownloadEP.downloadFile = function (request, response) {
    // logger.debug("DownloadFile operation: %j", request.body);

    // rc, and errorMessage are optional, but if given, must be given together.
    function endDownloadWithError(op, rc, errorMessage) {
        var clientResultInfo = null;
        
        if (isDefined(rc)) {
            clientResultInfo = op.prepareToEndDownloadWithRCAndErrorDetails(rc, errorMessage);
        }
        else {
            clientResultInfo = op.prepareToEndDownload();
        }
        
        response.setHeader(ServerConstants.httpDownloadParamHeader, clientResultInfo);
        op.end();
    }
    
    var op = new Operation(request, response);
    if (op.error) {
        endDownloadWithError(op);
        return;
    }

    op.validateUser(function () {
        getDownloadFileInfo(request, op, function (error, returnCode, psInboundFile) {
            if (objOrInject(error, op, ServerConstants.dbTcGetDownloadFileInfo)) {
                endDownloadWithError(op, returnCode, error);
            }
            else {
               // Can download the file.
                
                var localFile = new File(op.userId(), op.deviceId(), psInboundFile.fileId);
                var fileNameWithPathToDownload = localFile.localFileNameWithPath();
                        
                const clientFileName = "download"
                const downloadFileMimeType = psInboundFile.mimeType;
                
                var clientResultInfo = op.prepareToEndDownloadWithRC(ServerConstants.rcOK);
                logger.trace("Sending response back to client: " + clientResultInfo);

                response.setHeader('Content-Type', downloadFileMimeType);
                response.setHeader('Content-disposition', 'attachment; filename=' + clientFileName);
                response.setHeader(ServerConstants.httpDownloadParamHeader, clientResultInfo);

                // Start download.
                // See http://stackoverflow.com/questions/7288814/download-a-file-from-nodejs-server-using-express
                // And http://code.runnable.com/UTlPPF-f2W1TAAEW/download-files-with-express-for-node-js
                // And http://expressjs.com/en/api.html
                response.download(fileNameWithPathToDownload);
                
                // I'm not going to remove this from PSInboundFile's immediately after the download has completed, nor am I going to remove the file from local storage. I'm going to provide a separate API method for the client to do that-- in case of some kind of error (e.g., on the client side), where the client wants to retry the download.
            }
        });
    });
};

if (! "DEBUG") {

// Enable the client to remove a downloaded file from the PSInboundFile's, and from local storage on the sync server. Making this a separate operation from the download itself to ensure that the download is successful-- and to enable retries of the download.
app.post('/' + ServerConstants.operationRemoveDownloadFile, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        // User is on the system.
        
        // TODO: It seems odd here to be removing PSInboundFile information without any sort of a lock. In principle there is a race condition between getting the info on the inbound file, and removing that entry from Mongo (the race will be between the device/app instance and itself, however). The worst case situation would seem to be that we get stuck in a cycle of trying to remove the file info from the collection but it's not there, so we fail and try again. It seems we could handle this in one of two ways: (1) use some other kind of lock, perhaps specific to PSInboundFile's. Or (2) not consider it to be an error if we try to remove the entry from PSInboundFile and don't find the entry there.
        getDownloadFileInfo(request, op, function (error, returnCode, psInboundFile) {
            if (error) {
                op.endWithRCAndErrorDetails(ServerConstants.rcOperationFailed, message);
            }
            else {
                psInboundFile.remove(function (error) {
                    if (error) {
                        op.endWithRCAndErrorDetails(ServerConstants.rcOperationFailed, error);
                    }
                    else {
                        op.endWithRC(ServerConstants.rcOK);
                    }
                });
            }
        });
    });
});

} // End "DEBUG"

// Pull info for a single file to be downloaded from HTTP request.
/* Callback has parameters:
    1) error
    2) if error, return code
    3) if no error, psInboundFile
 
*/
function getDownloadFileInfo(request, op, callback) {

    var clientFileObj = null;
    var requiredPropsParam = [ServerConstants.fileUUIDKey];
    
    try {
        clientFileObj = new ClientFile(request.body[ServerConstants.downloadFileAttributes], requiredPropsParam);
    } catch (error) {
        logger.error(error);
        callback(error, ServerConstants.rcServerAPIError, null);
        return;
    }
    
    logger.debug("File download info: %j", clientFileObj);
    
    // Lookup the file in PSInboundFile's
    var inboundFileData = {
        fileId: clientFileObj[ServerConstants.fileUUIDKey],
        userId: op.userId(),
        deviceId: op.deviceId(),
        received: true
    };
    
    var psInboundFile = null;
    
    try {
        psInboundFile = new PSInboundFile(inboundFileData);
    } catch (error) {
        logger.error(error);
        callback(error, ServerConstants.rcServerAPIError, null);
        return;
    }
    
    psInboundFile.lookup(function (error, fileIsPresent) {
        if (error) {
            callback(error, ServerConstants.rcOperationFailed, null);
        }
        else if (!fileIsPresent) {
            callback("File wasn't in PSInboundFile and marked as received!", ServerConstants.rcServerAPIError, null);
        }
        else {
            // Info for the file to be downloaded or deleted.
            callback(null, null, psInboundFile);
        }
    });
}

// export the class
module.exports = DownloadEP;


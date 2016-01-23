'use strict';

// Before the files get moved to their specific-user destination.
const initialUploadDirectory = './initialUploads/';

// TODO: What is safe mode in mongo? E.g., see https://mongodb.github.io/node-mongodb-native/api-generated/collection.html#insert
// See also options on insert https://mongodb.github.io/node-mongodb-native/api-generated/collection.html#insert
// Look at WriteConcern in mongo; see http://edgystuff.tumblr.com/post/93523827905/how-to-implement-robust-and-scalable-transactions
// WriteConcern is the same as safe mode http://api.mongodb.org/c/0.6/write_concern.html

// TODO: Need some logging to an external file: E.g., of error messages, of server failures/restarts (assuming that technically we can actually do that in [3] below), and other important events.
// TODO: It would also be good to log some analytics to a MongoDb collection for usage stats. E.g., the number of uploads/downloads etc. so we could do a little tracking of the amount of usage of the server. This wouldn't have to be on the basis of individual users-- it could be anonymized and comprise combined stats across all users.

var express = require('express');
var bodyParser = require('body-parser');
var app = express();
// https://github.com/expressjs/multer
var multer = require('multer');
var fse = require('fs-extra');

// Local modules.
var ServerConstants = require('./ServerConstants');
var Mongo = require('./Mongo');
var Operation = require('./Operation');
var PSLock = require('./PSLock');
var PSOutboundFileChange = require('./PSOutboundFileChange.sjs');
var FileTransfers = require('./FileTransfers');
var File = require('./File.sjs')
var logger = require('./Logger');
var PSOperationId = require('./PSOperationId.sjs');
var PSFileIndex = require('./PSFileIndex');
var Common = require('./Common');
var ClientFile = require('./ClientFile');

// See http://stackoverflow.com/questions/31496100/cannot-app-usemulter-requires-middleware-function-error
// See also https://codeforgeek.com/2014/11/file-uploads-using-node-js/
// TODO: Limit the size of the uploaded file.
// TODO: Is there a way with multer to add a callback that gets called periodically as an upload is occurring? We could use this to "refresh" an activity state for a lock to make sure that, even with a long-running upload (or download) if it is still making progress, that we wouldn't lose a lock.
var upload = multer({ dest: initialUploadDirectory}).single(ServerConstants.fileUploadFieldName)

// http://stackoverflow.com/questions/4295782/how-do-you-extract-post-data-in-node-js
app.use(bodyParser.json({extended : true}));

// Server main.
Mongo.connect();

app.post("/" + ServerConstants.operationCheckForExistingUser, function(request, response) {

    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }

    op.validateUser(false, function () {
        if (op.psUserCreds.stored) {
            op.endWithRC(ServerConstants.rcUserOnSystem);
        }
        else {
            op.endWithRC(ServerConstants.rcUserNotOnSystem);
        }
    });
});

app.post("/" + ServerConstants.operationCreateNewUser, function(request, response) {

    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    // Pass update as true as I'm assuming we *will* have an authorization code when creating a new user. (The authorization code is specific to Google).
    op.checkForExistingUser(true, function (error, staleUserSecurityInfo, psUserCreds) {
        if (error) {
            if (staleUserSecurityInfo) {
                op.endWithRCAndErrorDetails(ServerConstants.rcStaleUserSecurityInfo, error);
            }
            else {
                op.endWithErrorDetails(error);
            }
        }
        else {
            if (psUserCreds.stored) {
                op.endWithRC(ServerConstants.rcUserOnSystem);
            }
            else {
                // User creds not yet stored in Mongo. Store 'em.
                psUserCreds.storeNew(function (error) {
                    if (error) {
                        op.endWithErrorDetails(error);
                    }
                    else {
                        op.endWithRC(ServerConstants.rcOK);
                    }
                });
            }
        }
    });
});

// Failure mode analysis: On a failure, it is still possible that either one or both of these is true: 1) PSOperationId has been created, and 2) the lock has been created.
app.post('/' + ServerConstants.operationLock, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.
        
        // Need to make sure no lock is held right now. e.g., no other user with this same userId is changing files. It is possible (though unlikely) that between the time that we check to see a lock is held, then try to get the lock, that someone else got the lock. Since we're using the userId as the primary key into PSLock, only one attempt to create the lock will be successful.
        
        // Do the directory creation first (the directory is needed for file upload and download) so that failing on directory creation doesn't leave us holding a lock.
        var localFiles = new File(op.userId(), op.deviceId());
        
        // This directory can serve for uploads to the cloud storage for the userId, and downloads from it. This works because the PSLock is going to lock uploads or downloads for the specific userId.
        
        fse.ensureDir(localFiles.localDirectoryPath(), function (err) {
            if (err) {
                op.endWithErrorDetails(error);
            }
            else {
                // Next, check to see if we've (user/device) already has a lock. This should be for error recovery if we do.

                if (isDefined(psLock)){
                    if (isDefined(psOperationId)) {
                        // We have a lock and operationId. App must be doing error recovery. Make sure operation status is right.
                        if (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus) {
                            var message = "Yikes-- an async operation is already in progress!"
                            logger.error(message);
                            op.endWithErrorDetails(message);
                            return;
                        }
                    }
                    
                     // Good-- We're not going to start another async operation.
                    logger.info("Returning operationId to client: " + psLock.operationId);
                    op.result[ServerConstants.resultOperationIdKey] = psLock.operationId;
                    op.endWithRC(ServerConstants.rcOK);
                    
                } else {

                    var lockData = {
                        _id: op.userId(),
                        deviceId: op.deviceId(),
                    };
                    
                    var lock = null;
                    
                    try {
                        lock = new PSLock(lockData);
                    } catch (error) {
                        // Failure mode analysis: Lock will not have been created yet.
                        op.endWithErrorDetails(error);
                        return;
                    }

                    lock.attemptToLock(function (error, lockAlreadyHeld) {
                        if (error) {
                            // Failure mode analysis: Lock may have been created (seems unlikely, but still possible).
                            op.endWithErrorDetails(error);
                        }
                        else {
                            op.endWithRC(ServerConstants.rcOK);
                        }
                    });
                }
            }
        });
    });
});

// DEBUGGING
/*
app.post('/' + ServerConstants.operationUploadFile, upload, function (request, response) {
	console.log(JSON.stringify(request.file));
	var result = {};
	response.end(JSON.stringify(result));
});
*/
// DEBUGGING

/* This doesn't remove the PSOperationId on an uplod error because the client/app may be in the middle of a long series of uploads/deletes and may need to retry a specific upload.
*/
// Failure mode analysis: File may have been moved into our temporary directory and/or entry may have been created in PSOutboundFileChange.
app.post('/' + ServerConstants.operationUploadFile, upload, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
        
    /* request.file has the info on the uploaded file: e.g.,
    { fieldname: 'file',
      originalname: 'upload.txt',
      encoding: '7bit',
      mimetype: 'text/plain',
      destination: './uploads/',
      filename: 'e9a4080c46777d6341518afedec8af31',
      path: 'uploads/e9a4080c46777d6341518afedec8af31',
      size: 22 }
    */
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.
        // console.log("request.file: " + JSON.stringify(request.file));
        
        // Make sure user/device has started uploads. i.e., make sure this user/device has the lock.

        if (!isDefined(psLock)) {
            var message = "Error: Don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId) && (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus)) {
            // This check is to deal with error recovery.
            var message = "Error: Have lock, and an operation in-progress!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId) && (psOperationId.operationType != "Outbound")) {
            var message = "Error: Not doing outbound operation!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            logger.info("We've got the lock!");
            
            // Leave the parameter checking below until after checking for the lock because we're just checking for a lock, and not creating a lock.
            
            // 12/12/15; Ran into a bug where the upload failed, and .file object wasn't defined.
            if (!isDefined(request.file) || !isDefined(request.file.path)) {
                var message = "No file uploaded!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }
            
            logger.info(JSON.stringify(request.file));
            
            var clientFile = null;
            try {
                clientFile = new ClientFile(request.body);
            } catch (error) {
                logger.error(error);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, error);
                return;
            }
            
            /* Need to do some basic checking on this file in the PSFileIndex.
                a) Has this cloudFileName been used before for a different clientFileId? (Actually, we may want to allow this. If a file is deleted, we will want to be able to reuse it's cloudFileName).
                b) Is the version number +1 from the last?
            */
            // Need also to make similar checks in PSOutboundFileChange -- i.e., not only must the file we're uploading not exist in the file index but it also mustn't already exist in the set of files we're currently uploading.
            
            // This fileData is used across PSFileIndex and PSOutboundFileChange in checkIfFileExists
            var fileData = {
                userId: op.userId(),
                fileId: clientFile[ServerConstants.fileUUIDKey]
            };
            
            // 1) Do this first, with the userId and file UUID.
            checkIfFileExists(fileData, function (error, fileIndexObj, outbndFileObj) {
                if (error) {
                    logger.error(error);
                    op.endWithErrorDetails(error);
                    return;
                }
                
                if (fileIndexObj) {
                    var errorMessage = fileIndexObj.checkNewFileVersion(clientFile[ServerConstants.fileVersionKey]);
                    if (isDefined(errorMessage)) {
                        logger.error(errorMessage);
                        op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError,
                                errorMessage);
                        return;
                    }
                }
                
                if (outbndFileObj) {
                    var message = "Attempting to upload two instances of the same file id";
                    logger.error(message);
                    op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError,
                                message);
                    return;
                }
                
                // This fileData is used across PSFileIndex and PSOutboundFileChange in checkIfFileExists
                var fileData = {
                    userId: op.userId(),
                    cloudFileName: clientFile[ServerConstants.cloudFileNameKey]
                };
                
                // 2) Then, a second time with userId and cloudFileName
                checkIfFileExists(fileData, function (error, fileIndexObj, outbndFileObj) {
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
                    
                    if (outbndFileObj) {
                        var message = "Attempting to upload two files with the same cloudFileName";
                        logger.error(message);
                        op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError,
                                message);
                        return;
                    }
                    
                    // TODO: Validate that the mimeType is from an acceptable list of MIME types (e..g, so we don't get an injection error with someone injecting a special Google Drive object such as a folder).
                                 
                    // Move the file to where it's supposed to be.
                    
                    var localFile = new File(op.userId(), op.deviceId(), clientFile[ServerConstants.fileUUIDKey]);
                    
                    // Make the new file name.
                    var newFileNameWithPath = localFile.localFileNameWithPath();
                    
                    /* It is possible, from some prior server issue, that a file from a previous upload exists at the newFileNameWithPath location. E.g., if the server crashed or had a problem and didn't properly clean up the file on a previous operation. Since that this point we (a) have a lock and know we're the only one for this userId/deviceId uploading, and (b) have checked the version number for this file and know its an updated version number, we should be OK to override any existing file. Hence the clobber:true option below. Note that if we don't supply this option, the fse.move operation will fail if newFileNameWithPath exists:
                    2015-12-06T22:30:16-0700 <trace> Operation.js:95 (Operation.end) Sending response back to client: {"ServerResult":2,"ServerErrorDetails":{"errno":-17,"code":"EEXIST","syscall":"link","path":"initialUploads/982ea39fd40380e7ea13d8ed1e001ea1","dest":"/Users/chris/Desktop/Apps/repos/NetDb/Node.js/Node1/uploads/565be13f2917086977fe6f54.DE63BA86-0121-43FF-BAA7-79BBBBFF5D74/ADB50CE8-E254-44A0-B8C4-4A3A8240CCB5"}}
                    */
                    fse.move(request.file.path, newFileNameWithPath, {clobber:true}, function (err) {
                        if (err) {
                            logger.error("Failed on fse.move: %j", err);
                            op.endWithErrorDetails(err);
                        }
                        else {
                            addToOutboundFileChanges(op, clientFile, false, function (error) {
                                if (error) {
                                    logger.error("Failed on addToOutboundFileChanges: %j", error);
                                    op.endWithErrorDetails(error);
                                } else {
                                    op.endWithRC(ServerConstants.rcOK);
                                }
                            });
                        }
                    });
                });
            });
        }
    });
});

/* 
Check to see if the file exists in the PSFileIndex or PSOutboundFileChange. The parameter fileData doesn't have the deleted or toDelete property set.
Callback has four parameters: 
    1) error, 
    2) if error is null, PSFileIndex object -- if the file exists in the PSFileIndex
    3) if error is null, PSOutboundFileChange -- if the file exists in the PSOutboundFileChange
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
            
            var outboundFileChangesObj = null;
            try {
                outboundFileChangesObj = new PSOutboundFileChange(fileData);
            } catch (error) {
                callback(error, null, null);
                return;
            }
            
            outboundFileChangesObj.lookup(function (error, fileExists) {
                if (error) {
                    callback(error, null, null);
                }
                else {
                    if (!fileExists) {
                        outboundFileChangesObj = null;
                    }
                    
                    callback(null, fileIndexObj, outboundFileChangesObj);
                }
            });
        }
    });
}

/* This doesn't remove any PSOperationId on an uplod error because the client/app may be in the middle of a long series of uploads/deletes and may need to retry a specific upload.
*/
app.post('/' + ServerConstants.operationDeleteFiles, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        if (!psLock) {
            var message = "Error: Don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            
        }
        else if (isDefined(psOperationId) && (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus)) {
            // This check is to deal with error recovery.
            var message = "Error: Have lock, but operation is already in progress!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId) && (psOperationId.operationType != "Outbound")) {
            var message = "Error: Not doing outbound operation!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            // We're getting an array of file descriptions from the client.

            var clientFileArray = null;
            try {
                clientFileArray = ClientFile.objsFromArray(request.body[ServerConstants.filesToDeleteKey]);
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
            
            function errorChecking(clientFile, callback) {
                errorCheckFileForDeletion(op, clientFile, function (error) {
                    callback(error);
                });
            }
            
            function addToOutbound(clientFile, callback) {
                addToOutboundFileChanges(op, clientFile, true, function (error) {
                    callback(error);
                });
            }
            
            Common.applyFunctionToEach(errorChecking, clientFileArray, function (error) {
                if (error) {
                    op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, error);
                }
                else {
                    Common.applyFunctionToEach(addToOutbound, clientFileArray, function (error) {
                        if (error) {
                            // TODO: If we get an erorr here, there may be lingering deletion entries in the PSOutboundFileChanges that could be a problem. A cleanup is required from the client!!!
                            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, error);
                        }
                        else {
                            op.endWithRC(ServerConstants.rcOK);
                        }
                    });
                }
            });
        }
    });
});

// The callback has one parameter: error.
function errorCheckFileForDeletion(op, clientFile, callback) {
    // This fileData is used across PSFileIndex and PSOutboundFileChange in checkIfFileExists
    var fileData = {
        userId: op.userId(),
        fileId: clientFile[ServerConstants.fileUUIDKey]
    };
    
    checkIfFileExists(fileData, function (error, fileIndexObj, outbndFileObj) {
        if (error) {
            callback(error);
            return;
        }
        
        // Make sure this file isn't deleted already.
        if (fileIndexObj) {
            if (fileIndexObj.deleted) {
                callback(new Error("File was already deleted in the PSFileIndex"));
                return;
            }
        }
        
        // Make sure that the file isn't already in the outbound file changes.
        if (outbndFileObj) {
            callback(new Error("Attempting to upload/delete two instances of the same file id"));
            return;
        }
        
        callback(null);
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
    
    if (isDefined(clientFile[ServerConstants.appFileTypeKey])) {
        fileMetaData.appFileType = clientFile[ServerConstants.appFileTypeKey];
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

/* The rationale for waiting until operationStartOutboundTransfer in order to do the transfer to cloud storage is the greater relative stability of the server versus the mobile device. E.g., at any time a mobile device can (a) lose its network connection, or (b) have its app go into the background and lose CPU. Once the files are on the server, we don't have as much possible variablity in these issues.
*/
/* Failure mode analysis prior to returning success to the app/client from the commit:
1) An error can occur in checking for the lock; in which case, the PSLock is still held, and the PSOperationId is sill present.
2) The PSOperationId is marked as having a commit error. We're not going to purge files from temporary storage in the file system, or from the PSOutboundFileChange collection however. To enable the possiblity of other (to be defined recovery) REST API operations as working from those files.
    In this case the PSLock is still present.

Failure mode analysis after returning success from the commit:
*/
app.post('/' + ServerConstants.operationStartOutboundTransfer, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // Make sure user/device has started uploads. i.e., make sure this user/device has the lock.

        if (!isDefined(psLock)) {
            var message = "Error: Don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId)) {
            if (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus) {
                // This check is to deal with error recovery.
                var message = "Error: Have lock, but operation is already in progress!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            } else if (psOperationId.operationType != "Outbound") {
                var message = "Error: Not doing outbound operation!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            } else {
                // Already have operation Id.
                startOutboundTransfer(op, psLock, psOperationId);
            }
        }
        else {
            
            var psOperationId = null;

            try {
                psOperationId = new PSOperationId({operationType: "Outbound"});
            } catch (error) {
                op.endWithErrorDetails(error);
                return;
            };

            psOperationId.storeNew(function (error) {
                if (error) {
                    op.endWithErrorDetails(error);
                }
                else {
                    startOutboundTransfer(op, psLock, psOperationId);
                }
            });
        }
    });
});

function startOutboundTransfer(op, psLock, psOperationId) {
    // Always returning operationId, just for uniformity.
    
    logger.info("Returning operationId to client: " + psOperationId._id);
    op.result[ServerConstants.resultOperationIdKey] = psOperationId._id;
    
    // Need to update lock with operationId. It's possible this has already been done, but doing it multiple times shouldn't matter.
    
    psLock.operationId = psOperationId._id;
    psLock.update(function (error) {
        if (error) {
            op.endWithErrorDetails(error);
        }
        else {
            // Mark all files for user/device in PSOutboundFileChange's as committed.
            PSOutboundFileChange.commit(op.userId(), op.deviceId(), function (error) {
                if (objOrInject(error, op, ServerConstants.dbTcCommitChanges)) {
                    logger.error("Failed on PSOutboundFileChange.commit: " + error);
                    
                    // What the heck? Not proceeding with operation, so the PSOperationId is now not valid in some sense. I could remove it, but it costs little to leave it, and record the failure redundantly. Leaving it may also help us in recovery.
                    
                    psOperationId.operationStatus = ServerConstants.rcOperationStatusCommitFailed;
                    psOperationId.error = error;
                    
                    psOperationId.update(function (updateError) {
                        if (updateError) {
                            // Can't do much with this we've got two successive errors...
                            logger.error("Error on top of error: %s", updateError);
                        }
                        
                        op.endWithErrorDetails(error);
                    });
                }
                else {
                    startTransferringFiles(op, psLock, psOperationId);
                }
            });
        }
    });
}

// Need to kick off an operation that will execute untethered from the http request.
// We'll do a transfer, wait for it to complete. And then do the next, etc. This poses interesting problems for errors and reporting errors. AND, termination.
// It seems this untethered operation is a characteristic of Node.js: http://stackoverflow.com/questions/16180502/node-express-why-can-i-execute-code-after-res-send
// We'll have to do something separate to deal with (A) reporting/logging errors post-connection termation, (B) handling errors, and (C) ensuring termination (i.e., ensuring we don't run for too long).
// If we were using websockets, could we inform the app of an error in the file transfer? Presumably if the app was in the background, not launched, or not on the network, no.
function startTransferringFiles(op, psLock, psOperationId) {
    // Change PSOperationId status to rcOperationStatusInProgress to mark that the operation is operating asynchronously from the REST/API call.
    psOperationId.operationStatus = ServerConstants.rcOperationStatusInProgress;
    psOperationId.error = null;
    
    psOperationId.update(function (updateError) {
        if (objOrInject(updateError, op, ServerConstants.dbTcInProgress)) {
            logger.error("Could not update operation to rcOperationStatusInProgress: %s", updateError);
            op.endWithErrorDetails(updateError);
        }
        else {
            // 2) Tell the user we're off to the races, and end the connection.
            op.endWithRC(ServerConstants.rcOK);
            
            // 3) Do the file transfer to the cloud storage system.
            transferFilesToCloudStorage(op, psLock, psOperationId);
        }
    });
}

function transferFilesToCloudStorage(op, psLock, psOperationId) {

    function updateOperationId(psOperationId, rc, errorMessage) {
        if (errorMessage) {
            logger.error(errorMessage);
            psOperationId.error = errorMessage;
        }
        else {
            psOperationId.error = null;
        }
        
        psOperationId.operationStatus = rc;
        psOperationId.update();
    }
    
    logger.info("Attempting FileTransfers.setup...");
    var fileTransfers = new FileTransfers(op, psOperationId);

    fileTransfers.setup(function (error) {
        if (objOrInject(error, op, ServerConstants.dbTcSetup)) {
            var errorMessage = "Failed on setup: " + JSON.stringify(error);
            updateOperationId(psOperationId, ServerConstants.rcOperationStatusFailedBeforeTransfer, errorMessage);
        }
        else {
            logger.info("Attempting FileTransfers.sendFiles...");

            fileTransfers.sendFiles(function (sendFilesError) {
                if (objOrInject(sendFilesError, op, ServerConstants.dbTcSendFiles)) {
                    var errorMessage = "Error sending files: " +
                        JSON.stringify(sendFilesError);
                    updateOperationId(psOperationId, ServerConstants.rcOperationStatusFailedDuringTransfer, errorMessage);
                    
                    // I'm not going to remove the lock here to give the app a chance to recover from this error in a locked condition.
                    return;
                }

                psLock.removeLock(function (error) {
                    if (objOrInject(error, op, ServerConstants.dbTcRemoveLock)) {
                        var errorMessage = "Failed to remove the lock: " + JSON.stringify(error);
                        updateOperationId(psOperationId, ServerConstants.rcOperationStatusFailedAfterTransfer, errorMessage);
                    }
                    else {
                        logger.trace("Removed the lock.");

                        updateOperationId(psOperationId, ServerConstants.rcOperationStatusSuccessfulCompletion, null);
                        logger.trace("Successfully completed operation!");
                    }
                });
            });
        }
    });
}

app.post('/' + ServerConstants.operationGetFileIndex, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // In order to get a coherent view of the files on the SyncServer it seems that we need to have a lock. Without a lock, some other client could be in the middle of changing (updating or deleting) files in the index.
        // We can already hold the lock, or obtain the lock for just the duration of this call.

        if (isDefined(psLock)) {
            // We already held the lock-- prior to this get file index operation, so get list of files, but don't remove the lock afterwards.
            finishOperationGetFileIndex(op, null);
        } else {
            // Create a lock.
        
            var lockData = {
                _id: op.userId(),
                deviceId: op.deviceId()
            };
            
            var lock = new PSLock(lockData);
            lock.attemptToLock(function (error, lockAlreadyHeld) {
                if (error) {
                    if (lockAlreadyHeld) {
                        op.endWithRCAndErrorDetails(ServerConstants.rcLockAlreadyHeld, error);
                    }
                    else {
                        op.endWithErrorDetails(error);
                    }
                }
                else {
                    // Get list of files. Since we created the lock with this operation, remove the lock afterwards.
                    finishOperationGetFileIndex(op, lock);
                }
            });
        }
    });
});

// If the lock is null, it doesn't need to be removed.
function finishOperationGetFileIndex(op, lock) {

    // Get a list of all our files in the PSFileIndex.
    PSFileIndex.getAllFor(op.userId(), function (psFileIndexError, fileIndexObjs) {
        if (psFileIndexError) {
            if (isDefined(lock)) {
                lock.removeLock(function (error) {
                    if (error) {
                        logger.error("Failed to remove the lock: %j", error);
                    }
                    else {
                        logger.trace("Removed the lock.");
                    }
                    
                    op.endWithErrorDetails(psFileIndexError);
                });
            }
            else {
                op.endWithErrorDetails(psFileIndexError);
            }
        }
        else {
            // Get rid of _id and userId properties because neither is no business of the client's.
            for (var index in fileIndexObjs) {
                var obj = fileIndexObjs[index];
                delete obj._id;
                delete obj.userId;
            }
            
            function returnResult() {
                op.result[ServerConstants.resultFileIndexKey] = fileIndexObjs;
                op.endWithRC(ServerConstants.rcOK);
            }
            
            if (isDefined(lock)) {
                lock.removeLock(function (error) {
                    if (error) {
                        logger.error("Failed to remove the lock: " + error);
                        op.endWithErrorDetails(error);
                    }
                    else {
                        logger.trace("Removed the lock.");
                        returnResult();
                    }
                });
            }
            else {
                returnResult();
            }
        }
    });
}

app.post('/' + ServerConstants.operationCheckOperationStatus, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
    
        var operationId = request.body[ServerConstants.operationIdKey];
        if (!isDefined(operationId)) {
            var message = "No operationIdKey given in HTTP params!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
                
        // Specifically *not* checking to see if we have a lock. If an Outbound transfer operation has successfully completed, the lock will have been removed.
        
        // We already have the psOperationId, but go ahead and use the app/client's operationId to look it up.
        PSOperationId.getFor(operationId, function (error, psOperationId) {
            if (error) {
                var errorMessage = "Could not get operation id: " + JSON.stringify(error) + " for id: " + operationId;
                logger.error(errorMessage);
                op.endWithErrorDetails(errorMessage);
            }
            else {
                // TODO: Make sure the user/device id for this operation Id is the same as ours.

                op.result[ServerConstants.resultOperationStatusCountKey] = psOperationId.operationCount;
                op.result[ServerConstants.resultOperationStatusCodeKey] = psOperationId.operationStatus;
                op.result[ServerConstants.resultOperationStatusErrorKey] = psOperationId.error;
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
});

// This is useful in case the CommitChanges fails but the operation Id was generated.
app.post('/' + ServerConstants.operationGetOperationId, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        if (!psLock) {
            // If we don't have a lock, we can't have an operation Id. Considering this an API error, because the client/app should know they don't have a lock.
            var message = "Error: Don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            if (isDefined(psOperationId)) {
                logger.info("Returning operationId to client: " + psOperationId._id);
                op.result[ServerConstants.resultOperationIdKey] = psOperationId._id;
            }
            
            op.endWithRC(ServerConstants.rcOK);
        }
    });
});

app.post('/' + ServerConstants.operationRemoveOperationId, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        removeOperationId(op, request);
    });
});

// Remove the operation id, and send the result back to REST/API caller.
function removeOperationId(op, request) {
    var operationId = request.body[ServerConstants.operationIdKey];
    if (!isDefined(operationId)) {
        var message = "No operationIdKey given in HTTP params!";
        logger.error(message);
        op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        return;
    }
    
    // Specifically *not* checking to see if we have a lock. If the operation has successfully completed, the lock will have been removed.

    // We already have the psOperationId, but go ahead and use the app/client's operationId to look it up.
    PSOperationId.getFor(operationId, function (error, psOperationId) {
        if (error) {
            var errorMessage = "Could not get operation id: " + JSON.stringify(error) + " for id: " + operationId;
            logger.error(errorMessage);
            op.endWithErrorDetails(errorMessage);
        }
        else {
            // TODO: Make sure the user/device id for this operation Id is the same as ours.
            
            psOperationId.remove(function (error) {
                if (error) {
                    op.endWithErrorDetails(error);
                }
                else {
                    op.endWithRC(ServerConstants.rcOK);
                }
            });
        }
    });
}

app.post('/' + ServerConstants.operationUploadRecovery, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        
        /* 
        Our situation: PSOperationId may have been created, PSLock may be held and PSOutboundFileChange's may have been created.
        The important issue is with the PSOutboundFileChange entries in the database: Because they typically represent upload work done. If we have one or more of these, we'll be restarting. If we have none of these, we'll clean up and let the app start file changes from scratch.
        */
        /* 
        12/25/15; Up until this point, I was allowing lock to be called muliple times (i.e., I was making use of this for recovery-- so I didn't have to release the lock and reacquire it). However, I ran into an issue with testing: 1) I simulated failure of the commit operation on the client side, and 2) the app tried to do a recovery. However, because the commit actually succeeded, at the same time as the commit was occuring on the server, the app was starting up a concurrent lock, and so I ended up with two concurrent commits occuring for the same user/device. In general, this poses an issue: When you believe you've got an error on the commit, how do you ensure that the commit isn't actually proceeding?
        WHAT ABOUT: Before beginning this recovery, on the server, we check what the status of the Operation Id is. If the status is some error or failure, then we can proceed with the recovery. If the status not rcOperationStatusInProgress then the operation is not in asynchronous/concurrent execution, and we can proceed with the recovery.
        */
                    
        if (!isDefined(psLock)) {
            var message = "We don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId) && (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus)) {
            // This is really an error. We should never have an in-progress operation for UploadRecovery because we should only ever be doing a UploadRecovery prior to a successful commit.
            var message = "Operation status was rcOperationStatusInProgress";
            logger.error(message);
            // Should we really call this a rcServerAPIError?
            op.endWithRCAndErrorDetails(ServerConstants.rcOperationInProgress, message);
        }
        else if (isDefined(psOperationId) && (psOperationId.operationType != "Outbound")) {
            var message = "Error: Not doing outbound transfer operation!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            finishUploadRecovery(op, psLock, psOperationId);
        }
    });
});

function finishUploadRecovery(op, lock, psOperationId) {
    PSOutboundFileChange.getAllFor(op.userId(), op.deviceId(),
        function (error, psOutboundFileChanges) {
            if (error) {
                op.endWithErrorDetails(error);
            }
            else if (psOutboundFileChanges.length == 0) {
                logger.info("No PSOutboundFileChange items. Try to remove any PSOperationId and/or PSLock.");
                // Try to remove the lock first. That's the most important. If we fail to remove the PSOperationId, it's no biggie. Garbage collection can get that later.

                lock.removeLock(function (error) {
                    if (error) {
                        op.endWithErrorDetails(error);
                    }
                    else {
                        if (isDefined(psOperationId)) {
                            psOperationId.remove(function (error) {
                                if (error) {
                                    op.endWithErrorDetails(error);
                                }
                                else {
                                    op.endWithRC(ServerConstants.rcOK);
                                }
                            });
                        }
                        else {
                            op.endWithRC(ServerConstants.rcOK);
                        }
                    }
                });
            }
            else {
                logger.info("We've got PSOutboundFileChange items. Client/app will need to work from an existing set of file uploads.");

                // With PSOutboundFileChange items, we will necessarily have a PSLock. This is because in order to create a PSOutboundFileChange, we necessarily have a PSLock.
                // I'm going to format these PSOutboundFileChange items like they were a file index.
                
                function returnOutboundFileChanges() {
                    var result = [];
                    
                    for (var index in psOutboundFileChanges) {
                        var obj = psOutboundFileChanges[index];
                        result.push(obj.convertToFileIndex());
                    }
                    
                    op.result[ServerConstants.resultFileIndexKey] = result;
                    op.endWithRC(ServerConstants.rcOK);
                }
                
                if (isDefined(psOperationId)) {
                    // Set the PSOperationId to an initial, non-error state.
                    psOperationId.operationStatus = ServerConstants.rcOperationStatusNotStarted;
                    psOperationId.error = null;
                    
                    psOperationId.update(function (updateError) {
                        if (updateError) {
                            logger.error("Could not update operation to rcOperationStatusNotStarted: %s", updateError);
                            op.endWithErrorDetails(updateError);
                        }
                        else {
                            op.result[ServerConstants.resultOperationIdKey] = lock.operationId;
                            returnOutboundFileChanges();
                        }
                    });
                }
                else {
                    returnOutboundFileChanges();
                }
            }
        });
}

// Removes PSOutboundFileChange's, removes the PSLock, and removes the PSOperationId (if any).
app.post('/' + ServerConstants.operationCleanup, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        if (!isDefined(psLock)) {
            var message = "We don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId) && (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus)) {
            // Yikes.
            var message = "Operation status was rcOperationStatusInProgress";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcOperationInProgress, message);
        }
        else {
            // Remove the PSOutboundFileChange's before the lock because that seems safer. If we fail on removing the file changes, at least we still have the lock.
            PSOutboundFileChange.getAllFor(op.userId(), op.deviceId(), function (error, psOutboundFileChangeObjs) {
                if (error) {
                    var message = "Failed on PSOutboundFileChange.getAllFor!";
                    logger.error(message);
                    op.endWithErrorDetails(message);
                }
                else {
                    Common.applyMethodToEach("remove", psOutboundFileChangeObjs, function (error) {
                        if (error) {
                            var message = "Failed deleting a PSOutboundFileChange object";
                            logger.error(message);
                            op.endWithErrorDetails(message);
                        }
                        else {
                            psLock.remove(function (error) {
                                if (error) {
                                    var message = "Failed removing PSLock!";
                                    logger.error(message);
                                    op.endWithErrorDetails(message);
                                }
                                else {
                                    if (isDefined(psOperationId)) {
                                        psOperationId.remove(function (error) {
                                            if (error) {
                                                var message = "Failed removing PSOperationId!";
                                                logger.error(message);
                                                op.endWithErrorDetails(message);
                                            }
                                            else {
                                                op.endWithRC(ServerConstants.rcOK);
                                            }
                                        });
                                    }
                                    else {
                                        op.endWithRC(ServerConstants.rcOK);
                                    }
                                }
                            });
                        }
                    });
                }
            });
        }
    });
});

app.post('/' + ServerConstants.operationOutboundTransferRecovery, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
                    
        if (!isDefined(psLock)) {
            var message = "We don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (!isDefined(psOperationId)) {
            // Should not be doing a transfer recovery without an operationId.
            var message = "There is no operationId!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus) {
            // If the operation is InProgress, we'll consider this not be an error and not something we have to recover from.
            var message = "Operation was InProgress-- Not doing transfer recovery.";
            logger.debug(message);
            op.endWithRC(ServerConstants.rcOK);
        }
        else if (psOperationId.operationType != "Outbound") {
            var message = "Error: Not doing outbound transfer operation!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            logger.debug("About to check log consistency...");
            
            var fileTransfers = new FileTransfers(op, psOperationId);
            
            fileTransfers.ensureLogConsistency(function (error) {
                if (error) {
                    op.endWithErrorDetails(error);
                }
                else {
                    // Originally I was thinking of this as now being in the same kind of situation as file changes recovery at this point. HOWEVER, that is not true. If there are files listed in outbound file changes, they will be *committed*. All files will have already been uploaded. Treating this like file changes recovery would indicate that some files might still need to be uploaded. Which is incorrect. Rather, the question is: What files still need to be transferred to cloud storage? We've made our log consistent, so our PSOutboundFileChange info and our PSFileIndex will be consistent. SO, our job right now is to do the remaining transfers.
                    // startTransferringFiles calls transferFilesToCloudStorage, which calls sendFiles, which looks up committed entries in PSOutboundFileChange's, so that will do what we want at this point.
                    // In fact, this will act in the same manner as the end part of CommitFileChanges-- it will let the file transfer run asynchronously and "return" to the server REST API caller.
                    startTransferringFiles(op, psLock, psOperationId);
                }
            });
        }
    });
});

// Initiates an asynchronous operation transferring files from cloud storage. REST/API caller provides the list of files to be transferred.
app.post('/' + ServerConstants.operationStartInboundTransfer, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.

        var localFiles = new File(op.userId(), op.deviceId());
        
        if (!isDefined(psLock)) {
            var message = "We don't have the lock!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else if (isDefined(psOperationId)) {
            // Should not already have an operationId because this is is going to create an operationId.
            var message = "There is already an operationId!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
            var clientFileArray = null;
            try {
                clientFileArray = ClientFile.objsFromArray(request.body[ServerConstants.filesToTransferFromCloudStorageKey]);
            } catch (error) {
                logger.error(error);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, error);
                return;
            }
            
            if (clientFileArray.length == 0) {
                var message = "No files given to transfer from cloud storage.";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }
        }
    });
});

app.post('/*' , function (request, response) {
    logger.error("Bad Operation URL");
    var op = new Operation(request, response, true);
    op.endWithRC(ServerConstants.rcUndefinedOperation);
});

// Error handling: http://expressjs.com/guide/error-handling.html
app.use(function(err, req, res, next) {
    // TODO: If I get a syntax error in my code will this get called? What I'd like to do is set up an error handler that gets called in the case of syntax errors, and mark the PSOperationId entry as done, but having had an error. Is there a way I can handle exceptions globally and get at least a final block of code executed? Syntax errors seem to throw exceptions.
    logger.error("Error occurred: %j" + JSON.stringify(err));
    var op = new Operation(req, res, true);
    op.endWithErrorDetails(err);
    logger.error(err.stack);
});

app.listen(8081);

logger.info('Server running at http://127.0.0.1:8081/');

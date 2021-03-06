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
var PSInboundFile = require('./PSInboundFile');
var Secrets = require('./Secrets');
var assert = require('assert');
var PSUserCredentials = require('./PSUserCredentials');
require('./Globals')

// See http://stackoverflow.com/questions/31496100/cannot-app-usemulter-requires-middleware-function-error
// See also https://codeforgeek.com/2014/11/file-uploads-using-node-js/
// TODO: Limit the size of the uploaded file.
// TODO: Is there a way with multer to add a callback that gets called periodically as an upload is occurring? We could use this to "refresh" an activity state for a lock to make sure that, even with a long-running upload (or download) if it is still making progress, that we wouldn't lose a lock.
var upload = multer({ dest: initialUploadDirectory}).single(ServerConstants.fileUploadFieldName)

// http://stackoverflow.com/questions/4295782/how-do-you-extract-post-data-in-node-js
app.use(bodyParser.json({extended : true}));

var serverPort = 8081;
var serverIPAddress = '0.0.0.0';

// 5/1/16; Changes for running on Heroku. process.env.PORT is an environmental dependency on Heroku. The only Heroku dependency in the server I think.
//if (isDefined(process.env.PORT)) {
//    serverPort = process.env.PORT;
//}

// 7/31/16
// Changes for running on Bluemix.
// https://console.ng.bluemix.net/docs/runtimes/nodejs/index.html#nodejs_runtime

if (isDefined(process.env.VCAP_APP_PORT)) {
    logger.info("Found VCAP_APP_PORT: Assuming that we're running on Bluemix.");

    serverPort = process.env.VCAP_APP_PORT;
    
    if (!isDefined(process.env.VCAP_APP_HOST)) {
        throw("Could not find process.env.VCAP_APP_HOST");
    }
    
    serverIPAddress = process.env.VCAP_APP_HOST;
}

// Server main.
Secrets.load(function (error) {
    assert.equal(null, error);
    
    var mongoDbURL = Secrets.mongoDbURL();
    if (!isDefined(mongoDbURL)) {
        throw new Error("mongoDbURL is not defined!");
    }
    
    Mongo.connect(mongoDbURL);
});

// Enable creation of an owning or sharing user.
// TODO: Eventually this needs to contain a check to ensure that only certain apps are calling this entry point. So that others don't use our server resources.
app.post("/" + ServerConstants.operationCreateNewUser, function(request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }

    op.checkForExistingUser(function (error, staleUserSecurityInfo) {
        if (error) {
            if (staleUserSecurityInfo) {
                op.endWithRCAndErrorDetails(ServerConstants.rcStaleUserSecurityInfo, error);
            }
            else {
                op.endWithErrorDetails(error);
            }
        }
        else {
            logger.info("psUserCreds.stored: " + op.psUserCreds.stored);
            if (op.psUserCreds.stored) {
                op.endWithRC(ServerConstants.rcUserOnSystem);
            }
            else {
                // User creds not yet stored in Mongo. Store 'em.
                op.psUserCreds.storeNew(function (error) {
                    if (error) {
                        op.endWithErrorDetails(error);
                    }
                    else {
                        op.result[ServerConstants.internalUserId] = op.psUserCreds._id;
                        op.endWithRC(ServerConstants.rcOK);
                    }
                });
            }
        }
    });
});

app.post("/" + ServerConstants.operationCheckForExistingUser, function(request, response) {

    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }

    op.validateUser({userMustBeOnSystem:false, mustHaveLinkedOwningUserId:false}, function () {
        if (op.psUserCreds.stored) {
            op.result[ServerConstants.internalUserId] = op.psUserCreds._id;
            op.endWithRC(ServerConstants.rcUserOnSystem);
        }
        else {
            op.endWithRC(ServerConstants.rcUserNotOnSystem);
        }
    });
});

// You can do multiple successive locks with the same deviceId/userId. Locks after the first have no effect, but also don't fail.
// Failure mode analysis: On a failure, it is still possible that either one or both of these is true: 1) PSOperationId has been created, and 2) the lock has been created.
app.post('/' + ServerConstants.operationLock, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.
        
        // Generally: Need to make sure no lock is held right now. e.g., no other user with this same userId is changing files. It is possible (though unlikely) that between the time that we check to see a lock is held, then try to get the lock, that someone else got the lock. Since we're using the userId as the primary key into PSLock, only one attempt to create the lock will be successful.
        
        // Do the directory creation first (the directory is needed for file upload and download) so that failing on directory creation doesn't leave us holding a lock.
        var localFiles = new File(op.userId(), op.deviceId());
        
        // This directory can serve for uploads to the cloud storage for the userId, and downloads from it. This works because the PSLock is going to lock uploads or downloads for the specific userId.
        
        var forceLock = request.body[ServerConstants.forceLock];
        
        fse.ensureDir(localFiles.localDirectoryPath(), function (err) {
            if (err) {
                op.endWithErrorDetails(error);
            }
            else {
                // Next, check to see if we (user/device) already have a lock.

                op.result[ServerConstants.resultLockHeldPreviously] = isDefined(psLock);
 
                if (isDefined(psLock)) {
                    /* We have a lock and operationId. Two possibilities:
                    1) App is doing a reset from an error-- ignore operation status.
                    2) App is doing error recovery. Make sure operation status is right.
                    */
                    if (isDefined(psOperationId) && !forceLock) {
                        if (ServerConstants.rcOperationStatusInProgress == psOperationId.operationStatus) {
                            var message = "Yikes-- an async operation is already in progress!"
                            logger.error(message);
                            op.endWithErrorDetails(message);
                            return;
                        }
                    }
                    
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
                            // Failure mode analysis: Lock may have been created (seems unlikely, but still possible). What is more likely is that the lock could have been created and held by another device with the same userId.
                            if (lockAlreadyHeld) {
                                op.endWithRCAndErrorDetails(ServerConstants.rcLockAlreadyHeld, error);
                            }
                            else {
                                op.endWithErrorDetails(error);
                            }
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

app.post('/' + ServerConstants.operationUnlock, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        if (isDefined(psLock)) {
            if (isDefined(psOperationId)) {
                op.endWithErrorDetails("Can't use explicit unlock when there is an operationId!");
            }
            else {
                psLock.removeLock(function (error) {
                    if (error) {
                        op.endWithErrorDetails("Failed to remove the lock: " + error);
                    }
                    else {
                        op.endWithRC(ServerConstants.rcOK);
                    }
                });
            }
        } else {
            op.endWithRCAndErrorDetails(ServerConstants.rcLockNotHeld, "Lock not held");
        }
    });
});

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
/* This doesn't remove the PSOperationId on an uplod error because the client/app may be in the middle of a long series of uploads/deletes and may need to retry a specific upload.
*/
// Failure mode analysis: File may have been moved into our temporary directory and/or entry may have been created in PSOutboundFileChange.
app.post('/' + ServerConstants.operationUploadFile, upload, function (request, response) {
    // Somewhat of a hack, but due to the way that the file upload works on the iOS client we have to do some processing of the parameters out of the body ourselves. I'm doing this at the very start of the operation so that the Operation constructor gets the proper JSON valued request.body. See also https://stackoverflow.com/questions/37449472/afnetworking-v3-1-0-multipartformrequestwithmethod-uploads-json-numeric-values-w/37684827#37684827
    // TODO: When other (e.g., Android) clients are created, we may need to condition this step based on the type of client.
    
    // I just got an issue: "SyntaxError: Unexpected token u in JSON at position 0" at this position in the code. Which came from bad upload parameters.  See http://stackoverflow.com/questions/13022178/uncaught-syntaxerror-unexpected-token-u-json
    // Putting in an error test case for that.
    var paramsForUpload = request.body[ServerConstants.serverParametersForFileUpload];
    if (!isDefined(paramsForUpload)) {
        var message = "Undefined upload parameters";
        logger.error(message);
        op.endWithErrorDetails(message);
        return;
    }
    
    request.body = JSON.parse(paramsForUpload);
    
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
    
    const undeleteFileKey = request.body[ServerConstants.undeleteFileKey];
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.
        // console.log("request.file: " + JSON.stringify(request.file));
        
        // Make sure user/device has the lock.
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
            
            if (!op.endIfUserNotAuthorizedFor(ServerConstants.sharingUploader)) {
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
                    
                    // In terms of server scaling, or in terms of multiple hits on this same server concurrently, because we have a lock on the server for this userId/deviceId, we know that we'll be having the only access to the PSFileIndex for this userId.
                    
                    var sameFileIndexVersionIfExists = true
                    fileIndexObj.updateOrStoreNew(sameFileIndexVersionIfExists, function (error) {
                        if (error) {
                            var errorMessage = "updateOrStoreNew: Error: " + error;
                            logger.debug(errorMessage);
                            op.endWithErrorDetails(errorMessage);
                        }
                        else {
                            completeOperationUploadFile(op, outbndFileObj, clientFile, request);
                        }
                    });
                }
                else {
                    // Complete the upload.
                    completeOperationUploadFile(op, outbndFileObj, clientFile, request);
                }
            });
        }
    });
});

function completeOperationUploadFile(op, outbndFileObj, clientFile, request) {
    var createOutboundFileChangeEntry = true;
    
    if (outbndFileObj) {
        // To enable recovery, not going to consider this an error, as long as the cloud file name matches up too.
        if (clientFile[ServerConstants.cloudFileNameKey] == outbndFileObj.cloudFileName) {
            createOutboundFileChangeEntry = false;
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
            if (clientFile[ServerConstants.fileUUIDKey] == outbndFileObj.fileId && !createOutboundFileChangeEntry) {
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
                if (createOutboundFileChangeEntry) {
                    addToOutboundFileChanges(op, clientFile, false, function (error) {
                        if (error) {
                            logger.error("Failed on addToOutboundFileChanges: %j", error);
                            op.endWithErrorDetails(error);
                        } else {
                            op.endWithRC(ServerConstants.rcOK);
                        }
                    });
                }
                else {
                    op.endWithRC(ServerConstants.rcOK);
                }
            }
        });
    });
}

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
    This can be called multiple times from the client with the same parameters. Once the info for a specific file to be deleted is entered into the PSOutboundFileChange, it will not be entered a second time. E.g., with no failure the first time around, calling this a second time has no effect and doesn't cause an error.
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
});

// The callback has one parameter: error.
function addDeletionToOutboundIfNew(op, clientFile, callback) {
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
        
        // Make sure this file isn't deleted already. i.e., that it's not marked as deleted in the PSFileIndex.
        if (fileIndexObj) {
            if (fileIndexObj.deleted) {
                callback(new Error("File was already deleted in the PSFileIndex"));
                return;
            }
        }
        
        // Check if the file is already scheduled for deletion in the outbound file changes.
        if (outbndFileObj) {
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
            // 4/23/16; There is a possible recovery situation here. If we remove the lock in [6], but fail in reporting that back to the app, and a recovery takes place, we'll get to this point in the code. Note that with the psLock not defined, the psOperationId will also not be defined-- this is how validateUser works. So, let's lookup the PSOperationId separately, based on the user/device because we don't have an operationId as a parameter to this server API call.
            noLockRecoveryForTransfer(op, "Outbound");
        }
        else if (isDefined(psOperationId)) {
            // Outbound transfer recovery.
            
            if (psOperationId.operationType != "Outbound") {
                var message = "Error: Not doing outbound operation!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            }
            else {
                outboundTransferRecovery(op, psLock, psOperationId);
            }
        }
        else {
            // Not checking for sharingType because it was checked on upload.
            
            var psOperationId = null;

            try {
                psOperationId = new PSOperationId({
                    operationType: "Outbound",
                    userId: op.userId(),
                    deviceId: op.deviceId()
                });
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

function outboundTransferRecovery(op, psLock, psOperationId) {
    // Always returning operationId, just for uniformity.
    
    logger.info("Returning operationId to client: " + psOperationId._id);
    op.result[ServerConstants.resultOperationIdKey] = psOperationId._id;
    
    switch (psOperationId.operationStatus) {
    case ServerConstants.rcOperationStatusNotStarted:
    case ServerConstants.rcOperationStatusFailedBeforeTransfer:
        // Must have failed on or before the commit. Need to do the commit.
        startOutboundTransfer(op, psLock, psOperationId);
        break;
        
    case ServerConstants.rcOperationStatusFailedDuringTransfer:
        logger.debug("About to check log consistency...");

        var fileTransfers = new FileTransfers(op, psOperationId);
        
        fileTransfers.ensureLogConsistency(function (error) {
            if (error) {
                op.endWithErrorDetails(error);
            }
            else {
                // startTransferOfFiles sends back completion info to the server API callee.
                startTransferOfFiles(op, psLock, psOperationId, FileTransfers.methodNameSendFiles);
            }
        });
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

// This is called in two cases: 1) To start outbound tranfers for the first time, and 2) To initiate recovery, when the calling client app detects a problem with outbound transfer.
function startOutboundTransfer(op, psLock, psOperationId) {
    // Always returning operationId, just for uniformity.
    
    logger.info("Returning operationId to client: " + psOperationId._id);
    op.result[ServerConstants.resultOperationIdKey] = psOperationId._id;
    
    // Need to update lock with operationId. It's possible this has already been done, but doing it multiple times shouldn't matter.
    
    psLock.operationId = psOperationId._id;
    psLock.update(function (error) {
        if (error) {
            logger.error("Error updating psLock: " + error);
            op.endWithErrorDetails(error);
        }
        else {
            // Mark all files for user/device in PSOutboundFileChange's as committed.
            PSOutboundFileChange.commit(op.userId(), op.deviceId(), function (error) {
                if (objOrInject(error, op, ServerConstants.dbTcCommitChanges)) {
                    logger.error("Failed on PSOutboundFileChange.commit: " + error);
                    
                    // What the heck? Not proceeding with operation, so the PSOperationId is now not valid in some sense. I could remove it, but it costs little to leave it, and record the failure redundantly. Plus, it should help with recovery.
                    
                    op.endWithErrorDetails(error);
                }
                else {
                    // startTransferOfFiles sends back completion info to the server API callee.
                    startTransferOfFiles(op, psLock, psOperationId, FileTransfers.methodNameSendFiles);
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
// transferMethodName can be FileTransfers.methodNameSendFiles or FileTransfers.methodNameReceiveFiles
function startTransferOfFiles(op, psLock, psOperationId, transferMethodName) {
    // Change PSOperationId status to rcOperationStatusInProgress to mark that the operation is operating asynchronously from the REST/API call.
    // 4/19/16; I've struggled with when to change the status to rcOperationStatusInProgress. Up until now, my view was as follows: "It is best to not do this too early. i.e., we should not do this before we actually know that the operation is actually in-progress. If we do this early, then if we get a false negative in setting the in-progress status (we successfully set the status to in-progress, but get a report of failure), we will be in a bad state: We will believe we the operation is in-progress, but we have really not started the transfer operation."
    // HOWEVER, now, I'm going to change the status to InProgress prior to ending the HTTP connection with client. I'm doing this because I'm making an assumption that I will eventually be able to get ongoing feedback in outbound and inbound transfers, as in the TODO immediately below. ALSO: It just makes more sense to set this to InProgress before returning to the user. Otherwise, there is at least logically a race condition. e.g., The client app could have the result back before the status change.
    // TODO: We need to get some kind of ongoing feedback (e.g., a callback that occurs periodically on the basis of time or bytes transferred) from the cloud storage file transfer, and when we fail to get that ongoing feedback, we change the operation status to a failure status. See [1].

    psOperationId.operationStatus = ServerConstants.rcOperationStatusInProgress;
    psOperationId.error = null;
    
    op.result[ServerConstants.resultOperationIdKey] = psLock.operationId;

    psOperationId.update(function (updateError) {
        if (objOrInject(updateError, op, ServerConstants.dbTcInProgress)) {
            var errorMessage = "Could not update operation to rcOperationStatusInProgress: %s", updateError;
            logger.error(errorMessage);
            updateOperationId(psOperationId, ServerConstants.rcOperationStatusFailedBeforeTransfer, errorMessage);
            op.endWithErrorDetails(errorMessage);
        }
        else {
            // 2) Tell the user we're off to the races, and end the connection.
            op.endWithRC(ServerConstants.rcOK);
            
            // 3) Do the file transfer between the cloud storage system and the sync server.
            cloudStorageTransfer(op, psLock, psOperationId, transferMethodName);
        }
    });
}

// Update the operationId without specific error checking. This is for use in failure cases.
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

// transferMethod is given by a string-- this is a method of the FileTransfers.sjs class. FileTransfers.methodNameReceiveFiles or FileTransfers.methodNameSendFiles
// This function operates in asynchronous mode, i.e., with the connection to the client terminated already.
function cloudStorageTransfer(op, psLock, psOperationId, transferMethod) {
    logger.info("Attempting FileTransfers.setup...");
    var fileTransfers = new FileTransfers(op, psOperationId);

    fileTransfers.setup(function (error) {
        if (objOrInject(error, op, ServerConstants.dbTcSetup)) {
            var errorMessage = "Failed on setup: " + JSON.stringify(error);
            updateOperationId(psOperationId, ServerConstants.rcOperationStatusFailedBeforeTransfer, errorMessage);
        }
        else {
            logger.info("Attempting FileTransfers.%s...", transferMethod);

            fileTransfers[transferMethod](function (error) {
                if (objOrInject(error, op, ServerConstants.dbTcTransferFiles)) {
                    var errorMessage = "Error transferring files: " + JSON.stringify(error);
                    updateOperationId(psOperationId, ServerConstants.rcOperationStatusFailedDuringTransfer, errorMessage);
                    
                    // I'm not going to remove the lock here, in order to give the app a chance to recover from this error in a locked condition.
                    return;
                }

                // [6].
                psLock.removeLock(function (error) {
                    if (objOrInject(error, op,
                        ServerConstants.dbTcRemoveLockAfterCloudStorageTransfer)) {
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

        // 5/1/16; I just ran into a situation where the lock wasn't held beforehand, but it should have been. I've added an extra parameter to try to debug this.
        
        const requirePreviouslyHeldLock = request.body[ServerConstants.requirePreviouslyHeldLockKey]
        
        if (isDefined(psLock)) {
            // We already held the lock-- prior to this get file index operation, so get list of files, but don't remove the lock afterwards.
            finishOperationGetFileIndex(op, null);
        }
        else if (requirePreviouslyHeldLock) {
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError,
                "Should have previously held the lock!");
        }
        else {
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
    logger.debug("Getting list of files for userId: " + op.userId());
    
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
        PSOperationId.getFor(operationId, op.userId(), op.deviceId(), function (error, psOperationId) {
            if (error) {
                op.endWithErrorDetails(error);
            }
            else if (!isDefined(psOperationId)) {
                var errorMessage = "operationCheckOperationStatus: Could not get operation id: "
                    + operationId;
                logger.error(errorMessage);
                op.endWithErrorDetails(errorMessage);
            }
            else {
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
    // operationId is a string-- a parameter from the client.
    var operationId = request.body[ServerConstants.operationIdKey];
    
    if (!isDefined(operationId)) {
        var message = "No operationIdKey given in HTTP params!";
        logger.error(message);
        op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        return;
    }
    
    // Specifically *not* checking to see if we have a lock. If the operation has successfully completed, the lock will have been removed.

    // We already have the psOperationId, but go ahead and use the app/client's operationId to look it up. On second thoughts, look for any PSOperationId for the client. Then, compare, if any to the operationId string. We can check for more different types of errors this way.
    PSOperationId.getFor(null, op.userId(), op.deviceId(), function (error, psOperationId) {
        if (error) {
            op.endWithErrorDetails(error);
        }
        else if (!isDefined(psOperationId)) {
            // 4/27/16; We're not going to treat this as an error, in order to enable self-recovery for this method. That is, if the operationId has already been removed, but communication back to client failed, then we shouldn't fail if we don't find the operationId now.
            logger.info("Apparent recovery: Couldn't remove operation id: " + operationId);
            op.endWithRC(ServerConstants.rcOK);
        }
        else if (operationId != psOperationId._id) { // Seems we can use equality/inequality test directly across a string and ObjectID
            // Found operationId, but it wasn't the one we were looking for. Ouch!!
            var errorMessage = "removeOperationId: Could not get operation id: " + operationId + "; instead found: " + JSON.stringify(psOperationId);
            logger.error(errorMessage);
            op.endWithErrorDetails(errorMessage);
        }
        else {
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

// Removes PSOutboundFileChange's, removes the PSLock, and removes the PSOperationId (if any).
// TODO: Shouldn't this remove PSInboundFile's too?
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
        // 8/24/16; Going to go forward with this even if psOperationId.operationStatus is ServerConstants.rcOperationStatusInProgress-- because this is a cleanup operation, and we may be cleaning up from an operation that was in progress until it failed.
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

// Makes entries in PSInboundFile for each of the inbound files. Doesn't start the inbound transfers. This server API entry point can be called multiple times with the same parameters-- for recovery purposes. The 2nd time, etc., has no effect and doesn't fail.
app.post('/' + ServerConstants.operationSetupInboundTransfers, function (request, response) {
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
    
    op.validateUser(function (psLock, psOperationId) {
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

app.post('/' + ServerConstants.operationDownloadFile, function (request, response) {
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

    op.validateUser(function (psLock, psOperationId) {
        // Should not have the lock to download files.
        if (objOrInject(psLock, op, ServerConstants.dbTcGetLockForDownload)) {
        // Same check as:
        // if (isDefined(psLock)) {
            var message = "Error: Have the lock-- should not have lock to download files!";
            logger.error(message);
            endDownloadWithError(op, ServerConstants.rcServerAPIError, message);
        }
        else {
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
        }
    });
});

// Enable the client to remove a downloaded file from the PSInboundFile's, and from local storage on the sync server. Making this a separate operation from the download itself to ensure that the download is successful-- and to enable retries of the download.
app.post('/' + ServerConstants.operationRemoveDownloadFile, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.
        
        if (isDefined(psLock)) {
            var message = "We have the lock, but shouldn't!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        }
        else {
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
        }
    });
});

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

app.post('/' + ServerConstants.operationCreateSharingInvitation, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.

        if (!op.endIfUserNotAuthorizedFor(ServerConstants.sharingAdmin)) {
            return;
        }
                    
        var sharingType = request.body[ServerConstants.sharingType];
        if (!isDefined(sharingType)) {
            var message = "No sharingType was sent!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        var possibleSharingTypeValues = [ServerConstants.sharingDownloader, ServerConstants.sharingUploader, ServerConstants.sharingAdmin];
        
        // Ensure we got a valid sharingType

        if (possibleSharingTypeValues.indexOf(sharingType) == -1) {
            var message = "You gave an unknown sharingType: " + sharingType;
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        var sharingInvitation = new Mongo.SharingInvitation({
            owningUser: op.userId(),
            sharingType: sharingType
        });
        
        sharingInvitation.save(function (err, sharingInvitation) {
            if (err) {
                op.endWithErrorDetails(err);
            }
            else {
                logger.trace("New Sharing Invitation:");
                logger.debug(sharingInvitation);
                op.result[ServerConstants.sharingInvitationCode] = sharingInvitation._id;
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
});

app.post('/' + ServerConstants.operationLookupSharingInvitation, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function (psLock, psOperationId) {
        // User is on the system.
        
        var invitationCode = request.body[ServerConstants.sharingInvitationCode];
        if (!isDefined(invitationCode)) {
            var message = "No invitation code was sent!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        Mongo.SharingInvitation.findOne({ _id: invitationCode }, function (err, sharingInvitation) {
            if (err) {
                op.endWithErrorDetails(err);
            }
            else {
                logger.trace("Found Sharing Invitation:");
                logger.debug(sharingInvitation);
                
                // Make sure that the owningUser is us-- otherwise, this is a security issue.
                if (!op.userId().equals(sharingInvitation.owningUser)) {
                    logger.error("Current userId: " + op.userId() + "; owningUser: " + sharingInvitation.owningUser + "; typeof owningUser: " + typeof sharingInvitation.owningUser);
                    
                    var message = "You didn't own this sharing invitation!";
                    logger.error(message);
                    op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                    return;
                }

                var invitationContents = {};
                invitationContents[ServerConstants.invitationExpiryDate] = sharingInvitation.expiry;
                invitationContents[ServerConstants.invitationOwningUser] = sharingInvitation.owningUser;
                invitationContents[ServerConstants.invitationSharingType] = sharingInvitation.sharingType;
                
                op.result[ServerConstants.resultInvitationContentsKey] = invitationContents;
                
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
});

// You can redeem a sharing invitation for a new user (user created by this call), or for an existing user.
app.post('/' + ServerConstants.operationRedeemSharingInvitation, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }

    op.checkForExistingUser(function (error, staleUserSecurityInfo) {
        if (error) {
            if (staleUserSecurityInfo) {
                op.endWithRCAndErrorDetails(ServerConstants.rcStaleUserSecurityInfo, error);
            }
            else {
                op.endWithErrorDetails(error);
            }
        }
        else {
    
            // Make sure the creds are for a SharingUser. Do this after checkForExistingUser because in general, we may need to do a mongo lookup to determine if this user can be a sharing user.
            if (!op.sharingUserSignedIn()) {
                var message = "Error: Attempt to redeem sharing invitation by a non-sharing user!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }
    
            var invitationCode = request.body[ServerConstants.sharingInvitationCode];
            if (!isDefined(invitationCode)) {
                var message = "No invitation code was sent!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }

            finishRedeemingSharingInvitation(op, invitationCode, op.psUserCreds);
        }
    });
});

function finishRedeemingSharingInvitation(op, invitationCode, psUserCreds) {
    // The following query for findOneAndUpdate also does validation: It ensures the invitation hasn't already been redeemed, and hasn't expired. I'm assuming that this will take place atomically across possibly multiple server instances.
    
    // http://mongoosejs.com/docs/api.html#model_Model.findOneAndUpdate
    var now = new Date ();
    var query = {
        _id: invitationCode,
        redeemed: false,
        
        // I'm looking for an invitation that has an expiry that is >= the date right now. This defines expiry. E.g., say an expiry is: 2016-06-16T22:42:19.393Z
        // and the current date is: 2016-06-15T22:52:02.593Z
        "expiry": {$gte: now}
    };
    var update = { $set: {redeemed: true} };
    
    Mongo.SharingInvitation.findOneAndUpdate(query, update, function (err, invitationDoc) {
        if (err || !invitationDoc) {
            var message = "Error updating/redeeming invitation: It was a bad invitation, expired, or had already been redeemed.";
            logger.error(message + " error: " + JSON.stringify(err));
            op.endWithRCAndErrorDetails(
                ServerConstants.rcCouldNotRedeemSharingInvitation, message);
        }
        else {
            
            // Errors after this point will fail and will have marked the invitation as redeemed. Not the best of techniques, but once we get initial testing done, failures after this point should be rare. It would, of course, be better to rollback our db changes. :(. Thanks MongoDB! Not!
            // In the worst case we get an invitation that is marked as redeemed, but it fails to allow linking for the user. Presumably, the person that did the inviting in that case would have to generate a new invitation.
            
            logger.trace("Found and redeemed Sharing Invitation: " + JSON.stringify(invitationDoc));
                
            // Need to link the invitation into the sharing user's account.
            
            var newLinked = {
                owningUser: invitationDoc.owningUser,
                sharingType: invitationDoc.sharingType
            };
                        
            // First, let's see if the given owningUser is already present in the sharing user's linked accounts.
            var found = false;
            if (psUserCreds.stored) {
                logger.debug("looking for owningUser in linked accounts");
                
                for (var linkedIndex in psUserCreds.linked) {
                    var linkedCreds = psUserCreds.linked[linkedIndex];
                    var linkedOwningUser = linkedCreds.owningUser;
                    var invitationOwningUser = invitationDoc.owningUser;
                    
                    // See http://stackoverflow.com/questions/11060213/mongoose-objectid-comparisons-fail-inconsistently/38298148#38298148 for the reason for using string comparison and not the .equals method of ObjectID's.
                    
                    if (String(invitationOwningUser) === String(linkedOwningUser)) {
                        logger.info("Redeeming with existing owningUser: Replacing.");
                        found = true;
                        psUserCreds.linked[linkedIndex] = newLinked;
                        break;
                    }
                }
            }
            
            if (psUserCreds.stored) {
                if (!found) {
                    psUserCreds.linked.push(newLinked);
                }
                
                var saveAll = true;
                psUserCreds.update(function (err) {
                    if (err) {
                        op.endWithErrorDetails(err);
                    }
                    else {
                        op.result[ServerConstants.linkedOwningUserId] = invitationDoc.owningUser;
                        op.endWithRC(ServerConstants.rcUserOnSystem);
                    }
                });
            }
            else {
                psUserCreds.linked.push(newLinked);
                
                // User creds not yet stored in Mongo. Store 'em.
                psUserCreds.storeNew(function (error) {
                    if (error) {
                        op.endWithErrorDetails(error);
                    }
                    else {
                        op.result[ServerConstants.linkedOwningUserId] = invitationDoc.owningUser;
                        op.result[ServerConstants.internalUserId] = psUserCreds._id;
                        op.endWithRC(ServerConstants.rcOK);
                    }
                });
            }
        }
    });
}

app.post('/' + ServerConstants.operationGetLinkedAccountsForSharingUser, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
        
    op.validateUser({mustHaveLinkedOwningUserId:false}, function (psLock, psOperationId) {
        // User is on the system.

        if (!op.sharingUserSignedIn()) {
            var message = "Error: Attempt to get linked accounts by a non-sharing user!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        op.psUserCreds.makeAccountList(function (error, accountList) {
            if (error) {
                logger.error("Failed on makeAccountList for PSUserCredentials: " + JSON.stringify(error));
                op.endWithErrorDetails(error);
            }
            else {
                op.result[ServerConstants.resultLinkedAccountsKey] = accountList;
                op.endWithRC(ServerConstants.rcOK);
            }
        });
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

app.listen(serverPort, serverIPAddress, function() {
  logger.info('Node app is running on port ' + serverPort);
  logger.info('     with IP address: ' + serverIPAddress);
});


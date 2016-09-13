// Accessing the users cloud storage to transfer files. This deals with the details of the cloud storage systems (e.g., Google Drive).
// This class is closely coupled to GoogleUserCredentials. E.g., it knows about GoogleUserCredentials .oauth2Client property.

/* 7/26/16; Sometimes Google Drive puts (n) at the end of file names. I'm not sure which file it will read. See 
https://productforums.google.com/forum/#!topic/drive/XJzVGC868DQ
https://productforums.google.com/forum/#!topic/drive/WPF82xwXR-o
*/

'use strict';

const AccessTokenExpired = 401;

// See https://developers.google.com/api-client-library/javascript/reference/referencedocs
// https://github.com/google/google-api-nodejs-client/blob/master/apis/drive/v2.js
var google = require('googleapis');
var fs = require('fs');

var logger = require('./Logger');
var File = require('./File.sjs');
var PSUserCredentials = require('./PSUserCredentials');
var ServerConstants = require('./ServerConstants');

// Constructor
// psUserCreds: cloudStorageCreds() must be of type GoogleUserCredentials
function GoogleCloudStorage(psUserCreds, cloudFolderPath) {
    var self = this;
    
    self.psUserCreds = psUserCreds;
    
    var googleUserCredentials = self.psUserCreds.cloudStorageCreds();
    
    if (googleUserCredentials.accountType != ServerConstants.accountTypeGoogle) {
        throw new Error("Expected account type: " + ServerConstants.accountTypeGoogle);
    }
    
    self.oauth2Client = googleUserCredentials.oauth2Client;
    
    self.cloudFolderPath = cloudFolderPath;
    self.cloudFolderId = null;
}

// instance methods

// Callback: One parameter: error.
GoogleCloudStorage.prototype.setup = function (callback) {
    var self = this;
    
    /* Need to:
    1) See if our cloudFolderPath folder exists at the root of the cloud storage system
    2) If it doesn't, create it, and get its file/folderId
    
    Originally, I was going to get a listing of all files in our cloud folder. HOWEVER, Google places limits on the number of files returned in a listing. So, it seems better to do this on a per file basis. Number of files returned has default of 100, and a max of 1000. See https://developers.google.com/drive/v2/reference/files/list
    */
    var query = "mimeType = 'application/vnd.google-apps.folder' and title = '"
        + self.cloudFolderPath + "' and trashed=false";
    
    self.listFiles(query, function (error, files) {
        if (error) {
            logger.error("GoogleCloudStorage.setup: Failed on listFile: " + JSON.stringify(error))
            callback(error);
        }
        else {
            // logger.info("files from query: " + JSON.stringify(files));
            if (files.length == 0) {
                // Our cloud folder didn't exist. Create it.
                self.createDirectory(self.cloudFolderPath, function (error, folderId) {
                    if (!error) {
                        self.cloudFolderId = folderId;
                    }
                    callback(error);
                });
            }
            else if (files.length > 1) {
                // Some odd error!
                callback("More than one cloud folder!");
            }
            else {
                // The cloud folder existed! Yea!. Need to get its folder id.
                self.cloudFolderId = files[0].id;
                logger.info("cloudFolderId: " + self.cloudFolderId);
                    
                // DEBUGGING
                // self.listAllFiles();
    
                callback(null);
            }
        }
    });
}

// fileToSend is a File object.
GoogleCloudStorage.prototype.deleteFile = function (fileToSend, callback) {
    var self = this;
    self.sendFile(true, fileToSend, callback);
}

// fileToSend is a File object.
// Stream the file to cloud storage.
// Callback params: 1) error, 2) file properties (if error is null).
GoogleCloudStorage.prototype.outboundTransfer = function (fileToSend, callback) {
    var self = this;
    self.sendFile(false, fileToSend, callback);
}

// fileToReceive is of type File
// Copy data (i.e., download) of the file to the SyncServer from cloud storage.
// Callback params: 1) error, 2) file properties (if error is null).
GoogleCloudStorage.prototype.inboundTransfer = function (fileToReceive, callback) {
    var self = this;
    
    var drive = google.drive({ version: 'v2', auth: self.oauth2Client });
    
    var cloudFileName = fileToReceive.cloudFileName;
    var mimeType = fileToReceive.mimeType;
    
    // Adapted from https://developers.google.com/drive/v3/web/manage-downloads
    // See also https://gist.github.com/davestevens/6f376f220cc31b4a25cd
    
    if (!isDefined(self.cloudFolderId)) {
        callback(new Error("cloudFolderId is not defined!"), null);
        return;
    }
    
    // I'm *not* including the mime type in the search criteria. Rather just look to see if a file with this title is present in the folder. Then, as a second step, check to see if the mime type is what we expect. I suspect with Google Drive we can have two files with the same name but different mime types.
    
    // First, see if our file exists in the cloud folder.
    var query = "title = '" + cloudFileName + "' "
            + " and '" + self.cloudFolderId + "' in parents and trashed=false";
    
    self.listFiles(query, function (error, files) {
        if (error) {
            callback(error, null);
        }
        else if (files.length != 1) {
            callback(
                new Error("Yikes! Some funky error! More than one file or zero files: "
                    + JSON.stringify(files)), null);
        }
        else {
            var existingFile = files[0];
            
            // We're not going to allow two files with the same file name, and different MIME type. I think Google Drive allows this, but we'll consider it an error just because at this point I don't think we need this flexibility.
            
            if (existingFile.mimeType != mimeType) {
                callback(new Error("Two files with same name and different mime type!"), null);
                return;
            }

            var parameters = {
                fileId: existingFile.id,
                alt: "media"
            };

            logger.debug("Receiving Google Drive file with fileId: %s", existingFile.id);
           
            var suffixCall = {
                method: "pipe",
                param: dest.stream
            };
           
            self.callGoogleDriveAPI(drive.files.get, parameters, suffixCall, function(err, response) {
                var fileProperties = null;
                if (err) {
                    logger.error('The API returned an error: drive.files.get: %j', err);
                }
                else {
                    fileProperties = {};
                    
                    // 5/20/16; If the file we're dealing with is empty, response appears to be nil. Yikes!
                    var fileSize = 0;
                    if (isDefined(response)) {
                        fileSize = response.fileSize;
                    }
                    
                    fileProperties.fileSizeBytes = fileSize;
                }
                
                callback(err, fileProperties);
                logger.debug("fileProperties: %j", fileProperties);
            });
        }
    });
}

// It seems you can't replace a file in Google Drive, with one of the existing title, all in one step. See http://stackoverflow.com/questions/34110694/can-i-do-a-google-drive-insert-rest-operation-replacing-an-existing-file-with-t

// PRIVATE
// Transfer a file to the users cloud storage or delete the file.
// Parameter:
//      1) deleteTheFile: Boolean: If true, file is being deleted.
//          If false, file is being transferred.
//      2) fileToSend of type File.
// Callback parameters: 1) error, 2) If error is null, a JSON structure with the following properties: fileSizeBytes (only when not deleting).
GoogleCloudStorage.prototype.sendFile = function (deleteTheFile, fileToSend, callback) {
    var self = this;
    
    var drive = google.drive({ version: 'v2', auth: self.oauth2Client });
    
    var cloudFileName = fileToSend.cloudFileName;
    var mimeType = fileToSend.mimeType;
    
    var mediaParameter = null;
    
    if (!deleteTheFile) {
        mediaParameter = {
            mimeType: mimeType,
            body: fileToSend.fileReadStream
        };
    }
    
    // Adapted from https://github.com/google/google-api-nodejs-client/
    // The resource key here seems have sub-keys from the "File resource" in https://developers.google.com/drive/v2/reference/files/insert
    // See also https://developers.google.com/drive/v2/reference/files#resource
    // And see http://www.codeproject.com/Articles/1042234/NodeJs-Google-Drive-Backup
    
    if (!isDefined(self.cloudFolderId)) {
        callback(new Error("cloudFolderId is not defined!"), null);
        return;
    }
    
    // I'm *not* including the mime type in the search criteria. Rather just look to see if a file with this title is present in the folder. Then, as a second step, check to see if the mime type is what we expect. I suspect with Google Drive we can have two files with the same name but different mime types.
    
    // First, see if our file exists in the cloud folder.
    var query = "title = '" + cloudFileName + "' "
            + " and '" + self.cloudFolderId + "' in parents and trashed=false";
    
    self.listFiles(query, function (error, files) {
        if (error) {
            callback(error, null);
        }
        else {
            if (files.length > 1) {
                callback(new Error("Yikes! Some funky error! More than one file: " + JSON.stringify(files)), null);
            }
            else if (files.length == 1) {
                var existingFile = files[0];
                
                // We're not going to allow two files with the same file name, and different MIME type. I think Google Drive allows this, but we'll consider it an error just because at this point I don't think we need this flexibility.
                
                if (existingFile.mimeType != mimeType) {
                    callback(new Error("Two files with same name and different mime type!"), null);
                    return;
                }

                // See https://developers.google.com/drive/v2/reference/files/update#examples
                var parameters = {
                    fileId: existingFile.id
                };
                
                if (!deleteTheFile) {
                    parameters.newRevision = false;
                    parameters.resource = { mimeType: mimeType };
                    parameters.media = mediaParameter;
                }
                
                if (deleteTheFile) {
                    logger.debug("Doing a file deletion: fileId: %s", existingFile.id);
                   
                    // Using drive.files.trash and not drive.files.delete so that earlier versions of file might be recovered (e.g., by the end-user).
                    self.callGoogleDriveAPI(drive.files.trash, parameters, function(err, response) {
                        if (err) {
                            logger.error('The API returned an error: drive.files.trash: %j', err);
                        }
                        callback(err, null);
                        // logger.debug("Google Drive API Response: %j", response);
                    });
                }
                else {
                    logger.debug("Doing a file update: Existing Google Drive fileId: %s",
                        existingFile.id);
                   
                    self.callGoogleDriveAPI(drive.files.update, parameters, function(err, response) {
                        var fileProperties = null;
                        if (err) {
                            logger.error('The API returned an error: drive.files.update: %j', err);
                        }
                        else {
                            fileProperties = {};
                            fileProperties.fileSizeBytes = response.fileSize;
                        }
                        callback(err, fileProperties);
                        // logger.debug("Google Drive API Response: %j", response);
                    });
                }
            }
            else { // File absent on Google Drive.
                if (deleteTheFile) {
                    var message = "Yikes: Attempting to delete an absent file!";
                    logger.error(message);
                    callback(new Error(message), null);
                    return;
                }
                
                logger.debug("Doing a file insert: Must be a new file: Inserting into parent: " + self.cloudFolderId);
                
                // TODO: If we had access right now to the fileVersion given to us by the app, we could make sure that the version was 0. HOWEVER, this means we'll fail if the user happens to delete a file. Which they shouldn't be doing, but...
                
                var parameters = {
                    resource: {
                        title: cloudFileName,
                        mimeType: mimeType,
                        // See https://developers.google.com/drive/web/folder for the notation for parents.
                        parents: [{
                            "id": self.cloudFolderId
                        }]
                    },
                    media: mediaParameter
                };
                
                self.callGoogleDriveAPI(drive.files.insert, parameters, function(err, response) {
                    var fileProperties = null;
                    if (err) {
                        logger.error('The API returned an error: drive.files.insert: %j', err);
                    }
                    else {
                        fileProperties = {};
                        fileProperties.fileSizeBytes = response.fileSize;
                    }
                    // logger.debug("Google Drive API Response: %j", response);
                    callback(err, fileProperties);
                });
            }
        }
    });
}

// PRIVATE (but need access to object members)
/* Obtains a list of all of the files in a folder. If query is not given (only the callback is given), then obtains a list of the files in the root directory on the cloud storage. If query is given, then obtains a list of the files constrained by the query. For Google Drive query, see https://developers.google.com/drive/web/search-parameters

    Make sure you add "and trashed = false" to exclude trashed files from your query results. When I delete a file from Google Drive (e.g., on my Mac), it gets placed in the trash. By default, a list files operation will still find (and can update!) that trashed file. Which seems confusing.

    Callback has two parameters: 1) error, 2) if error is null, the array of files.
*/
GoogleCloudStorage.prototype.listFiles = function (query, callback) {
    var self = this;
    
    var parameters = {
        auth: self.oauth2Client
    };
    
    if (typeof query === 'function') {
        callback = query;
        query = null;
    }
    else {
        parameters["q"] = query;
    }

    var drive = google.drive('v2');
    
    logger.info("GoogleCloudStorage: listFiles: About to call callGoogleDriveAPI: parameters: " + JSON.stringify(parameters));
    
    self.callGoogleDriveAPI(drive.files.list, parameters, function(err, response) {
        if (err) {
            logger.error('GoogleCloudstorage: listFiles: The API returned an error: drive.files.list: %j', err);
            callback(err, null);
            return;
        }
        
        callback(null, response.items);
    });
}

// PRIVATE (but need access to object members)
/* Create a directory.
Callback has two parameters: 1) error, 2) if error is null, the fileId of the created directory.
*/
GoogleCloudStorage.prototype.createDirectory = function (directoryTitle, callback) {
    var self = this;
    
    var drive = google.drive({ version: 'v2', auth: self.oauth2Client });
    
    var parameters = {
        resource: {
            title: directoryTitle,
            mimeType: 'application/vnd.google-apps.folder'
        }
    };
    
    self.callGoogleDriveAPI(drive.files.insert, parameters, function(err, response) {
        if (err) {
            logger.error('The API returned an error: drive.files.insert: %j',  err);
            callback(err, null);
            return;
        }
        
        logger.debug("folder id: " + response.id);
        callback(null, response.id);
    });
}

/* If a Google Drive operation fails, the first step should be to use the refresh token to get a new access token, and then retry the operation. If it fails a second time, we can call that a failure. It would be good though to be able to detect that an operation failed because we need to get a new access token. Can we do this? YES.
2015-12-07T21:36:21-0700 <error> CloudStorage.sjs:108 () The API returned an error: {"code":401,"errors":[{"domain":"global","reason":"authError","message":"Invalid Credentials","locationType":"header","location":"Authorization"}]}
2015-12-07T21:36:21-0700 <error> Server.sjs:225 () Failed on setup: Error: Invalid Credentials

See http://stackoverflow.com/questions/17813621/oauth2-0-token-strange-behaviour-invalid-credentials-401
This is because of an expired access token.
*/

// PRIVATE
// Calls a Google Drive REST API function. Assumes that the callback & the apiFunction callback take two parameters, error and response. If the operation fails on an AccessTokenExpired error, this attempts to refresh the access token. If a second error occurs, this reported back to the original callback.
// suffixCall is optional and if given is an object with properties: method (method name string), and param (parameter value). It will be called on the function result of calling the apiFunction.
GoogleCloudStorage.prototype.callGoogleDriveAPI = function (apiFunction, parameters, suffixCall, callback) {
    var self = this;
    
    self.callGoogleDriveAPIAux(2, apiFunction, parameters, suffixCall, callback);
}

// Don't call this directly. Call the above function.
GoogleCloudStorage.prototype.callGoogleDriveAPIAux =
    function (numberAttempts, apiFunction, parameters, suffixCall, callback) {
        var self = this;
        
        if (typeof suffixCall === 'function') {
            callback = suffixCall;
            suffixCall = null;
        }
        
        logger.info("GoogleCloudStorage.callGoogleDriveAPIAux: Call number: " + numberAttempts);
        
        function apiFunctionCallback(err, response) {
           if (err && (numberAttempts > 1) && isDefined(err.code) && (AccessTokenExpired == err.code)) {
                // Attempt to refresh the access token, and then if successful, call the API function again.
                logger.trace("Access token expired: Attempting to refresh");
                
                self.psUserCreds.signedInCreds().refreshSecurityTokens(function (err) {
                    if (err) {
                        logger.error("Failed on refreshing access token: %j", err);
                        callback(err, response);
                    }
                    else {
                        logger.info("Succeeded on refreshing access token");

                        // Save the updated psUserCreds to persistent storage.
                        self.psUserCreds.update(function (error) {
                            if (error) {
                                logger.error("Failed to save updated access token to persistent storage %j", error)
                                callback(error, null);
                            }
                            else {
                                // Call the API function again. Use recursion.
                                self.callGoogleDriveAPIAux(numberAttempts--, apiFunction, parameters, callback);
                            }
                        });
                    }
                });
            }
            else {
                callback(err, response);
            }
        }
        
        if (isDefined(suffixCall)) {
            (apiFunction(parameters, function (err, response) {
                apiFunctionCallback(err, response);
            }))[suffixCall.method](suffixCall.param);
        }
        else {
            apiFunction(parameters, function (err, response) {
                apiFunctionCallback(err, response);
            });
        }
    }

// DEBUGGING

GoogleCloudStorage.prototype.listAllFiles = function() {
    var self = this;
    
    logger.info("listAllFiles: Listing files...");
    
    if (!isDefined(self.cloudFolderId)) {
        logger.debug("listAllFiles: self.cloudFolderId is not defined");
        return;
    }
    
    var query = "'" + self.cloudFolderId + "' in parents";
    
    self.listFiles(query, function (error, files) {
        if (error) {
            logger.error("listAllFiles: Error listing files: " + error);
        }
        else {
            if (files.length == 0) {
                logger.info('listAllFiles: No files found.');
            }
            else {
                logger.info('listAllFiles: Files:');
                
                for (var i = 0; i < files.length; i++) {
                    var file = files[i];
                    logger.info("File#" + i + ': %s (%s); %j', file.title, file.id, file);
                }
            }
        }
    });
}

// export the class
module.exports = GoogleCloudStorage;

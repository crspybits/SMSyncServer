// Persistent Storage to represent an index of file changes that are "Outbound" -- pending transmission to the users cloud storage system. These consist of file uploads and file deletions.

'use strict';

var fse = require('fs-extra');

var Mongo = require('./Mongo');
var File = require('./File.sjs')
var logger = require('./Logger');
var Common = require('./Common');
var ServerConstants = require('./ServerConstants');

const collectionName = "OutboundFileChanges";

// These must exactly match those properties given in the data model below.
const props = ["_id", "fileId", "userId", "deviceId", "toDelete", "cloudFileName", "mimeType", "appMetaData", "fileVersion", "committed"];

// Note that same names used across some of the properties in this class and PSFileIndex are important and various dependencies exist.

/* Data model
    {
        // Primary key for this change; assigned by Mongo; I'm letting Mongo assign this and not using the fileId because this collection represents files *across* users and at least conceptually, the namespace of UUID's for each user is distinct.
        _id: (ObjectId),
 
        // Together, these two form a unique key.
		fileId: (String, UUID), // fileId; permanent reference to file, assigned by app
		userId: (String), // reference into PSUserCredentials (i.e., _id from PSUserCredentials)
 
        deviceId: (String, UUID), // identifies a specific mobile device (assigned by app)
 
        // delete the file on the cloud storage system? If true, this doesn't represent a pending file upload, but rather a pending file deletion. Note that I'm not using the term "delete" here because that's a keyword in Javascript.
		toDelete: (true | false),
 
        cloudFileName: (String), // name of the file in cloud storage excluding the folder path.
 
        mimeType: (String), // MIME type of the file
        appMetaData: (JSON structure), // App-specific meta data
        
		fileVersion: (Integer value), // values must be >= 0.
        
        // Initially false, and set to true when app has uploaded/marked for deletion all the files to the SyncServer in the collection it is uploading. Note that this is *not* about transfering the files to user-owned cloud storage. Rather, it's about the app uploading the file(s) to the SyncServer in preparation for transfer to cloud storage.
        committed: boolean
	}
	
	Details: The entry is removed from this collection immediately after the file has been sent to the server. A Lock is held until all entries are removed for the particular userId/deviceId pair. While the lock is held, this userId cannot request uploads. (This makes some sense because other devices using the same userId should receive these updates first). While this lock is held, the user also cannot request downloads. (This is a simplifying assumption, and also makes some sense: We wouldn't want the same userId to start a download on a file that was being uploaded concurrently).
    For the purposes of an MVP, or at least an alpha version, we can strengthen this idea of a lock so that while any entries exist in this table for a given userId, we will not allow any uploads or downloads by another user. (In general this seems too strong-- because what if one user/device starts a series of file uploads, but doesn't end up committing those? A lock will be held for an arbitrary period of time until that user/device completes its operation.).
*/

// Constructor
/* fileData should be an Object with all of the properties in the data model above, with the following exceptions: 
    1) You can include the committed property if you want. By default it will get set to false. 
    2) For a PSOutboundFileChange object that doesn't exist yet in persistent storage, don't supply the _id key in the fileData.
*/
// Throws an exception in the case of an error.
function PSOutboundFileChange(fileData) {
    var self = this;

    Common.assignPropsTo(self, fileData, props);

    if (!isDefined(self.committed)) {
        self.committed = false;
    }

    if (isDefined(self.fileVersion) && self.fileVersion < 0) {
        throw new Error("fileVersion < 0: " + self.fileVersion);
    }
}

// Return only the data properties.
// Can throw error.
PSOutboundFileChange.prototype.dataProps = function () {
    var self = this;
    var returnProps = {};
    Common.assignPropsTo(returnProps, self, props);
    return returnProps;
}

// The lastModified property is not given. The deleted property of the resulting object should be interpreted as the intent to mark as deleted.
// Returns an object with a subset of PSFileIndex keys.
PSOutboundFileChange.prototype.convertToFileIndex = function () {
    var self = this;
    
    var fileIndexData = {};
    
    fileIndexData[ServerConstants.fileIndexFileId] = self.fileId;
    fileIndexData[ServerConstants.fileIndexCloudFileName] = self.cloudFileName;
    fileIndexData[ServerConstants.fileIndexMimeType] = self.mimeType;
    fileIndexData[ServerConstants.fileIndexFileVersion] = self.fileVersion;
    fileIndexData[ServerConstants.fileIndexDeleted] = self.toDelete;
    fileIndexData[ServerConstants.fileIndexAppMetaData] = self.appMetaData;
    
    return fileIndexData;
}

// instance methods

// Save a new object in persistent storage based on the member variables of this instance.
// Callback has one parameter: error.
PSOutboundFileChange.prototype.storeNew = function (callback) {
    var self = this;

    // TODO: We should not allow multiple changes in the collection of outbound file changes for the the same userId/fileId/deviceId. That is, why should an app be putting in a request for two changes, in the same group of changes, for the same file?
    
    Common.storeNew(self, collectionName, props, callback);
}

// Commit all changes for the userId/deviceId pair. Just marks all those documents having their commited property set to true.
// There must be at least one change document to commit.
// This is a "class" method in that you don't call it with an instance.
// Callback parameters: 1) Error, 2) If no error, provides the number of changes committed. (Note that this can be 0 in some recovery cases where the commit is being repeated but was successful previously).
PSOutboundFileChange.commit = function (userId, deviceId, callback) {
    var query = {
        userId: userId,
        deviceId: deviceId
    };
    
    var update = {
        committed: true
    };

    Mongo.db().collection(collectionName).updateMany(query, {$set: update},
        function(err, results) {
            // console.log(results);
            if (err) {
                callback(err, null);
            }
            else {
                logger.info("Number of change committed: " + results.result.nModified);
                callback(null, results.result.nModified);
            }
        });
}

// Looks up a PSOutboundFileChange object based on the instance values. On success the instance has its values populated by the found object.
// Callback parameters: 1) error, 2) if error is null, a boolean indicating if the object could be found. It is an error for more than one object to be found in a query using the instance values.
PSOutboundFileChange.prototype.lookup = function (callback) {
    Common.lookup(this, this, props, collectionName, callback);
}

// Callback parameters: 1) error, 2) if error not null, an array of PSOutboundFileChange objects describing the outbound file changes pending for this userId/deviceId.
PSOutboundFileChange.getAllCommittedFor = function (userId, deviceId, callback) {
    PSOutboundFileChange.getAllFor(userId, deviceId, true, callback);
}

// The state parameter is optional, but can be true or false for committed or not committed. It defaults to obtaining all PSOutboundFileChange independent of true or false.
// Callback parameters: 1) error, 2) if error not null, an array of PSOutboundFileChange objects describing the outbound file changes pending for this userId/deviceId. This array is zero length if no PSOutboundFileChange objects were found.
PSOutboundFileChange.getAllFor = function (userId, deviceId, state, callback) {
    var query = {
        userId: userId,
        deviceId: deviceId
    };
    
    if (typeof state === 'function') {
        callback = state;
        state = null;
    }
    else {
        query.committed = state;
    }
	
	var cursor = Mongo.db().collection(collectionName).find(query);
		
	if (!cursor) {
		callback("Failed on find!");
		return;
	}

    var result = [];
    
    cursor.each(function(err, doc){
        if (err) {
            callback(err, null);
            return;
        }
        else if (!doc) {
            callback(null, result);
            return;
        }
        
        // make a new PSOutboundFileChange for the doc
        var outboundFileChange = new PSOutboundFileChange(doc);
        result.push(outboundFileChange);
    });
}

// Remove the PSOutboundFileChange object from MongoDb.
/* Parameters:
    1) removeLocal: Boolean; removes the local file system file represented by this object iff removeLocal is true. (optional-- default is true).
    2) callback.
*/
// If the deletion of the PSOutboundFileChange object fails, and removeLocal is true, the local file system file doesn't get deleted.
// Callback parameter: error
PSOutboundFileChange.prototype.remove = function (removeLocal, callback) {
    var self = this;
    
    if (typeof removeLocal === 'function') {
        callback = removeLocal
        removeLocal = true
    }
    
    // Overkill on overqualifying the query, but why not?
    var query = Common.extractPropsFrom(self, props);

    Mongo.db().collection(collectionName).deleteOne(query,
        function(err, results) {
            // console.log(results);
            
            if (err) {
                callback(err);
            }
            else if (0 == results.deletedCount) {
                callback("Could not delete remove PSOutboundFileChange!");
            }
            else if (results.deletedCount > 1) {
                callback("Yikes! Removed more than one PSOutboundFileChange!");
            }
            else {
                if (removeLocal) {
                    // TODO: Make sure this doesn't fail if the file isn't there already. This should help in error recovery.
                    var localFile = new File(self.userId, self.deviceId, self.fileId);
                    var localFileNameWithPath = localFile.localFileNameWithPath();

                    fse.remove(localFileNameWithPath, function (err) {
                        callback(err);
                    });
                }
                else {
                    callback(null);
                }
            }
        });
}

// export the class
module.exports = PSOutboundFileChange;

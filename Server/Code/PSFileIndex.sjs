// Persistent Storage to represent meta info about the users cloud-stored files, i.e., files that are stored (or were previously stored) in the users specific cloud storage system.

'use strict';

var Mongo = require('./Mongo');
var logger = require('./Logger');
var Common = require('./Common');
var ServerConstants = require('./ServerConstants');
var ObjectID = require('mongodb').ObjectID;

const collectionName = "FileIndex";

// These must match those properties given in the data model below. Callers of this class don't supply lastModified. lastModified is added by this class.
const props = ["_id", "userId", ServerConstants.fileIndexFileId, ServerConstants.fileIndexCloudFileName, ServerConstants.fileIndexMimeType, ServerConstants.fileIndexAppMetaData, ServerConstants.fileIndexDeleted, ServerConstants.fileIndexFileVersion, ServerConstants.fileIndexLastModified, ServerConstants.fileSizeBytes];

// Note that the same names used across some of the properties in this class and PSOutboundFileChanges are important and various dependencies exist.

/* 
1/7/15; What about merging/combining this collection with the PSOutboundFileChange collection? I.e., can I get by with just a single one of these collections? One issue with this is that if a file was already uploaded (i.e., had an entry in PSFileIndex), how would we represent the fact of the new upload? We'd have to differentiate, using properties in the collection, between at least: 1) an uploaded file in cloud storage, 2) an uploaded file in cloud storage where we also were uploading a new version, 3) a file we were in the process of uploading. Plus we'd need an additional property for a new fileSizeBytes being uploaded. And an additional property for toDelete when the current file wasn't deleted but the operation was indicating it should be deleted. Further, a deviceId isn't needed for the file index, but is needed for the file being uploaded.
It seems like this could get confusing.
*/

/* Data model
	{
        // Primary key for this file; assigned by Mongo; I'm letting Mongo assign this and not using the fileId because this collection represents files *across* users and at least conceptually, the namespace of UUID's for each user is distinct.
        _id: (ObjectId),
 
        // Together, these two form a unique key.
		fileId: (UUID), // fileId (app/client assigned)
		userId: (ObjectId), // reference into PSUserCredentials collection
        
		cloudFileName: (String), // name of the file on the cloud storage system (without path)
        mimeType: (String), // MIME type of the file
        appMetaData: (JSON structure), // App-dependent meta data
		deleted: (true | false),
        
        // Intended to allow the app/client determine if a change has happened to the file.
		fileVersion: (Integer value),
        
        // The caller of this class should not provide this property. This is added/modified internally when the file is updated/created on cloud storage.
        // This date should not be depended on for detecting changes to the file. I.e., the client/app should use the fileVersion to check if the file has changed. (I've added this largely for convenience in development-- I wanted to see if the change I made actually occurred).
        lastModified: (Date)
        
        // Size of file in cloud storage.
        fileSizeBytes: (Integer value)
	}
*/

// Constructor
// properties in fileData must be from props.
// Can throw error.
function PSFileIndex(fileData) {
    var self = this;
    
    Common.assignPropsTo(self, fileData, props);
    
    if (isDefined(self.fileVersion) && self.fileVersion < 0) {
        throw "fileVersion < 0: " + self.fileVersion;
    }
    
    if (!isDefined(self.deleted)) {
        self.deleted = false;
    }
}

// Save a new object in persistent storage based on the member variables of this instance.
// Callback has one parameter: error.
PSFileIndex.prototype.storeNew = function (callback) {
    var self = this;
    
    self.lastModified = new Date();
    
    // TODO: Don't allow insertion of a PSFileIndex object that has identical fileId and userId. Can we impose a constraint during insertion that doesn't allow this so we get an atomic operation that disallows this duplication?

    Common.storeNew(self, collectionName, props, callback);
}

// Return null if the new version is one more than this instances version, or the same version if sameVersionAllowed is true. Returns a descriptive error string otherwise.
PSFileIndex.prototype.checkNewFileVersion = function (newVersion, sameVersionAllowed) {
    var self = this;
    
    if (sameVersionAllowed === undefined) {
        sameVersionAllowed = false; // default value
    }

    var fileVersion = parseInt(self.fileVersion)
    var expectedVersion = fileVersion + 1;
    logger.debug("expectedVersion: " + expectedVersion);
    logger.debug("newVersion: " + newVersion);
    var updatedVersion = parseInt(newVersion)
    
    if (sameVersionAllowed && (fileVersion == updatedVersion)) {
        return null
    }
    else if (expectedVersion != updatedVersion) {
        return "Error: Updated file version (" + updatedVersion + ") is not that expected (" + expectedVersion + ").";
    }
    else {
        return null;
    }
}

// If there is no object with the current properties in PS, store a new one. If there is one, update that one. New update must have a version exactly one greater than the previous.
// If the optional sameVersionIfExists (boolean) parameter is given, and it is true, then if updating a PSFileIndex object, the new update can have exactly the same version as the previous (this is for recovery).
// Callback has one parameter: error.
PSFileIndex.prototype.updateOrStoreNew = function (sameVersionIfExists, callback) {
    var self = this;
    
    if (typeof sameVersionIfExists === 'function') {
        callback = sameVersionIfExists;
        sameVersionIfExists = false;
    }
    
    PSFileIndex.getAllFor(self.userId, self.fileId, function (error, result) {
        if (error) {
            callback(error);
        }
        else if (result.length == 0) {
            logger.debug("New object: %j", self);

            // No object exists.
            self.storeNew(callback);
        }
        else if (result.length > 1) {
            var message = "Yikes: More than one object in index for the userId and fileId: " + JSON.stringify(result);
            callback(new Error(message));
        }
        else { // result.length == 1; update object.
            var previousFileIndexObject = result[0];

            if (self.deleted) {
                if (self.fileVersion != previousFileIndexObject.fileVersion) {
                    var message = "Trying to delete different version of file";
                    callback(new Error(message));
                    return;
                }
            }
            else {
                // Check the version of the previous item in the file index.
                var errorMessage = previousFileIndexObject.checkNewFileVersion(self.fileVersion, sameVersionIfExists);

                if (isDefined(errorMessage)) {
                    callback(new Error(errorMessage));
                    return;
                }
            }
            
            var query = {
                userId: self.userId,
                fileId: self.fileId
            };
            
            // Make a clone so that I can remove the _id; don't want to update the _id.
            
            // var newFileIndexData = JSON.parse(JSON.stringify(self));
            /* Danger Will Robinson!
                JSON.parse(JSON.stringify(X)) is not necessarily equivalent to X! See example:
             
                > function Foo() {}
                undefined
                > var x = new Foo()
                undefined
                > x
                Foo {}
                > var y = {x: x};
                undefined
                > y
                { x: Foo {} }
                > JSON.parse(JSON.stringify(y));
                { x: {} }
            */
            
            var newFileIndexData = Common.extractPropsFrom(self, props);
            delete newFileIndexData._id;
            newFileIndexData.lastModified = new Date();
            
            logger.debug("Updating with: %j", newFileIndexData);
            
            Mongo.db().collection(collectionName).updateOne(query, {$set: newFileIndexData},
                function(err, results) {
                    callback(err);
                });
        }
    });
}

// Looks up a PSFileIndex object based on the instance values. On success the instance has its values populated by the found object.
// Callback parameters: 1) error, 2) if error is null, a boolean indicating if the object could be found. It is an error for more than one object to be found in a query using the instance values.
PSFileIndex.prototype.lookup = function (callback) {
    Common.lookup(this, this, props, collectionName, callback);
}

// Parameters: fileId is optional. If you give a fileId, it is not an error for the PSFileIndex object to not exist.
// Callback parameters: 1) error, 2) if error not null, an array of PSFileIndex objects describing the file index for this userId (and, optionally, the fileId).
PSFileIndex.getAllFor = function (userId, fileId, callback) {
    if (typeof userId === 'string') {
        try {
            userId = new ObjectID.createFromHexString(userId);
        } catch (error) {
            callback(error, null);
            return;
        }
    }

    var query = {
        userId: userId
    };
    
    if (typeof fileId === 'function') {
        callback = fileId;
        fileId = null;
    }
    else {
        query.fileId = fileId;
    }
    
    logger.debug("getAllFor: query: %j", query);

	var cursor = Mongo.db().collection(collectionName).find(query);
		
	if (!cursor) {
		callback("Failed on find!");
		return;
	}

    var result = [];
    
    cursor.each(function(err, doc) {
        if (err) {
            callback(err, null);
            return;
        }
        else if (!doc) {
            callback(null, result);
            return;
        }
        
        // make a new PSFileIndex object for the doc
        var fileIndex = new PSFileIndex(doc);
        result.push(fileIndex);
    });
}

// instance methods

// export the class
module.exports = PSFileIndex;

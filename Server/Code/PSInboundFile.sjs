// Persistent Storage to represent an index of file transfers that are "Inbound" -- pending transmission from the users cloud storage system.

'use strict';

var fse = require('fs-extra');

var Mongo = require('./Mongo');
var File = require('./File.sjs')
var logger = require('./Logger');
var Common = require('./Common');
var ServerConstants = require('./ServerConstants');

const collectionName = "InboundFiles";

// These must exactly match those properties given in the data model below.
const props = ["_id", "fileId", "userId", "deviceId", "cloudFileName", "mimeType", "received"];

// Note that same names used across some of the properties in this class and PSFileIndex are important and various dependencies exist.

/* Data model
    {
        // Primary key for this change; assigned by Mongo; I'm letting Mongo assign this and not using the fileId because this collection represents files *across* users and at least conceptually, the namespace of UUID's for each user is distinct.
        _id: (ObjectId),
 
        // Together, these two form a unique key.
		fileId: (String, UUID), // fileId; permanent reference to file, assigned by app
		userId: (String), // reference into PSUserCredentials (i.e., _id from PSUserCredentials)
 
        deviceId: (String, UUID), // identifies a specific mobile device (assigned by app)
        
        // These are added as part of operationStartInboundTransfer in part because they are needed later in the inbound transfer, but also to check the .deleted property of the PSFileIndex fairly early in the file transfer process
        cloudFileName: (String), // Just for convenience
        mimeType: (String), // Just for convenience
 
        received: (Boolean) // Has the file been received from cloud storage?
	}
	
	Details: The entry is removed from this collection immediately after the file has been received from the server. A Lock is held until all entries are removed for the particular userId/deviceId pair. While the lock is held, this userId cannot request uploads or downloads.
*/

// Constructor
/* fileData should be a JSON object with all of the properties in the data model above, with the following exceptions:
    For a PSInboundFile object that doesn't exist yet in persistent storage, don't supply the _id key in the fileData.
*/
// Throws an exception in the case of an error.
function PSInboundFile(fileData) {
    var self = this;
    
    if (!isDefined(fileData.received)) {
        fileData.received = false;
    }

    Common.assignPropsTo(self, fileData, props);
}

// instance methods

// Save a new object in persistent storage based on the member variables of this instance.
// Callback has one parameter: error.
PSInboundFile.prototype.storeNew = function (callback) {
    var self = this;

    var copy = {};
    
    try {
        Common.assignPropsTo(copy, self, props);
    } catch (error) {
        callback(error);
    }
    
    // We should not allow multiple entries in the collection of inbound file changes for the the same userId/fileId/deviceId. That is, why should an app be putting in a request for two downloads for the same file?
    Common.lookup(copy, props, collectionName, function (error, objectFound) {
        if (error) {
            callback(error);
        }
        else if (objectFound) {
            callback(new Error("storeNew: Found existing instance!"));
        } else {
            Common.storeNew(self, collectionName, props, callback);
        }
    });
}

// Looks up a PSInboundFile object based on the instance values. On success the instance has its values populated by the found object.
// Callback parameters: 1) error, 2) if error is null, a boolean indicating if the object could be found. It is an error for more than one object to be found in a query using the instance values.
PSInboundFile.prototype.lookup = function (callback) {
    Common.lookup(this, props, collectionName, callback);
}

// Callback parameters: 1) error, 2) if error not null, an array of PSInboundFile objects describing the inbound files pending for this userId/deviceId. This array is zero length if no PSInboundFile objects were found.
PSInboundFile.getAllFor = function (userId, deviceId, callback) {
    var query = {
        userId: userId,
        deviceId: deviceId
    };
	
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
        
        // make a new PSInboundFile for the doc
        var inboundFile = new PSInboundFile(doc);
        result.push(inboundFile);
    });
}

// Update persistent store from self.
// Callback has one parameter: error.
PSInboundFile.prototype.update = function (callback) {
    var self = this;

    Common.update(self, collectionName, props, function (error) {
        callback(error);
    });
}

// Remove the PSInboundFile object from MongoDb.
// If the deletion of the PSInboundFile object fails, the local file system file doesn't get deleted.
// Callback parameter: error
PSInboundFile.prototype.remove = function (callback) {
    var self = this;
    
    // Overkill on overqualifying the query, but why not?
    var query = Common.extractPropsFrom(self, props);

    Mongo.db().collection(collectionName).deleteOne(query,
        function(err, results) {
            // console.log(results);
            
            if (err) {
                callback(err);
            }
            else if (0 == results.deletedCount) {
                callback(new Error("Could not delete remove PSInboundFile!"));
            }
            else if (results.deletedCount > 1) {
                callback(new Error("Yikes! Removed more than one PSInboundFile!"));
            }
            else {
                // TODO: Make sure this doesn't fail if the file isn't there already. This should help in error recovery.
                var localFile = new File(self.userId, self.deviceId, self.fileId);
                var localFileNameWithPath = localFile.localFileNameWithPath();

                fse.remove(localFileNameWithPath, function (err) {
                    callback(err);
                });
            }
        });
}

// export the class
module.exports = PSInboundFile;

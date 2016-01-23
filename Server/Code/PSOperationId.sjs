// Persistent Storage to represent identifiers for asynchronous cloud storage transfer operations, so an app/client can poll after a successful commit to determine the operation state.

'use strict';

var ObjectID = require('mongodb').ObjectID;

var Mongo = require('./Mongo');
var logger = require('./Logger');
var Common = require('./Common');
var ServerConstants = require('./ServerConstants');

const collectionName = "OperationIds";

// These must match those properties given in the data model below.
const props = ["_id", "startDate", "operationType", "operationCount", "operationStatus", "error"];

// TODO: This data model needs to have at least a userId to add some confirmation/error checking for operationCheckOperationStatus. Right now any user can access any operationId.

/* Data model
	{
        _id: (ObjectId), // key for this operation identifier; assigned by Mongo.
        startDate: (Date/time), // date/time that the operation started
 
        // For error checking and integrity -- to ensure the REST/API is being used as it should be. A given operation id can only be used for Outbound or Inbound operations not for both.
        operationType: (String), // Outbound (after upload) or Inbound (before download).
 
        // Initialized to 0. Incremented immediately *prior* to attempting each cloud storage file operation. e.g., immediately before a transfer of a file to the server occurs this is incremented. In normal operation, this will end up being the number of entries/documents originally placed into the PSOutboundFileChange collection. If operationStatus indicates an error (i.e., the overall operation failed), and operationCount is 0, then no change was made to cloud storage.
        operationCount: (Integer),
 
        // Current overall status of this operation.
        operationStatus: (Integer), // See constants in ServerConstants.
 
        error: (String), // if operationStatus is operationStatusFailed, has text describing the error.
	}
*/

// Constructor
// You can leave the idData null, and suitable defaults will be provided.
// if idData._id is provided and given as a string, it will be converted to an ObjectID.
// Errors: Can throw an Error object.
function PSOperationId(idData) {
    var self = this;

    if (isDefined(idData)) {
        if (isDefined(idData._id) && typeof idData._id === 'string') {
            // This can throw an error; let the caller of PSOperationId catch it.
            idData._id = new ObjectID.createFromHexString(idData._id);
        }
    
        Common.assignPropsTo(self, idData, props);
    }
    
    if (!isDefined(self.startDate)) {
        self.startDate = new Date();
    }
    
    if (!isDefined(self.operationCount)) {
        self.operationCount = 0;
    }
    
    if (!isDefined(self.operationStatus)) {
        self.operationStatus = ServerConstants.rcOperationStatusNotStarted;
    }
}

// You must have defined the operationType property.
// Callback has one parameter: error.
PSOperationId.prototype.storeNew = function (callback) {
    var self = this;
    
    if (!isDefined(self.operationType)) {
        callback(new Error("operationType was not given in PSOperationId"))
        return;
    }
    else if (self.operationType != "Outbound" && self.operationType != "Inbound") {
        callback(new Error("operationType was not Outbound or Inbound"))
        return;
    }
    
    Common.storeNew(self, collectionName, props, callback);
}

// Update persistent store from self. If you don't give an error property, it will be set to null.
// Callback is optional and if given has one parameter: error.
PSOperationId.prototype.update = function (callback) {
    var self = this;
    
    var query = {
        _id: self._id
    };
    
    // Make a clone so that I can remove the _id; don't want to update the _id.
    // Not this though. Bad puppy!!
    // var newIdData = JSON.parse(JSON.stringify(self.idData));
    
    var newIdData = Common.extractPropsFrom(self, props);
    delete newIdData._id;
    
    var updates = {
        $set: newIdData
    };
    
    if (!isDefined(self.error)) {
       updates.$unset = { "error": ""}
    }
    
    logger.debug("updates: %j", updates);

    Mongo.db().collection(collectionName).updateOne(query, updates,
        function(err, results) {
            if (isDefined(callback)) {
                callback(err);
            }
        });
}

// Return a PSOperationId object from PS based on the given operationId. The operationId given can be of ObjectId type, or of string type. If of string type, it will be converted to an ObjectId.
// It is considered an error to not find the given operationId in the collection.
// Callback: two parameters: 1) error, and 2) the PSOperationId object if no error.
PSOperationId.getFor = function(operationId, callback) {
    if (typeof operationId === 'string') {
        try {
            operationId = new ObjectID.createFromHexString(operationId);
        } catch (error) {
            callback(error);
            return;
        }
    }
    // Else, we'll try searching for it assuming it's an ObjectId
    
    var query = {
        _id: operationId
    };
    
	var cursor = Mongo.db().collection(collectionName).find(query);
		
	if (!cursor) {
		callback(new Error("Failed on find!"));
		return;
	}

	cursor.count(function (err, count) {
		logger.debug("cursor.count: " + count);
		
		if (err) {
            logger.error(err);
			callback(err, null);
		}
		else if (count > 1) {
			callback(new Error("More than one PSOperationId with: " + operationId), null);
		}
		else if (0 == count) {
			callback(new Error("No PSOperationId with: " + operationId), null);
		}
		else {
			// Just one operation id matched. We need to get it.
			cursor.nextObject(function (err, doc) {
				if (err) {
					callback(err, null);
				}
                else {
                    // TODO: PSOperationId can throw an error.
                    callback(null, new PSOperationId(doc));
                }
			});
		}
	});
}

// Callback has one parameter: error.
PSOperationId.prototype.remove = function (callback) {
    var self = this;
    Common.remove(self, collectionName, callback);
}

// instance methods

// export the class
module.exports = PSOperationId;

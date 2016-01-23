// Persistent Storage to represent a log for the FileTransfers class to assist error recovery.

'use strict';

var ObjectID = require('mongodb').ObjectID;

var Mongo = require('./Mongo');
var logger = require('./Logger');
var Common = require('./Common');
var ServerConstants = require('./ServerConstants');
var PSFileIndex = require('./PSFileIndex');
var PSOutboundFileChange = require('./PSOutboundFileChange');

const collectionName = "FileTransferLog";

// These must match those properties given in the data model below.
const props = ["_id", "fileIndex", "outboundFileChange"];

/* Data model
	{
        // Primary key for this log entry; assigned by Mongo.
        _id: (ObjectId),
        
        fileIndex: (Properties from a PSFileIndex object, but no _id),
        
        outboundFileChange: (Properties from a PSOutboundFileChange object),
	}
*/

// Constructor
// properties in fileData must be from props.
// Can throw error.
function PSFileTransferLog(objData) {
    var self = this;
    
    Common.assignPropsTo(self, objData, props);
}

// Returns the PSFileIndex object created by reconstituting the fileIndex property. Returns null if PSFileIndex object cannot be constructed.
PSFileTransferLog.prototype.getFileIndex = function () {
    var self = this;
    
    var psFileIndex = null;
    
    try {
        psFileIndex = new PSFileIndex(self.fileIndex);
    } catch (error) {
        logger.error("Error attempting to create PSFileIndex object: " + error);
    }
    
    return psFileIndex;
}

// Returns the PSOutboundFileChange object created by reconstituting the outboundFileChange property. Returns null if PSOutboundFileChange object cannot be constructed.
PSFileTransferLog.prototype.getOutboundFileChange = function () {
    var self = this;
    
    var outboundFileChange = null;
    
    try {
        outboundFileChange = new PSOutboundFileChange(self.outboundFileChange);
    } catch (error) {
        logger.error("Error attempting to create PSOutboundFileChange object: " + error);
    }
    
    return outboundFileChange;
}

// Save a new object in persistent storage based on the member variables of this instance.
// Callback has one parameter: error.
PSFileTransferLog.prototype.storeNew = function (callback) {
    var self = this;
    Common.storeNew(self, collectionName, props, callback);
}

// Remove the instance.
// Callback has one parameter: error.
PSFileTransferLog.prototype.remove = function (callback) {
    var self = this;
    Common.remove(self, collectionName, callback);
}

// Get the set of log entries for this userId. It is assumed that you have a lock prior to calling this.
// userId can be given as a string or ObjectID, but is used internally as an ObjectID.
// Callback has two parameters: 1) error, 2) if error is null, a (possibly zero length) array of PSFileTransferLog objects.
PSFileTransferLog.getAllFor = function (userId, callback) {
    if (typeof userId === 'string') {
        try {
            userId = new ObjectID.createFromHexString(userId);
        } catch (error) {
            callback(error);
            return;
        }
    }
    
    var query = {
        'fileIndex.userId': userId
    };
	
	var cursor = Mongo.db().collection(collectionName).find(query);
		
	if (!cursor) {
		callback(new Error("Failed on find!"));
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
        
        // make a new PSFileTransferLog for the doc
        var fileTransferLogObj = new PSFileTransferLog(doc);
        result.push(fileTransferLogObj);
    });
}

// export the class
module.exports = PSFileTransferLog;

/* Example: 

PSFileTransferLog
{
	"_id" : ObjectId("568f501a439c6dfa83ce770c"),
	"fileIndex" : {
		"fileId" : "DF27924C-34DB-4765-8B2C-822D62BC0CAA",
		"userId" : ObjectId("565be13f2917086977fe6f54"),
		"cloudFileName" : "file0",
		"mimeType" : "text/plain",
		"deleted" : false,
		"fileVersion" : "1",
		"appFileType" : null,
		"fileSizeBytes" : "11"
	},
	"outboundFileChange" : {
		"_id" : ObjectId("568f5018439c6dfa83ce770b"),
		"fileId" : "DF27924C-34DB-4765-8B2C-822D62BC0CAA",
		"userId" : ObjectId("565be13f2917086977fe6f54"),
		"deviceId" : "DE63BA86-0121-43FF-BAA7-79BBBBFF5D74",
		"toDelete" : false,
		"cloudFileName" : "file0",
		"mimeType" : "text/plain",
		"fileVersion" : "1",
		"committed" : true
	}
}
*/

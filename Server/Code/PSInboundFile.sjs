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
const props = ["_id", "fileId", "userId", "deviceId", "cloudFileName", "mimeType", "appFileType", "fileVersion", "committed"];

// Note that same names used across some of the properties in this class and PSFileIndex are important and various dependencies exist.

/* Data model
    {
        // Primary key for this change; assigned by Mongo; I'm letting Mongo assign this and not using the fileId because this collection represents files *across* users and at least conceptually, the namespace of UUID's for each user is distinct.
        _id: (ObjectId),
 
        // Together, these two form a unique key.
		fileId: (String, UUID), // fileId; permanent reference to file, assigned by app
		userId: (String), // reference into PSUserCredentials (i.e., _id from PSUserCredentials)
 
        deviceId: (String, UUID), // identifies a specific mobile device (assigned by app)
 
        cloudFileName: (String), // name of the file in cloud storage excluding the folder path.
 
        mimeType: (String), // MIME type of the file
        appFileType: (String), // App-specific file type
        
		fileVersion: (Integer value), // values must be >= 0.
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

    Common.assignPropsTo(self, fileData, props);

    if (isDefined(self.fileVersion) && self.fileVersion < 0) {
        throw new Error("fileVersion < 0: " + self.fileVersion);
    }
}

// export the class
module.exports = PSInboundFile;

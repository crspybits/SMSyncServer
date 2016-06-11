// Persistent Storage for Sharing Users; stored using MongoDb
// These users do not own the cloud storage accounts, rather they have been allowed shared access to those cloud storage accounts.
// (I tried using Mongoose for this but it doesn't seem to allow a variant record structure).

'use strict';

var logger = require('./Logger');
var Mongo = require('./Mongo');

const collectionName = "SharingUsers";

// These must exactly match those properties given in the data model below.
const props = ["_id", "username", "account", "shared"];

/* Data model
	{
		_id: (ObjectId), // userId: unique to the user (assigned by MongoDb).
		username: (String), // account name
        
        // Account that identifies the sharing user.
		account: {
			type: "Facebook" | "Google",
            // Value of creds dependent on type
            
             // For Facebook
			creds: {
                userId: String
			}
        },
 
        // The "Owning User" accounts that are shared.
        // Array of structures because a given sharing user can potentially share more than one set of cloud storage data.
        shared: [
            { 
                owningUser: ObjectId, // The _id of a PSUserCredentials object.
                capabilities: [String] // Each string should be the description representation of a UserCapabilityMask item (see iOS client) -- e.g., Create or Read
            }
        ]
	}
*/

// Constructor
// sharingUser should be a JSON object with the properties of the document as in the model above.
// Doesn't access MongoDb.
// Throws an erorr if userCreds are invalid.
function PSSharingUsers(sharingUser) {
    var self = this;
    Common.assignPropsTo(self, sharingUser, props);
}

// Save a new object in persistent storage based on the member variables of this instance.
// (optional) mustBeNew parameter: if true, then there must be no account with these same creds already. Default is false if not given.
// Callback has one parameter: error.
PSSharingUsers.prototype.save = function (mustBeNew, callback) {
    var self = this;
    
    if (typeof mustBeNew === 'function') {
        callback = mustBeNew;
        mustBeNew = false;
    }
    
    if (mustBeNew) {
        var query = {};
        query.account = self.account;
    
        Common.lookup(query, props, collectionName, function (error, objectFound) {
            if (error) {
                callback(error);
            }
            else if (objectFound) {
                callback(new Error("save: Found existing instance!"));
            } else {
                Common.storeNew(self, collectionName, props, callback);
            }
        });
    }
    else {
        var updates = {};
        
        try {
            Common.assignPropsTo(updates, self, props);
        } catch (error) {
            callback(error);
        }
        
        delete updates._id;
    
        var query = {_id: self._id};
        
        Mongo.db().collection(collectionName).updateOne(query, {$set: updates},
            function(err, results) {
                callback(err);
            });
    }
}
// Persistent Storage for User Credentials; stored using MongoDb
/* These are for both:
    a) OwningUser's -- users that directly own the cloud storage accounts, and
    b) SharingUser's -- users that do not own the cloud storage accounts, rather they have been allowed shared access to those cloud storage accounts.
*/
'use strict';

var UserCredentials = require('./UserCredentials.sjs');
var Mongo = require('./Mongo');
var jsonExtras = require('./JSON');
var logger = require('./Logger');
var ServerConstants = require('./ServerConstants');

const collectionName = "UserCredentials";

/* Data model v2 (with both OwningUser's and SharingUser's)
	{
		_id: (ObjectId), // userId: unique to the user (assigned by MongoDb).
 
		username: (String), // account name, e.g., email address.
        
        userType: "OwningUser" | "SharingUser",
        
        accountType: // Value as follows

        // If userType is "OwningUser", then the following options are available for accountType
        accountType: "Google",

         // If userType is "SharingUser", then the following options are available for accountType
        accountType: "Facebook",

        creds: // Value as follows

        // If userType is "OwningUser" and accountType is "Google"
        creds: {
            sub: XXXX, // Google individual identifier
            access_token: XXXX,
            refresh_token: XXXX
        }
        
        // If userType is "SharingUser" and accountType is "Facebook"
        creds: {
            userId: String,
            
            // This is the last validated access token. It's stored so I don't have to do validation by going to Facebook's servers (see also https://stackoverflow.com/questions/37822004/facebook-server-side-access-token-validation-can-it-be-done-locally) 
            accessToken: String
        }
        
        // SharingUser's have another field in this structure:

        // The linked or shared "Owning User" accounts.
        // Array of structures because a given sharing user can potentially share more than one set of cloud storage data.
        linked: [
            { 
                // The _id of a PSUserCredentials object that must be an OwningUser
                owningUser: ObjectId,
                
                // Each string is the description representation of a UserCapabilityMask item (see iOS client) -- e.g., Create or Read
                capabilities: [String]
            }
        ]
	}
*/

/* Data model v1 (without SharingUser's).
	{
		_id: (ObjectId), // userId: unique to the user (assigned by MongoDb).
		username: (String), // account name on app (e.g., Petunia username)
		cloud_storage:
			{cloud_type: "Google" | "Dropbox",
			cloud_creds: // value dependent on cloud_type
				{"sub" : XXXX, // Google individual identifier
				"access_token" : XXXX,
				"refresh_token" : XXXX}
			}
	}
*/

// Constructor
// userCreds is of type UserCredentials; keeps a reference to this object, so that if the user creds changes, the PSUserCredentials object can access that change.
// Doesn't access MongoDb.
// Throws an error if userCreds are invalid.
function PSUserCredentials(userCreds) {
    var self = this;
    
    // always initialize all instance properties
    
    self._id = null;
    self.username = null;
    self.userType = null;
    self.accountType = null;
    self.creds = null;
    self.linked = null;
    
    // the UserCredentials object.
    self.userCreds = userCreds;
    
    // logger.debug("self.userCreds: " + JSON.stringify(self.userCreds));
	
	// Is this in persistent storage? (We don't know yet).
	self.stored = null;
}

// instance methods

// Only use the invariant parts of the cloud storage as these form the unique search key. Also should qualify it by account type and user type.
function queryData(signedInCreds) {
    return {
        accountType: signedInCreds.accountType,
        userType: signedInCreds.userType,
        creds: signedInCreds.persistentInvariant()
    };
}

// Lookup the signed-in user creds in persistent storage.
// Callback has a single parameter: error. If the error is null in the callback, check the member property .stored to see if the user creds are stored in persistent storage. The .stored member will be null if there is an error.
PSUserCredentials.prototype.lookup = function (callback) {
    var self = this;
    self.stored = null;
    
    var query = queryData(self.userCreds.signedInCreds());
    
	// find needs this query flattened.
	query = jsonExtras.flatten(query);
	
	logger.debug("flattened query: ");
	logger.debug(query);
	
	var cursor = Mongo.db().collection(collectionName).find(query);
		
	if (!cursor) {
		callback("Failed on find!");
		return;
	}
		
	// See docs https://mongodb.github.io/node-mongodb-native/api-generated/cursor.html#count
	cursor.count(function (err, count) {
		logger.info("cursor.count: " + count);
		
		if (err) {
            logger.error(err);
			callback(err);
		}
		else if (count > 1) {
            // Error case.
			callback("More than one user with those credentials!");
		}
		else if (0 == count) {
            self.stored = false;
			callback(null);
		}
		else {
			// Just one user matched. We need to get it.
			cursor.nextObject(function (err, doc) {
				if (!err) {
					self.stored = true;
					self._id = doc._id;
                    self.username = doc.username;
                    self.userType = doc.userType;
                    self.accountType = doc.accountType;
                    self.creds = doc.creds;
                    self.linked = doc.linked;
				}
                
                callback(err);
			});
		}
	});
		
	// The way the "each" method works is that it will iterate N+1 times, where
	// N is the number of documents returned in the query. In the N+1-th iteration,
	// doc will be null.
	// See https://mongodb.github.io/node-mongodb-native/api-generated/cursor.html#each
}

// Populates the signed in .userCreds member of this object from the .creds member.
// Callback has one parameter: error
PSUserCredentials.prototype.populateFromUserCreds = function (callback) {
    var self = this;
    logger.info("populateFromUserCreds: " + JSON.stringify(self.creds));
    
    function setPersistent() {
        self.userCreds.signedInCreds().setPersistent(self.creds, function (err) {
            callback(err);
        });
    }

    // populateFromUserCreds could be called with or without calling lookup first.
    if (self.creds) {
        logger.info("Populating directly from self.creds");
        setPersistent();
    }
    else {
        logger.info("Doing lookup to populate");
        self.lookup(function (err) {
            if (err) {
                callback(err);
            }
            else {
                setPersistent();
            }
        });
    }
}

// Save a new object in persistent storage based on the member variables of this instance.
// Callback has one parameter: error.
PSUserCredentials.prototype.storeNew = function (callback) {
    var self = this;
    
    var signedInCreds = self.userCreds.signedInCreds();
    
    // Letting Mongo give us the unique _id.
    var userCredentialsDocument = {
    	username: signedInCreds.username,
        userType: signedInCreds.userType,
        accountType: signedInCreds.accountType,
    	creds: signedInCreds.persistent()
    };
    
    if (ServerConstants.userTypeSharing == signedInCreds.userType) {
        userCredentialsDocument.linked = [];
    }
    
    logger.debug("storeNew: " + JSON.stringify(userCredentialsDocument));
    
   	Mongo.db().collection(collectionName).insertOne(userCredentialsDocument,
   		function(err, result) {
   			if (!err) {
   				self._id = result._id;
   			}
   			
    		callback(err);
  		});
}

// Update persistent store from the current userCreds member. No effect if user creds has no (variant) data with which to update persistent store. (This is not considered an error).
// Parameter: saveAll (boolean, optional, default: false)-- if true, will save all fields to PS.
// Callback has one parameter: error.
// TODO: Need to add a parameter so that other info from the instance can get written back to PS. Need this particularly for updating links field.
PSUserCredentials.prototype.update = function (saveAll, callback) {
    var self = this;

    if (typeof saveAll === 'function') {
        callback = saveAll;
        saveAll = false;
    }
    
    // Anything to update?
    var variantData = self.userCreds.signedInCreds().persistentVariant();
    if (!variantData && !saveAll) {
        callback(null);
        return;
    }
    
    // logger.info("variantData: " + JSON.stringify(variantData));
    
    var query = queryData(self.userCreds.signedInCreds());
	// I'm guessing that since find needs this query flattened, so does updateOne.
	query = jsonExtras.flatten(query);
    
    var updates = {};

    // Create the update data
    if (saveAll) {
        var signedInCreds = self.userCreds.signedInCreds();
        
        updates.username = signedInCreds.username;
        updates.userType = signedInCreds.userType;
        updates.accountType = signedInCreds.accountType;
        updates.creds =  signedInCreds.persistent();
        
        if (isDefined(self.linked)) {
            updates.linked = self.linked;
        }
    }
    else {
        // I'm not quite sure why this is so complex. It works though.
        var variantCreds = { creds : variantData };
        variantCreds = jsonExtras.flatten(variantCreds);
        var numberOfUpdates = 0;
        
        for (var key in variantCreds) {
            if (variantCreds.hasOwnProperty(key)) {
                numberOfUpdates++;
                updates[key] = variantCreds[key];
            }
        }
        
        if (0 == numberOfUpdates) {
            callback(null);
            return;
        }
    }
    
    // logger.debug("Updates: " + JSON.stringify(updates));
    // logger.debug("Number of keys in updates: " + Object.keys(updates).length);
    
    Mongo.db().collection(collectionName).updateOne(query, {$set: updates},
    function(err, results) {
        // logger.debug(results);
        callback(err);
    });
}

// export the class
module.exports = PSUserCredentials;
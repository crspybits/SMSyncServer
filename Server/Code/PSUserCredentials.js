// Persistent Storage for User Credentials; stored using MongoDb
// These are "Owning Users" -- i.e., users that directly own the cloud storage accounts.

'use strict';

var UserCredentials = require('./UserCredentials.sjs');
var Mongo = require('./Mongo');
var jsonExtras = require('./JSON');
var logger = require('./Logger');

const collectionName = "UserCredentials";

/* Data model
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
// Throws an erorr if userCreds are invalid.
function PSUserCredentials(userCreds) {
    // always initialize all instance properties
    
    // these three will be taken from persistent storage.
    this._id = null;
    this.username = null;
    this.cloud_storage = null;
    
    this.userCreds = userCreds;
    
	if (!this.userCreds.persistent()) {
		throw "**** ERROR ****: Null user creds cloud_storage";
	}
	
	// Is this in persistent storage? (We don't know yet).
	this.stored = null;
}

// instance methods

// Lookup the user creds in persistent storage.
// Callback has a single parameter: error. If the error is null in the callback, check the member property .stored to see if the user creds are stored in persistent storage. The .stored member will be null if there is an error.
PSUserCredentials.prototype.lookup = function (callback) {
    var self = this;
    self.stored = null;
    
    // Only use the invariant parts of the cloud storage as these form the unique search key.
    var query = { cloud_storage: self.userCreds.persistentInvariant() };
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
                    self.cloud_storage = doc.cloud_storage;
				}
                
                //console.log(err);
                //console.log(doc);
                //console.log(self.cloud_storage);
                
                callback(err);
			});
		}
	});
		
	// The way the "each" method works is that it will iterate N+1 times, where
	// N is the number of documents returned in the query. In the N+1-th iteration,
	// doc will be null.
	// See https://mongodb.github.io/node-mongodb-native/api-generated/cursor.html#each
}

// Populates the .userCreds member of this object from the .cloud_storage member.
// Callback has one parameter: error
PSUserCredentials.prototype.populateFromUserCreds = function (callback) {
    var self = this;
    logger.info("populateFromUserCreds: " + JSON.stringify(self.cloud_storage));
    
    function setPersistent() {
        self.userCreds.setPersistent(self.cloud_storage, function (err) {
            callback(err);
        });
    }

    // populateFromUserCreds could be called with or without calling lookup first.
    if (self.cloud_storage) {
        logger.info("Populating directly from self.cloud_storage");
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
    
    // Letting Mongo give us the unique _id.
    var userCredentialsDocument = {
    	username: self.userCreds.username,
    	cloud_storage: self.userCreds.persistent()
    };
    
   	Mongo.db().collection(collectionName).insertOne(userCredentialsDocument,
   		function(err, result) {
   			if (!err) {
   				self._id = result._id;
   			}
   			
    		callback(err);
  		});
}

// Update persistent store from the current userCreds member. No effect if user creds has no (variant) data with which to update persistent store. (This is not considered an error).
// Callback has one parameter: error.
PSUserCredentials.prototype.update = function (callback) {
    var self = this;
    
    // Anything to update?
    var variantData = this.userCreds.persistentVariant();
    if (!variantData) {
        callback(null);
        return;
    }
    
    // logger.info("variantData: " + JSON.stringify(variantData));
    
    var query = { cloud_storage : self.userCreds.persistentInvariant() };
	// I'm guessing that since find needs this query flattened, so does updateOne.
	query = jsonExtras.flatten(query);
    
    // Create the update data
    var variantCloudStorage = { cloud_storage : variantData };
    variantCloudStorage = jsonExtras.flatten(variantCloudStorage);
    var updates = {};
    var numberOfUpdates = 0;
    
    for (var key in variantCloudStorage) {
        if (variantCloudStorage.hasOwnProperty(key)) {
            numberOfUpdates++;
            updates[key] = variantCloudStorage[key];
        }
    }
    
    // logger.debug("Updates: " + JSON.stringify(updates));
    // logger.debug("Number of keys in updates: " + Object.keys(updates).length);
    
    if (0 == numberOfUpdates) {
        callback(null);
    }
    else {
        Mongo.db().collection(collectionName).updateOne(query, {$set: updates},
        function(err, results) {
            // logger.debug(results);
            callback(err);
        });
    }
}

// export the class
module.exports = PSUserCredentials;

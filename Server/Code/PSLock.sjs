// Persistent Storage to represent a set of locks.

'use strict';

var Mongo = require('./Mongo');
var logger = require('./Logger');
var Common = require('./Common');

const collectionName = "Locks";

// These must match those properties given in the data model below.
const props = ["_id", "operationId", "deviceId", "lockStart", "lastLockActivity"];

/* Data model
	{
        // userId; reference into PSUserCredentials. The lock is held across all deviceId's used by this userId. I.e., this locks the cloud storage referrred to by this userId.
		_id: (ObjectId),
        
        // Refers to _id in PSOperationId. We keep this reference here, in the Locks  collection because we need to be able to update the operation id status when the operation is done. Also, the lock is providing an exclusive means to execute the operation. We don't just return the _id for the lock to the client app as a means of tracking the operation, because of the eventuality needing to break the lock. (Which will mean removing the entry from this lock collection).
        operationId: (ObjectId),
 
        // While the lock prevents other deviceId's for the same userId from accessing the cloud storage referred to by the userId, the lock is held by one specific deviceId.
		deviceId: (UUID),
 
		lockStart: (Date),
        lastLockActivity: (Date)
	}
	
	Details: These are mutex locks and are used by devices for purposes of atomically uploading files from a device to the sync server, downloading files from the sync server to a device, and for transferring files between the sync server and  cloud storage.
	userId's are used for the _id (primary key) to ensure that one user can only hold one lock at a time across a number of devices making use of that same userId (i.e., making use of that same cloud storage).
	These locks expire (and will be removed from the Lock collection) at a particular time interval after lastLockActivity *and* when there is contention from another user with the same userId.
    The MVP will not have lock breaking.
*/

// Constructor
// The operationId is optional in the lockData -- E.g., if the lock you are holding is temporary, within the duration of one SyncServer API call, you don't need it.
// Erorrs: Can throw an Error object (in Common.assignPropsTo)
function PSLock(lockData) {
    var self = this;
    Common.assignPropsTo(self, lockData, props);
}

// instance methods

// Attempt to get the lock for this userId. Do this by attempting to create a new document with the userId as the primary key. If this succeeds, it must be the only doc with this userId. If it fails, there is a boolean (see below) which indicates if the failure was because the lock was already held by this userId.
/* Callback has parameters: 
    1) error, 
    2) a boolean which if error non-null, and the error was that the lock was already present, will be true.
*/
PSLock.prototype.attemptToLock = function (callback) {
    var self = this;
    
    self.lockStart = new Date();
    self.lastLockActivity = self.lockStart;
    
    var docData = {
        _id: self._id,
        deviceId: self.deviceId,
        lockStart: self.lockStart,
        lastLockActivity: self.lastLockActivity
    };
    
    if (isDefined(self.operationId)) {
        docData.operationId = self.operationId;
    }

    // We're getting MongoError: E11000 duplicate key error
    // if we attempt to get a lock and it's already held.
    /* The full error structure is:
    {
        "name": "MongoError",
        "message": "E11000 duplicate key error index: test.Locks.$_id_ dup key: { : ObjectId('565be13f2917086977fe6f54') }",
        "driver": true,
        "index": 0,
        "code": 11000,
        "errmsg": "E11000 duplicate key error index: test.Locks.$_id_ dup key: { : ObjectId('565be13f2917086977fe6f54') }"
    }
    */
    // This is the mechanism by which we assure the atomic all/none nature of the lock. Only one entry  (document) can be present in the collection with the given _id (i.e., with this specific userId). This means that only a single device/app can hold the lock for that userId.
    
    const duplicateKeyError = 11000;
    
    Mongo.db().collection(collectionName).insertOne(docData, function(err, result) {
        if (err) {
            logger.error("attemptToLock: " + err);
            if (duplicateKeyError == err.code) {
                callback(err, true);
            }
            else {
                callback(err, false);
            }
            
            return;
        }
        
        callback(null, null);
    });
}

// Check to see if we (userId) have a lock.
/* Callback has two parameters: 
    1) error, 
    2) if error is null,
        Either null which indicates we didn't have the lock, or
            the PSLock object representing the lock held.
*/
// TODO: When this succeeds, update lastLockActivity with the current date/time.
PSLock.checkForOurLock = function (userId, deviceId, callback) {
    var query = {
        _id: userId
    };
	
	var cursor = Mongo.db().collection(collectionName).find(query);
		
	if (!cursor) {
		callback("Failed on find!", null);
		return;
	}
		
	// See docs https://mongodb.github.io/node-mongodb-native/api-generated/cursor.html#count
	cursor.count(function (err, count) {
		logger.info("cursor.count: " + count);
		
		if (err) {
            logger.error("Error on count: %j", err);
			callback(err, null);
		}
		else if (count > 1) {
            // Should never get here. Put it in just for integrity checking.
			callback("More than one user/device with lock!", null);
		}
		else if (0 == count) {
            // We don't have the lock
			callback(null, null);
		}
        else {
			// Just one user lock! Make sure it was for our device.
			cursor.nextObject(function (err, doc) {
				if (err) {
                    logger.error("Error on nextObject: %j", err);
					callback(err, null);
				}
				else if (!doc) {
                    // 1/6/16; This test is here because I believe I got a failure on this today.
                    var msg = "Don't have doc on nextObject";
                    logger.error(msg);
					callback(msg, null);
				}
                else if (deviceId == doc.deviceId) {
                    // We have the lock.
                    callback(null, new PSLock(doc));
                }
                else {
                    callback("User held lock, but not our device!", null);
                }
			});
		}
	});
}

// Checks to make sure we have the lock before attempting to remove.
// Callback: Error parameter.
PSLock.prototype.removeLock = function (callback) {
    var self = this;
    
    PSLock.checkForOurLock(self._id, self.deviceId, function (error, psLock) {
        if (error) {
            logger.error("Error when calling checkForOurLock");
            callback(error);
        }
        else if (!psLock) {
            logger.error("Don't have the lock!");
            callback("We don't have the lock! Thus, we can't remove it!");
        }
        else {
            var query = {
                _id: self._id
            };
            
            Mongo.db().collection(collectionName).deleteOne(query, function(err, results) {
                //logger.debug(results);
                
                if (err) {
                    callback(err);
                }
                else if (0 == results.deletedCount) {
                    callback("Could not remove lock!");
                }
                else if (results.deletedCount > 1) {
                    callback("Yikes! We removed more than one lock!");
                }
                else {
                    callback(null);
                }
            });
        }
    });
}

PSLock.prototype.remove = PSLock.prototype.removeLock;

// export the class
module.exports = PSLock;

// Persistent Storage for User Credentials; stored using MongoDb
/* These are for both:
    a) OwningUser's -- users that directly own the cloud storage accounts, and
    b) SharingUser's -- users that do not own the cloud storage accounts, rather they have been allowed shared access to those cloud storage accounts.
*/
'use strict';

var ObjectID = require('mongodb').ObjectID;

var Mongo = require('./Mongo');
var jsonExtras = require('./JSON');
var logger = require('./Logger');
var ServerConstants = require('./ServerConstants');
var GoogleUserCredentials = require('./GoogleUserCredentials');
var FacebookUserCredentials = require('./FacebookUserCredentials');
var Common = require('./Common');

var accountCreationMethods = [GoogleUserCredentials.CreateIfOurs, FacebookUserCredentials.CreateIfOurs];
var emptyCreationMethods = [GoogleUserCredentials.CreateEmptyIfOurs, FacebookUserCredentials.CreateEmptyIfOurs];

const collectionName = "UserCredentials";

// These must exactly match those properties given in the data model below.
const props = ["_id", "username", "userTypes", "accountType", "creds", "linked"];

/* Data model v2 (with both OwningUser's and SharingUser's)
	{
		_id: (ObjectId), // userId: unique to the user (assigned by MongoDb).
 
		username: (String), // account name, e.g., email address.
        
        // The permissible userTypes for these account creds.
        // "OwningUser" and/or "SharingUser" in an array
        userTypes: [],
 
        accountType: // Value as follows

        // If userTypes includes "OwningUser", then the following options are available for accountType
        accountType: "Google",

         // If userTypes includes "SharingUser", then the following options are available for accountType
        accountType: "Facebook",

        creds: // Value as follows

        // If accountType is "Google"
        creds: {
            sub: XXXX, // Google individual identifier
            access_token: XXXX,
            refresh_token: XXXX
        }
        
        // If accountType is "Facebook"
        creds: {
            userId: String,
            
            // This is the last validated access token. It's stored so I don't have to do validation by going to Facebook's servers (see also https://stackoverflow.com/questions/37822004/facebook-server-side-access-token-validation-can-it-be-done-locally) 
            accessToken: String
        }
        
        // Users with SharingUser in their userTypes have another field in this structure:

        // The linked or shared "Owning User" accounts.
        // Array of structures because a given sharing user can potentially share more than one set of cloud storage data.
        linked: [
            { 
                // The _id of a PSUserCredentials object that must be an OwningUser
                owningUser: ObjectId,
            
                // See ServerConstants.sharingType
                sharingType: String
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

/* Constructor
    Parameters: credentialsData (optional)
        If given, throws an error if credentialsData don't have insufficient info.
        credentialsData is from serverConstants userCredentialsDataKey

    Doesn't access MongoDb.
*/
function PSUserCredentials(credentialsData) {
    var self = this;
    
    // The data for each instance comes in two parts:
    
    // 1) Data that is NOT contained in Mongo.
    
	self.stored = null; // Is the data from this instance in persistent storage? (We don't know yet).

    if (isDefined(credentialsData)) {
        // For sharing users only-- the currently selected owning userId.
        self.linkedOwningUserId = credentialsData[ServerConstants.linkedOwningUserId];
        
        // Also for sharing users. The UserCredentials specific object for self.linkedOwningUserId, if defined.
        self.linkedOwningUserSpecificCreds = null;
        
        // sharingType that the sharing user has on the linkedOwningUserSpecificCreds.
        self.sharingType = null;
        
        // This is not saved into PSUserCredentials -- there may be several of these across users of the owning user account. i.e., several devices across which the data is being shared.
        self.mobileDeviceUUID = credentialsData[ServerConstants.mobileDeviceUUIDKey];
        if (!isDefined(self.mobileDeviceUUID)) {
            throw new Error("No mobileDeviceUUID in credentials data!");
        }
        
        // Also not saved persistently. But should it be??
        self.cloudFolderPath = credentialsData[ServerConstants.cloudFolderPath];
        if (!isDefined(self.cloudFolderPath)) {
            throw new Error("No cloudFolderPath in credentials data!");
        }
    
    // 2) Data that IS contained in Mongo.
    
        // Optional
        self.username = credentialsData[ServerConstants.accountUserName];
        
        self.userType = credentialsData[ServerConstants.userType];
        if (!isDefined(self.userType)) {
            throw new Error("No userType in credentials data!");
        }

        self.accountType = credentialsData[ServerConstants.accountType];
        if (!isDefined(self.accountType)) {
            throw new Error("No accountType in credentials data!");
        }
        
        if (isDefined(self.linkedOwningUserId) && self.userType != ServerConstants.userTypeSharing) {
            logger.debug("credentialsData: " + JSON.stringify(credentialsData));
            throw new Error("Have linkedOwningUserId, but don't have sharing user: " + self.userType);
        }
        
        self.creds = null;
        self.linked = [];
        
        // The specific creds info (UserCredentials subclass instance) that follows is stored in Mongo, but each object provides its own methods for massaging that data so it can be stored.
        self.specificCreds = null;
        
        // Assume each of the factory methods knows when it should create its creds. Stop at the first one that works.
        for (var methodIndex in accountCreationMethods) {
            var factoryMethod = accountCreationMethods[methodIndex];
            
            // These factory constructors can throw.
            self.specificCreds = factoryMethod(credentialsData);
            if (self.specificCreds) {
                break;
            }
        }
        
        if (!self.specificCreds) {
            throw new Error("Couldn't create specific account creds!");
        }
        
        // We're going to put off populating self.linkedOwningUserSpecificCreds until the PSUserCredentials object is actually fetched from Mongo.
    }
}

// instance methods

// The specific UserCredentials subclass must support this userType.
PSUserCredentials.prototype.initEmptySpecificCreds = function(userType) {
    var self = this;
    
    // Assume each of the factory methods knows when it should create its creds. Stop at the first one that works.
    for (var methodIndex in emptyCreationMethods) {
        var factoryMethod = emptyCreationMethods[methodIndex];
        
        // Not using self.userType here because that is not defined; self.userTypes is defined, and it's an array.
        self.specificCreds = factoryMethod(userType, self.accountType);
        if (self.specificCreds) {
            break;
        }
    }
    
    if (!self.specificCreds) {
        throw new Error("Couldn't create specific account creds: userType: " + userType + "; accountType: " + self.accountType);
    }
}

// The user creds that were actually sent via the REST call parameters.
// The object returned is a specific UserCredentials object.
PSUserCredentials.prototype.signedInCreds = function () {
    var self = this;
    return self.specificCreds;
}

// For owning users returns self.specificCreds. For sharing users, returns self.linkedOwningUserSpecificCreds if non-null. Throws an error otherwise.
PSUserCredentials.prototype.cloudStorageCreds = function (callback) {
    var self = this;
    
    if (self.owningUserSignedIn()) {
        callback(null, self.specificCreds);
    }
    else if (isDefined(self.self.linkedOwningUserSpecificCreds)) {
        return self.linkedOwningUserSpecificCreds;
    }
    else {
        throw new Error("Cannot obtain cloudStorageCreds");
    }
}

// Initializes self.linkedOwningUserSpecificCreds by looking up self.linkedOwningUserId in the .linked property. If self.linkedOwningUserId is null, just fails silently.
// The callback has one parameter: error.
PSUserCredentials.prototype.initLinkedOwningUser = function (callback) {
    var self = this;
    
    if (!isDefined(self.linkedOwningUserId)) {
        logger.info("No linkedOwningUserId!");
        callback(null);
        return;
    }

    logger.info("Have linkedOwningUserId: Looking up.");
    
    // First, make sure that self.linkedOwningUserId refers to one of the linked accounts.
    var found = false;
    for (var linkedIndex in self.linked) {
        var linkedCreds = self.linked[linkedIndex];
        if (self.linkedOwningUserId == linkedCreds.owningUser) {
            self.sharingType = linkedCreds.sharingType;
            found = true;
        }
    }
    
    if (!found) {
        callback(new Error("Cannot find linked userId: " + self.linkedOwningUserId));
        return;
    }
    
    logger.info("About to callPSUserCredentials constructor.");
    
    var psUserCreds = new PSUserCredentials();
    var options = {
        lookupId: self.linkedOwningUserId,
        userType: ServerConstants.userTypeOwning
    };
    
    psUserCreds.lookup(options, function (error) {
        if (error) {
            callback("Failed on lookup for PSUserCredentials: "
                + JSON.stringify(error));
        }
        else if (!isDefined(psUserCreds.specificCreds)) {
            callback("Could not get specific creds for: " + self.linkedOwningUserId);
        }
        else {
            logger.info("self.linkedOwningUserSpecificCreds: " + JSON.stringify(self.linkedOwningUserSpecificCreds));
            self.linkedOwningUserSpecificCreds = psUserCreds.specificCreds;
            callback(null);
        }
    });
}

// Returns true iff an owning user is signed in.
PSUserCredentials.prototype.owningUserSignedIn = function () {
    var self = this;
    return ServerConstants.userTypeOwning == self.userType;
}

// Returns true iff a sharing user is signed in.
PSUserCredentials.prototype.sharingUserSignedIn = function () {
    var self = this;
    return ServerConstants.userTypeSharing == self.userType;
}

// Is the current signed in user authorized to do this operation?
// One parameter: A sharingType (e.g., ServerConstants.sharingAdmin)
// Returns true or false.
PSUserCredentials.prototype.userAuthorizedFor = function (sharingType) {
    var self = this;
    
    if (self.owningUserSignedIn()) {
        return true;
    }
    else {
        switch (self.sharingType) {
        case ServerConstants.sharingAdmin:
            return true;
            
        case ServerConstants.sharingUploader:
            switch (sharingType) {
            case ServerConstants.sharingUploader:
            case ServerConstants.sharingDownloader:
                return true;
                
            default:
                return false;
            }

        case ServerConstants.sharingDownloader:
            switch (sharingType) {
            case ServerConstants.sharingDownloader:
                return true;
                
            default:
                return false;
            }
        
        default:
            logger.error("ERROR: Undefined sharing type: " + self.sharingType);
            return false;
        }
    }
}

/*
Callback has parameters:
    1) error;
    2) if error != null, a boolean, which if true indicates the error was that the user could not be validated because there security information is stale; this parameter is given as null if error is null
*/
PSUserCredentials.prototype.lookupAndValidate = function(callback) {
    var self = this;
    
    // 6/15/16: Identified a problem: I was doing a lookup before having done a validation. For Google creds, this meant we couldn't yet do the lookup because we haven't decrypted the IdToken, which give our "sub" identifier. For Facebook, this was OK since we have a non-encrpyted userId). Solution: I'm now making the decision about whether to do the lookup first (versus the validate first) on the basis of whether the specific creds (FB or Google at this point) gives us a non-null .persistentInvariant() function call value.

    var lookupKeys = self.signedInCreds().persistentInvariant();
    if (lookupKeys) {
        logger.info("We have keys in order to do the lookup.");
        self.lookup(function (error) {
            if (error) {
                callback(error, false);
            }
            else {
                var mongoCreds = null;
                if (self.stored) {
                    mongoCreds = self.creds;
                }

                // The validate call will also make sure what we have in Mongo matches what came in from the app.
                self.signedInCreds().validate(mongoCreds, function(error, staleUserSecurityInfo, credsChangedDuringValidation) {
                    if (error) {
                        callback(error, staleUserSecurityInfo);
                    }
                    else {
                        finishLookupAndValidate(self, credsChangedDuringValidation, callback);
                    }
                });
            }
        });
    }
    else {
        logger.info("We don't have the keys to do the lookup. Validate first.");
        self.signedInCreds().validate(null, function(error, staleUserSecurityInfo, credsChangedDuringValidation) {
            if (error) {
                callback(error, staleUserSecurityInfo);
            }
            else {
                self.lookup(function (error) {
                    if (error) {
                        callback(error, false);
                    }
                    else {
                        // Need to make sure that the validated specific creds match up with what we have in Mongo, if any.
                        if (self.stored) {
                            if (!self.signedInCreds().validateStored(self.creds)) {
                                callback("Creds didn't validate agains those stored in Mongo!", false)
                                return;
                            }
                        }
                        
                        finishLookupAndValidate(self, credsChangedDuringValidation, callback);
                    }
                });
            }
        });
    }
}

function finishLookupAndValidate(self, credsChangedDuringValidation, callback) {
    logger.debug("self.stored: " + self.stored + "; credsChangedDuringValidation: " + credsChangedDuringValidation);
    
    /* For Facebook creds, we get both the userId and accessToken from the app (i.e., all of the specific cred info).
            If the creds are already stored in Mongo, then
                If the creds changed during validation, then 
                    the persistentVariant info (i.e., the access token) will saved with the update.
                    HOWEVER, the info doesn't get copied back to self. We're going to rewrite update to deal with this.
                Else If the creds didn't change during validation, then since they are stored, we're fine.
            Else if the creds are not stored in Mongo, then whomever is calling this will have to do a "storeNew". Will the specific cred info have been transfered to the .creds property? Yes-- this is done by the storeNew method.
     
        For Google creds, we only get part of the creds from the app-- the IdToken. (And some times an auth code).
            If the creds are already stored in Mongo, then
                If the creds changed during validation, then 
                    the persistentVariant info (i.e., the access token) will get saved with the update.
                    DO THEY get copied back to self?
                    NO, they don't. The info gets saved to Mongo, and would be in .creds next time a lookup is done, but it doesn't get stored in self.
                    This is ODD. A better strategy for the update would seem to be to modify the self properties, then copy off the relevant properies and store them in Mongo.
                Else If the creds didn't change during validation, then since they are stored, we're fine.
            Else if the creds are not stored in Mongo, then
        
        1) A better strategy for the update would seem to be to modify the self properties, then copy off the relevant properies and store them in Mongo.
        2) I also want to modify storeNew to have it work in a similar manner to update. To make sure the self properties are fully updated.
        3) Lookup should also modify the specific creds with that info loaded from Mongo.
     
    */
    
    function initLinkedOwningUser(self) {
        self.initLinkedOwningUser(function (error) {
            if (error) {
                logger.error("Error calling initLinkedOwningUser: " + JSON.stringify(error));
                callback(error, false);
            }
            else {
                callback(null, null);
            }
        });
    }
    
    if (self.stored) {
        if (credsChangedDuringValidation) {
            // Update persistent store with user creds data.
            self.update(function (err) {
                if (err) {
                    callback(err, false);
                }
                else {
                    initLinkedOwningUser(self);
                }
            });
        }
        else {
            initLinkedOwningUser(self);
        }
    } 
    else {
        callback(null, null);
    }
}

// Only use the invariant parts of the cloud storage as these form the unique search key. Also should qualify it by account type. Not qualifying by userType because in the future we'd like to be able to have some users able to be both owning and sharing users. E.g., in the future a Google user should be able to be a sharing and an owning user.
function queryData(self) {
    return {
        accountType: self.accountType,
        creds: self.signedInCreds().persistentInvariant()
    };
}

/* Lookup user creds in persistent storage. A .specificCreds object is created (and initialized) after a successful lookup, if there is not one.

    Parameters:
    1) Options: A JSON object with the following keys and values:
        lookupId: string of a PSUserCredentials object: lookup purely by this _id. Can be a string or ObjectId.
        userType: either ServerConstants.userTypeSharing or ServerConstants.userTypeOwning
            If you don't give this, it defaults to ServerConstants.userTypeSharing
            This is used when if a .specificCreds object is created, to determine the userType of that object.
    2) Callback: With a single parameter: error. If the error is null in the callback, check the member property .stored to see if the user creds are stored in persistent storage. The .stored member will be null if there is an error.
*/
PSUserCredentials.prototype.lookup = function (options, callback) {
    var self = this;
    
    //logger.debug("self: " + JSON.stringify(self));
    logger.debug("options: " + JSON.stringify(options));

    self.stored = null;
    var query = null;
    var lookupId = options.lookupId;
    var userType = options.userType;
    
    if (typeof options === 'function') {
        callback = options;
    }
    
    if (isDefined(lookupId)) {
        if (typeof lookupId === 'string') {
            try {
                lookupId = new ObjectID.createFromHexString(lookupId);
            } catch (error) {
                callback(error);
                return;
            }
        }
    
        query = { _id: lookupId };
        
        // logger.debug("constructor");
        // console.log(lookupId.constructor);
    }
    else {
        query = queryData(self);
        // Common.lookup does *not* do flattening of query.
        query = jsonExtras.flatten(query);
    }
    
    if (!isDefined(userType)) {
        userType = ServerConstants.userTypeSharing;
    }
    
    if (!isDefined(query)) {
        throw new Error("query is not defined!")
    }
    
    logger.debug("query: " + JSON.stringify(query) + "; " + lookupId + "; " + typeof lookupId);

    var result = {};
    Common.lookup(query, result, props, collectionName, function (error, objectFound) {
        if (error) {
            callback(error);
        }
        else {
            self.stored = objectFound;
            logger.debug("self: " + JSON.stringify(self));
            
            if (objectFound) {
                Common.assignPropsTo(self, result, props);

                if (!isDefined(self.specificCreds)) {
                    // This will happen when we create a new PSUserCredentials object for the sole purpose of looking up by an id.
                    self.initEmptySpecificCreds(userType);
                }
                
                self.specificCreds.setPersistent(self.creds);
            }
            
            callback(null);
        }
    });
}

// Save a new object in persistent storage based on the member variables of this instance.
// Callback has one parameter: error.
PSUserCredentials.prototype.storeNew = function (callback) {
    var self = this;
    
    // Make sure the .creds have been updated.
    self.creds =  self.specificCreds.persistent();

    Common.storeNew(self, collectionName, props, function (error) {
        if (error) {
            callback(error);
        }
        else {
            self.stored = true;
            callback(error);
        }
    });
}

function updateUserTypes(userTypes, currentUserType) {
    if (userTypes.indexOf(currentUserType) == -1) {
        userTypes.push(currentUserType)
    }
}

// Callback has one parameter: error.
PSUserCredentials.prototype.update = function (callback) {
    var self = this;
    
    // Make sure the .creds have been updated.
    self.creds =  self.specificCreds.persistent();
    
    Common.update(self, collectionName, props, function (error) {
        callback(error);
    });
}

// In format needed by operationGetLinkedAccountsForSharingUser
// Callback has two parameters: 1) error, and 2) the account list if no error.
PSUserCredentials.prototype.makeAccountList = function (callback) {
    var self = this;
    
    logger.debug("makeAccountList");
    
    self.lookup(function (error) {
        if (error) {
            logger.error("Failed on lookup for PSUserCredentials: " + JSON.stringify(error));
            callback(error, null);
        }
        else {
            var result = [];
            makeAccountListAux(self.linked, 0, result, callback)
        }
    });
}

function makeAccountListAux(linkedAccounts, currIndex, currResult, callback) {
    logger.debug("makeAccountListAux: " + currIndex);

    if (currIndex >= linkedAccounts.length) {
        callback(null, currResult);
    }
    else {
        var linkedAccount = linkedAccounts[currIndex];
        
        var resultAccount = {};
        resultAccount[ServerConstants.internalUserId] = linkedAccount.owningUser;
        resultAccount[ServerConstants.accountSharingType] = linkedAccount.sharingType;

        var psUserCreds = null;
        try {
            psUserCreds = new PSUserCredentials();
        } catch (error) {
            callback(error, null);
            return;
        }
        
        // Do a separate lookup for that owningUser to get its username.
        var options = {
            lookupId: linkedAccount.owningUser,
            userType: ServerConstants.userTypeOwning
        };
        
        psUserCreds.lookup(options, function (error) {
            if (error) {
                logger.error("Failed on lookup for PSUserCredentials: " + JSON.stringify(error));
                callback(error, null);
            }
            else {
                resultAccount[ServerConstants.accountUserName] = psUserCreds.username;
                currResult.push(resultAccount);
                
                currIndex++;
                makeAccountListAux(linkedAccounts, currIndex, currResult, callback);
            }
        });
    }
}

// export the class
module.exports = PSUserCredentials;

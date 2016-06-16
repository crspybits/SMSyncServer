// User credentials. A SharingUser will have the sharing user and linked owning user creds. An OnwningUser will just owning user creds. These are not persistently stored.
// This is generic -- there are also specific classes for dealing with specific account types.

'use strict';

// Local
var ServerConstants = require('./ServerConstants');
var logger = require('./Logger');
var GoogleUserCredentials = require('./GoogleUserCredentials');
var FacebookUserCredentials = require('./FacebookUserCredentials');

/* Constructor
    Throws an error if credentialsData don't have insufficient info.
    credentialsData is from serverConstants userCredentialsDataKey
 
    Public members:
        cloudFolderPath, mobileDeviceUUID
 
    Owning users will consist of just one set of account credentials-- for the owning user. This will be stored under the property:
            .owningUser
 
    Sharing users will have two sets of creds: the sharing user, and the linked owning user. These are under the properties:
            .sharingUser
            .linkedOwningUser
    
    .owningUser is not used in the case of sharing users to emphasize the fact that you must consider the .sharingUser first.
*/
function UserCredentials(credentialsData) {
    var self = this;
    
    self.owningUser = null;
    self.sharingUser = null;
    self.linkedOwningUser = null;

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
    
    var accountCreationMethods = [GoogleUserCredentials.CreateIfOurs, FacebookUserCredentials.CreateIfOurs];
    var creds = null;
    
    // Assume each of the factory methods knows when it should create its creds. Stop at the first one that works.
    for (var methodIndex in accountCreationMethods) {
        var factoryMethod = accountCreationMethods[methodIndex];
        
        // These factory constructors can throw-- but will just throw back to UserCredentials caller.
        creds = factoryMethod(credentialsData);
        if (creds) {
            break;
        }
    }
    
    if (!creds) {
        throw new Error("Couldn't create specific account creds!");
    }
    
    switch (credentialsData[ServerConstants.userType]) {
    case ServerConstants.userTypeOwning:
        self.owningUser = creds;
        break;
        
    case ServerConstants.userTypeSharing:
        self.sharingUser = creds;
        // TODO: Need to put owning user info, linked from sharing user, into .linkedOwningUser
        logger.debug("ServerConstants.userTypeSharing: " + JSON.stringify(self));
        break;
    
    default:
        throw new Error("Unhandled userType: " + credentialsData[ServerConstants.userType]);
        break;
    }
}

// instance methods

UserCredentials.prototype.signedInCreds = function () {
    var self = this;
    
    var creds = null;
    
    if (isDefined(self.owningUser)) {
        creds = self.owningUser;
    }
    else if (isDefined(self.sharingUser)) {
        creds = self.sharingUser;
    }
    
    return creds;
}

// Returns true iff an owning user is signed in.
UserCredentials.prototype.owningUserSignedIn = function () {
    var self = this;
    return isDefined(self.owningUser);
}

// Returns true iff a sharing user is signed in.
UserCredentials.prototype.sharingUserSignedIn = function () {
    var self = this;
    return isDefined(self.sharingUser);
}

// Specific account classes need to implement the following methods:

/*
// Returns info suitable for storing account specific (e.g., specific to a Google account) user credentials info into persistent storage. The structure of the info returned is the same as the `creds` field of the PSUserCredentials data model, but doesn't have the `creds` key itself.
// Returns this info, or null if it could not be obtained.
UserCredentials.prototype.persistent = function () {
    var self = this;
    
}

// The parameter is the same data that was returned from a call to the .persistent function. This info replaces that of the instance.
// The callback method has one parameter: error
UserCredentials.prototype.setPersistent = function (creds, callback) {
    var self = this;
    
}

// Returns an object suitable for querying persistent data, i.e., some of the data in the .persistent method may change over time, but that returned here doesn't change over time.
UserCredentials.prototype.persistentInvariant = function () {
    var self = this;
    
}

// Returns any possibly time varying parts of the persistent data. Returns null if no time-variant parts.
UserCredentials.prototype.persistentVariant = function () {
    var self = this;
    
}

// Check to see if these are valid credentials. Returns true or false.
// Callback takes two parameters: 1) error, and 2) if error is not null, a boolean which is true iff the error that occurred is that the user security information is stale. E.g., user should sign back in again.
UserCredentials.prototype.validate = function (callback) {
    var self = this;
    
}


// Refresh the access token from the refresh token. On success, the UserCredentials are now refreshed. The caller should take care of storing those in persistent storage.
// Callback: Takes one parameter: error.
UserCredentials.prototype.refreshSecurityTokens = function (callback) {
    var self = this;
    
}
*/

// export the class
module.exports = UserCredentials;

 
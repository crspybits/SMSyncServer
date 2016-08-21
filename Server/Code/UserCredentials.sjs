// Placeholder, unused "abstract" class.
// Specific account classes need to implement the following methods:

/*
UserCredentials constructor
    self.accountType = ... // E.g., ServerConstants.accountTypeFacebook
*/

/*
UserCredentials.CreateIfOurs = function (credentialsData) {
}

UserCredentials.CreateEmptyIfOurs = function (userType, accountType) {
}

// Returns info suitable for storing account specific (e.g., specific to a Google account) user credentials info into persistent storage. The structure of the info returned is the same as the `creds` field of the PSUserCredentials data model, but doesn't have the `creds` key itself.
// Returns this info, or null if it could not be obtained.
UserCredentials.prototype.persistent = function () {
    var self = this;
    
}

// The parameter is the same data that was returned from a call to the .persistent function. This info replaces that of the instance.
// The callback method has one parameter: error
UserCredentials.prototype.setPersistent = function (creds) {
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

// Only defined for a particular concrete subclass if persistentInvariant initially returns null for an apps creds. i.e., if a lookup has to occur before a validate.
// Parameter: mongoCreds: In same format as in PSUserCredentials .creds for these specific creds.
// Returns a Boolean -- true iff the creds were valid.
UserCredentials.prototype.validateStored = function (mongoCreds) {
    var self = this;
}


// Refresh the access token from the refresh token. On success, the UserCredentials are now refreshed. The caller should take care of storing those in persistent storage.
// Callback: Takes one parameter: error.
UserCredentials.prototype.refreshSecurityTokens = function (callback) {
    var self = this;
    
}
*/


 

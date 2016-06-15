// User credentials for Facebook SharingUser's.

'use strict';

// I could follow this process on the server-side to generate a longer-lived access token. Not sure if this is relevant though. I think I may be able to let the client refresh the access token.
// https://developers.facebook.com/docs/facebook-login/access-tokens/expiration-and-extension

// See https://github.com/request/request
var request = require('request');

// Local
var ServerConstants = require('./ServerConstants');
var logger = require('./Logger');
var Secrets = require('./Secrets');

// Constructor
// Throws an error if credentialsData don't have insufficient info.
// credentialsData is from serverConstants userCredentialsDataKey
// Public members:
//      cloudFolderPath, username
function FacebookUserCredentials(credentialsData) {
    var self = this;
    
    // Optional
    self.username = credentialsData[ServerConstants.accountUserName];
    
    self.userType = credentialsData[ServerConstants.userType];
    if (!isDefined(self.userType)) {
        throw new Error("No userType in credentials data!");
    }

    if (self.userType != ServerConstants.userTypeSharing) {
        throw new Error("Not dealing with Facebook owning users!");
    }

    self.accountType = credentialsData[ServerConstants.accountType];
    if (!isDefined(self.accountType)) {
        throw new Error("No accountType in credentials data!");
    }

    var userId = credentialsData[ServerConstants.facebookUserId];
    if (!isDefined(userId)) {
        throw new Error("No userId in credentials data!");
    }
    
    var accessToken = credentialsData[ServerConstants.facebookUserAccessToken];
    if (!isDefined(accessToken)) {
        throw new Error("No accessToken in credentials data!");
    }
    
    self.facebookSecrets = Secrets.sharingService(Secrets.facebookSharingService);

    self.creds = {
        userId: userId,
        
        // This is the new acccess token, just obtained from the app. Not the access token stored in Mongo.
        accessToken: accessToken
    };
}

// Returns a FacebookUserCredentials object if it can make one-- i.e., if credentialsData represents Facebook creds. Can throw an error. Returns null if no error and cannot create a Google creds object.
FacebookUserCredentials.CreateIfOurs = function (credentialsData) {
    var result = null;
    
    if (ServerConstants.accountTypeFacebook == credentialsData[ServerConstants.accountType]) {
        result = new FacebookUserCredentials(credentialsData);
    }
    
    return result;
}

// instance methods

// Returning null from this indicates that we don't yet have any persistent creds, and creds need be validated in order to provide those persistent creds. NOTE: For Facebook, we get persistent creds from the app as parameters.
FacebookUserCredentials.prototype.persistent = function () {
    var self = this;
    return {
        userId: self.creds.userId,
        accessToken: self.creds.accessToken
    };
}

// The parameter is the same data that was returned from a call to the .persistent function.
// The callback method has one parameter: error
FacebookUserCredentials.prototype.setPersistent = function (creds, callback) {
	var self = this;

    if (!isDefined(creds.userId) || !isDefined(creds.accessToken)) {
        callback("One more of the creds properties was empty.");
        return;
    }
    
    self.creds = {
        userId: creds.userId,
        accessToken: creds.accessToken
    };

    callback(null);
}

// Returns an object suitable for querying persistent data, i.e., some of the data in the .persistent method may change over time, but that returned here doesn't change over time. 
FacebookUserCredentials.prototype.persistentInvariant = function () {
	var self = this;
	return {
        userId: self.creds.userId
    };
}

// Returns any possibly time varying parts of the persistent data. Returns null if no time-variant parts.
FacebookUserCredentials.prototype.persistentVariant = function () {
    var self = this;
    return {
        accessToken: self.creds.accessToken
    };
}

// Requiring use of appsecret_proof on server API calls https://developers.facebook.com/docs/graph-api/securing-requests
// Validating an access token http://stackoverflow.com/questions/5406859/facebook-access-token-server-side-validation-for-iphone-app
// 6/14/16; I just asked a question on SO about doing Facebook access token validation purely locally to my server https://stackoverflow.com/questions/37822004/facebook-server-side-access-token-validation-can-it-be-done-locally
// Node module for FB: https://www.npmjs.com/package/fb
// https://developers.facebook.com/docs/facebook-login/access-tokens/debugging-and-error-handling

/* Check to see if these are valid credentials.
    Parameters:
    1) mongoCreds: The credentials currently stored by Mongo (may be null).
    2) callback: takes three parameters: 
        a) error, 
        b) if error is not null, a boolean which is true iff the error that occurred is that the user security information is stale. E.g., user should sign back in again.
        c) if no error, a boolean which is true iff the creds have been updated and need to be stored to persistent store.
*/
FacebookUserCredentials.prototype.validate = function (mongoCreds, callback) {
    var self = this;
    
    if (isDefined(mongoCreds)) {
        // Existing mongoDB creds for user.
        if (self.creds.accessToken == mongoCreds.accessToken &&
            self.creds.userId == mongoCreds.userId) {
            // Going to take this to mean that the accessToken hasn't changed, and since we already know about it, we must have validated it before.
            callback(null, null, false);
        }
    }
    
    // Either no existing mongoCreds, or they didn't match up with our creds. Validate by asking Facebook.
    
    // The app secret proof is a sha256 hash of your app access token, using the app secret as the key. Here's what the call looks like in PHP:
    // $appsecret_proof= hash_hmac('sha256', $app_access_token, $app_secret);

    /*
    GET /debug_token?
      input_token={input-token}&amp;
      access_token={access-token}
    input_token: the access token you want to get information about
    access_token: your app access token or a valid user access token from a developer of the app

    Example expected result:
    
    {
        "data": {
            "app_id": 000000000000000, 
            "application": "Social Cafe", 
            "expires_at": 1352419328, 
            "is_valid": true, 
            "issued_at": 1347235328, 
            "scopes": [
                "email", 
                "publish_actions"
            ], 
            "user_id": 1207059
        }
    }
    */
    
    // TODO: We could see if we could convert the expires_at field to a date/time and do our own checking for expiry.
    
    var queryArgs = {
        input_token: self.creds.accessToken,
        access_token: self.facebookSecrets.client_token
    };
    var url = 'https://graph.facebook.com/debug_token';
    
    // http://stackoverflow.com/questions/16903476/node-js-http-get-request-with-query-string-parameters

    request({url: url, qs: queryArgs}, function(err, response, body) {
        if (!error && response.statusCode == 200) {
            var result = JSON.parse(body);
            logger.debug("Result from Facebook:");
            logger.debug(result);
            
            if (result.app_id == self.facebookSecrets.app_id &&
                result.user_id == self.creds.userId) {
                callback(null, null, true);
            }
            else {
                var message = "Facebook creds returned didn't match that expected.";
                logger.error(message);
                callback(message, false, null);
            }
        } else {
            logger.error(err);
            logger.error("ERROR: Request status code: " + response.statusCode);
            callback(err, false, null);
        }
    });
}

// Refresh the access token from the refresh token. On success, the FacebookUserCredentials are now refreshed. The caller should take care of storing those in persistent storage.
// Callback: Takes one parameter: error.
FacebookUserCredentials.prototype.refreshSecurityTokens = function (callback) {
    var self = this;
    throw new Error("FacebookUserCredentials: Not implemented!");
}

// export the class
module.exports = FacebookUserCredentials;

 
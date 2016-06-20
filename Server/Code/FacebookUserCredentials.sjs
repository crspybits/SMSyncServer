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
// credentialsData has the same form as the .creds for Facebook in the data stored in PSUserCredetials.
function FacebookUserCredentials(credentialsData) {
    var self = this;
    self.creds = {};

    if (isDefined(credentialsData)) {
        self.facebookSecrets = Secrets.sharingService(Secrets.facebookSharingService);

        var userId = credentialsData[ServerConstants.facebookUserId];
        if (!isDefined(userId)) {
            throw new Error("No userId in credentials data!");
        }
        
        var accessToken = credentialsData[ServerConstants.facebookUserAccessToken];
        if (!isDefined(accessToken)) {
            throw new Error("No accessToken in credentials data!");
        }
        
        self.creds.userId = userId;
        
        // This is the new acccess token, just obtained from the app. Not the access token stored in Mongo.
        self.creds.accessToken = accessToken;
    }
}

// Returns a FacebookUserCredentials object if it can make one-- i.e., if credentialsData represents Facebook creds. Can throw an error. Returns null if no error and cannot create a Google creds object.
FacebookUserCredentials.CreateIfOurs = function (credentialsData) {
    var result = null;
    
    if (ServerConstants.accountTypeFacebook == credentialsData[ServerConstants.accountType]  &&
        ServerConstants.userTypeSharing == credentialsData[ServerConstants.userType]) {
        result = new FacebookUserCredentials(credentialsData);
    }
    
    return result;
}

FacebookUserCredentials.CreateEmptyIfOurs = function (userType, accountType) {
    var result = null;
    
    if (ServerConstants.accountTypeFacebook == accountType  &&
        ServerConstants.userTypeSharing == userType) {
        result = new FacebookUserCredentials();
    }
    
    return result;
}

// instance methods

// Returning null from this indicates that we don't yet have any persistent creds, and creds need be validated in order to provide those persistent creds. NOTE: For Facebook, we get persistent creds from the app as parameters.
FacebookUserCredentials.prototype.persistent = function () {
    var self = this;
    
    if (isDefined(self.creds.userId) && isDefined(self.creds.accessToken)) {
        return {
            userId: self.creds.userId,
            accessToken: self.creds.accessToken
        };
    }
    else {
        return null;
    }
}

// The parameter is the same data that was returned from a call to the .persistent function.
// The callback method has one parameter: error
FacebookUserCredentials.prototype.setPersistent = function (creds) {
	var self = this;

    if (!isDefined(creds.userId) || !isDefined(creds.accessToken)) {
        logger.debug("One more of the creds properties was empty.");
        self.creds = {};
    }
    else {
        self.creds = {
            userId: creds.userId,
            accessToken: creds.accessToken
        };
    }
}

// Returns an object suitable for querying persistent data, i.e., some of the data in the .persistent method may change over time, but that returned here doesn't change over time. 
FacebookUserCredentials.prototype.persistentInvariant = function () {
	var self = this;
    
    if (isDefined(self.creds.userId)) {
        return {
            userId: self.creds.userId
        };
    }
    else {
        return null;
    }
}

// Returns any possibly time varying parts of the persistent data. Returns null if no time-variant parts.
FacebookUserCredentials.prototype.persistentVariant = function () {
    var self = this;
    
    if (isDefined(self.creds.accessToken)) {
        return {
            accessToken: self.creds.accessToken
        };
    }
    else {
        return null;
    }
}

// Requiring use of appsecret_proof on server API calls https://developers.facebook.com/docs/graph-api/securing-requests
// Validating an access token http://stackoverflow.com/questions/5406859/facebook-access-token-server-side-validation-for-iphone-app
// 6/14/16; I just asked a question on SO about doing Facebook access token validation purely locally to my server https://stackoverflow.com/questions/37822004/facebook-server-side-access-token-validation-can-it-be-done-locally
// Node module for FB: https://www.npmjs.com/package/fb
// https://developers.facebook.com/docs/facebook-login/access-tokens/debugging-and-error-handling

/* Check to see if these are valid credentials.
    Parameters:
    1) mongoCreds: The credentials currently stored by Mongo in PSUserCredentials. Will not be null in this case because persistentInvariant returns non-null when we get initial params from app.
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
            return;
        }
    }
    
    // Either no existing mongoCreds, or they didn't match up with our creds. Validate by asking Facebook.
    
    // Even though I've turned on the option to require secret_proof, the debug_token REST call doesn't appear to require this.
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
    
    // TODO: We could see if we could convert the expires_at field to a date/time and do our own checking for expiry. I.e., do this checking when we don't explicitly call the Facebook REST API to check.
    
    var queryArgs = {
        input_token: self.creds.accessToken,
        access_token: self.creds.accessToken
        
        // access_token: self.facebookSecrets.client_token
        // This seems to be why I'm getting back: {"error":{"message":"Invalid OAuth access token.","type":"OAuthException","code":190,"fbtrace_id":"D1wApsVfsOP"}}
    };
    var url = 'https://graph.facebook.com/debug_token';
    
    // http://stackoverflow.com/questions/16903476/node-js-http-get-request-with-query-string-parameters

    request.get({url: url, qs: queryArgs}, function(err, response, body) {
        var result = JSON.parse(body);
        logger.debug("body: " + JSON.stringify(result));
        if (!err && response.statusCode == 200) {
            logger.debug("Result from Facebook:");
            logger.debug(result);
            
            if (!result.data.is_valid) {
                var message = "Invalid credentials: They seem to have expired.";
                logger.error(message);
                callback(message, true, null);
            }
            else if (result.data.application == self.facebookSecrets.application &&
                result.data.app_id == self.facebookSecrets.app_id &&
                result.data.user_id == self.creds.userId &&
                self.creds.userId == mongoCreds.userId) {
                
                // Return the last parameter as true because the creds access token we have is not stored in mongo, and needs to be stored there.
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

 

// User credentials for Google OwningUser's.

'use strict';

// See https://github.com/request/request
var request = require('request');

// See https://github.com/google/google-auth-library-nodejs
var googleAuth = require('google-auth-library');

// Local
var ServerConstants = require('./ServerConstants');
var logger = require('./Logger');
var Secrets = require('./Secrets');

// Constructor
// Throws an error if credentialsData don't have insufficient info, or if bad data.
// credentialsData is from serverConstants userCredentialsDataKey
// Only considers credentialsData info specific to Google.
function GoogleUserCredentials(credentialsData) {
    var self = this;
    
    self.accountType = ServerConstants.accountTypeGoogle;
    
    // Credentials specific to the user.
    self.sub = null; // user identifier

    // Data for signing into Google from clientSecretFile.
    self.googleServerCredentials = Secrets.cloudStorageService(Secrets.googleCloudStorageService);
    // logger.debug("Secrets.googleCloudStorageService" + Secrets.googleCloudStorageService);
    // logger.debug("self.googleServerCredentials" + self.googleServerCredentials);
    
    var auth = new googleAuth();
    
    self.oauth2Client =
            new auth.OAuth2(self.googleServerCredentials.client_id,
                self.googleServerCredentials.client_secret,
                self.googleServerCredentials.redirect_uris[0]);
    
    if (isDefined(credentialsData)) {
        self.idToken = credentialsData[ServerConstants.googleUserIdToken];
        if (!isDefined(self.idToken)) {
            throw new Error("No Google IdToken in credentials data!");
        }
        
        self.authCode = credentialsData[ServerConstants.googleUserAuthCode];
        
        logger.debug("AuthCode: " + self.authCode);
    }
    
    logger.debug("Created GoogleUserCredentials object");
}

// Returns a GoogleUserCredentials object if it can make one-- i.e., if credentialsData represents Google creds. Can throw an error. Returns null if no error and cannot create a Google creds object.
GoogleUserCredentials.CreateIfOurs = function (credentialsData) {
    var result = null;
    
    if (ServerConstants.accountTypeGoogle == credentialsData[ServerConstants.accountType] &&
        ServerConstants.userTypeOwning == credentialsData[ServerConstants.userType]) {
        result = new GoogleUserCredentials(credentialsData);
    }
    
    return result;
}

GoogleUserCredentials.CreateEmptyIfOurs = function (userType, accountType) {
    var result = null;
    
    if (ServerConstants.accountTypeGoogle == accountType  &&
        ServerConstants.userTypeOwning == userType) {
        result = new GoogleUserCredentials();
    }
    
    return result;
}

// instance methods

// Returning null from this indicates that we don't yet have any persistent creds, and creds need be validated in order to provide those persistent creds. NOTE: This *is* the case for Google.
GoogleUserCredentials.prototype.persistent = function () {
    var self = this;
    var creds = null;
    
    var accessToken = null;
    var refreshToken = null;
    
    if (isDefined(self.oauth2Client.credentials)) {
        accessToken = self.oauth2Client.credentials.access_token;
        refreshToken = self.oauth2Client.credentials.refresh_token;
    }
    
    // I'm making both the refresh token and .sub critical as we should never be in a situation were, if we have persistent creds, we don't have one of these.
    if (refreshToken || self.sub) {
        creds = {
            sub: self.sub,
            access_token: accessToken,
            refresh_token: refreshToken
        };
    }
    
    return creds;
}

GoogleUserCredentials.prototype.setPersistent = function (creds) {
	var self = this;
    
    logger.debug("creds: " + JSON.stringify(creds));

    if (!creds.access_token || !creds.refresh_token) {
        logger.debug("One or more of the creds properties was empty.");
        
        self.oauth2Client.setCredentials({});
    }
    else {
        self.oauth2Client.setCredentials({
            access_token: creds.access_token,
            refresh_token: creds.refresh_token
        });
    }
    
    self.sub = creds.sub;
}

GoogleUserCredentials.prototype.persistentInvariant = function () {
	var self = this;
	
	var creds = self.persistent();
	
	if (creds) {
		// Need to actually remove these elements, and not just set them to null, 
		// otherwise, mongo will search for null valued items in the db.
        delete creds.access_token;
        delete creds.refresh_token;
	}
	
	return creds;
}

// Returns any possibly time varying parts of the persistent data. Returns null if no time-variant parts.
GoogleUserCredentials.prototype.persistentVariant = function () {
	var self = this;
	
	var creds = self.persistent();
	
	if (creds) {
        // This is the invariant part.
        delete creds.sub;
        
		// Removing null elements as I don't want to save null elements to the database.
        if (!creds.access_token) {
            delete creds.access_token;
        }
        if (!creds.refresh_token) {
            delete creds.refresh_token;
        }
        
        // http://stackoverflow.com/questions/679915/how-do-i-test-for-an-empty-javascript-object
        if (Object.keys(creds).length == 0) {
            creds = null;
        }
	}
	
	return creds;
}

// Only defined for a particular concrete subclass if persistentInvariant initially returns null for an apps creds. i.e., if a lookup has to occur before a validate.
// Parameter: mongoCreds: In same format as in PSUserCredentials .creds for these specific creds.
// Returns a Boolean -- true iff the creds were valid.
GoogleUserCredentials.prototype.validateStored = function (mongoCreds) {
    var self = this;
    return mongoCreds.sub == self.sub;
}

/* Check to see if these are valid credentials.
    Parameters:
    1) mongoCreds: The credentials currently stored by Mongo (may be null). Will be null in this case because persistentInvariant returns null when we get initial params from app.
    2) callback: takes three parameters: 
        a) error, 
        b) if error is not null, a boolean which is true iff the error that occurred is that the user security information is stale. E.g., user should sign back in again.
        c) if no error, a boolean which is true iff the creds have been updated and need to be stored to persistent store.
*/
GoogleUserCredentials.prototype.validate = function (mongoCreds, callback) {
    // See http://stackoverflow.com/questions/20279484/how-to-access-the-correct-this-context-inside-a-callback
    var self = this;
    
    // The audience to verify against the ID Token  
    // See https://github.com/google/google-auth-library-nodejs/blob/master/lib/auth/oauth2client.js#L384
    // TODO: I think this is for the "aud" field
    var audience = null;
    
    // 12/1/15; I'm getting:
    //  verifyIdToken error: TypeError: Not a buffer
    // at times. See, e.g., https://github.com/google/google-auth-library-nodejs/issues/46
    // I got this when I tried to verify an IdToken that was a couple of days old.
    // When I Logged out from Google, then logged back in, the new IdToken succeeded with verify Token.
    /* Later today, I'm getting an error like:
    verifyIdToken error: Error: Token used too late, 1449373721.729 > 1449372540: {"iss":"https://accounts.google.com","at_hash":"uP9fQDUF_xrVAzy6TWLwWw","aud":"973140004732-bbgbqh5l8pmcr6lhmoh2cgggdkelh9gf.apps.googleusercontent.com","sub":"102879067671627156497","email_verified":true,"azp":"973140004732-nss95sev1cscktkds4nr8vchvbnkuh7g.apps.googleusercontent.com","email":"crspybits@gmail.com","iat":1449368640,"exp":1449372240,"name":"Christopher G. Prince","picture":"https://lh3.googleusercontent.com/-PuoGipqj3hE/AAAAAAAAAAI/AAAAAAAAAJ8/aSdvLsy51jE/s96-c/photo.jpg","given_name":"Christopher G.","family_name":"Prince","locale":"en"}
    */
    /* 12/9/15; I'm still getting "UserCredentials.sjs:116 () error: Not a buffer" at times. Seems to be because of a stale IdToken.
    */
    /*
    5/23/16. I think I've figured out how to deal with errors like this below. They are arising because the IdToken sent from the app to the server is too old. I'm sending rcStaleUserSecurityInfo back to the app when this happens, and the *app* is refreshing the IdToken.
    
    2016-05-24T09:36:12-0600 <info> UserCredentials.sjs:102 () failed on verifyIdToken: error: Error: Token used too late, 1464104172.28 > 1464073872: {"iss":"https://accounts.google.com","at_hash":"P0o0iv_RbsZAn4bx5XSyjA","aud":"973140004732-bbgbqh5l8pmcr6lhmoh2cgggdkelh9gf.apps.googleusercontent.com","sub":"102879067671627156497","email_verified":true,"azp":"973140004732-nss95sev1cscktkds4nr8vchvbnkuh7g.apps.googleusercontent.com","email":"crspybits@gmail.com","iat":1464069972,"exp":1464073572}
    */
    
    // An IdToken is an encrypted JWT. See http://stackoverflow.com/questions/8311836/how-to-identify-a-google-oauth2-user/13016081#13016081
    // The second parameter to the callback is a LoginTicket object, which is just a thin wrapper over the parsed idToken. Is the LoginTicket empty if we get back an error below?
    // logger.debug("Calling self.oauth2Client.verifyIdToken");
    self.oauth2Client.verifyIdToken(self.idToken, audience, function(err, loginTicket) {
            // logger.debug('verifyIdToken loginTicket: ' + JSON.stringify(loginTicket));
            if (err) {
                var stringMessage = "failed on verifyIdToken: error: "  + err;
                logger.info(stringMessage);
                
                const staleSecurityToken = "Token used too late";
                
                // indexOf returns -1 if the string is not found.
                if (stringMessage.indexOf(staleSecurityToken) != -1) {
                    // So, staleSecurityToken was found in the err.
                    logger.info("User security token is stale: %s; loginTicket: %j", err, loginTicket);
                    callback(err, true, null);
                }
                else {
                    logger.error(stringMessage);
                    callback(err, false, null);
                }
                
                return;
            }
            
            // See code. https://github.com/google/google-auth-library-nodejs/blob/master/lib/auth/loginticket.js
            // getUserId returns the "sub" field.
            self.sub = loginTicket.getUserId();

            logger.debug("GoogleUserCredentials.prototype.validate: " + JSON.stringify(self));
            // console.log(self.oauth2Client.credentials);
            
            // If there is an authorization code, I'm going to exchange it for an access token, and a refresh token (using exchangeAuthorizationCode), which generates a call to the Google servers, and thus takes some time. My assumption is that we will only have an authorization code here infrequently-- e.g., when the user initially signs into the app, this will generate an authorization code. Subsequently (and the main use case), when a silent sign in is used, there will be no authorization code, and hence no Google server access.
            if (!isDefined(self.authCode)) {
                logger.debug("We got no authorization code");
                logger.info("self.oauth2Client.credentials: " + JSON.stringify(self.oauth2Client.credentials));
                callback(null, null, false);
                return;
            }
            
            exchangeAuthorizationCode(self, function (err, exchangedContent) {
                if (err) {
                    logger.error('Error exchanging authorization code: ' + err);
                    callback(err, false, null);
                }
                else if (!exchangedContent || !exchangedContent.access_token || !exchangedContent.refresh_token) {
                    logger.debug("exchangedContent: " + JSON.stringify(exchangedContent));
                    callback("ERROR: Could not exchange authorization code", false, null);
                }
                else {
                    logger.debug("exchangedContent.access_token: " +
                        exchangedContent.access_token);
                    logger.debug("exchangedContent.refresh_token: " +
                         exchangedContent.refresh_token);

                    self.oauth2Client.setCredentials({
                        access_token: exchangedContent.access_token,
                        refresh_token: exchangedContent.refresh_token
                    });
                    
                    logger.info("self.oauth2Client.credentials: " + JSON.stringify(self.oauth2Client.credentials));
                    
                    callback(null, null, true);
                }
            });
        });
}

/* For documentation on HTTP/REST, see https://developers.google.com/identity/protocols/OAuth2WebServer
    POST /oauth2/v3/token HTTP/1.1
    Host: www.googleapis.com
    Content-Type: application/x-www-form-urlencoded

    code=4/P7q7W91a-oMsCeLvIaQm6bTrgtp7&
    client_id=8819981768.apps.googleusercontent.com&
    client_secret={client_secret}&
    redirect_uri=https://oauth2-login-demo.appspot.com/code&
    grant_type=authorization_code
    
Here's an example of what I get back:

{
 "access_token": "ya29.NwJ4xMGwm5sF4N536ZhKXAR8L-_9pqefPMEpNG_ULEEXWInZV9BVcvs61dFaHDN5JaYk",
 "token_type": "Bearer",
 "expires_in": 3600,
 "refresh_token": "1/PPjLOmTwqAjY8y5mL15Qc0hJpC_P2HI0i1pxg9Zy21g",
 "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IjNjNmEyYTExN2E4NTU2YmY2NDAwZmViOTM1MmE3YjgzYjVkYjc1NmQifQ.eyJpc3MiOiJhY2NvdW50cy5nb29nbGUuY29tIiwiYXRfaGFzaCI6IkNNYm1UZ1Z6V1BTWER6ZU5lWnFXaGciLCJhdWQiOiI5NzMxNDAwMDQ3MzItYmJnYnFoNWw4cG1jcjZsaG1vaDJjZ2dnZGtlbGg5Z2YuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMDI4NzkwNjc2NzE2MjcxNTY0OTciLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiYXpwIjoiOTczMTQwMDA0NzMyLWJiZ2JxaDVsOHBtY3I2bGhtb2gyY2dnZ2RrZWxoOWdmLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwiZW1haWwiOiJjcnNweWJpdHNAZ21haWwuY29tIiwiaWF0IjoxNDQ4NDQwNDA3LCJleHAiOjE0NDg0NDQwMDd9.OldjhbIpnvj4dcU_TeslJMq9scVAVKxRPHeruWZZJluU-DNvdCJTDAy4Vq5nixPyGVMxBFkAlk3kBMmJO0ME6mWpJJEXEcNAF_VmGE8t62y7T-Lq2XMtveqlYxBG2y6PJsaDDLhcBZ9ZhOae5V0QL670OHW9hsp-YjoELrobqdYp1FIo0vpjFJURgLCvv2q80JSS52BsVEJyWbz6nO_YPvBbyIV4Z76l7gyhtrPJc5BrcrAyeX4zkvpY5Y7AiZli2bDuASCPRCHOnyaVdLDai1q9wwqwUTjS9FZvTKpoekJLXdF_NYfKPGWT77lYW_rGxfDLleBeIiGNoQjlNKeXJA"
}
*/
// The callback has two parameters: error, and the if error is null, an instance of the above json structure.
function exchangeAuthorizationCode(self, callback) {
    var args = 
        {url:'https://www.googleapis.com/oauth2/v3/token', 
         form: {code: self.authCode,
                client_id: self.googleServerCredentials.client_id,
                client_secret: self.googleServerCredentials.client_secret,
                grant_type: "authorization_code"
               }
        };
    
    logger.debug("exchangeAuthorizationCode args: " + JSON.stringify(args));
    
    request.post(args, function(error, httpResponse, body) { 
        if (!error && httpResponse.statusCode == 200) {
            callback(null, JSON.parse(body));
        } else {
            callback(error, null);
        }
    });
}

// Refresh the access token from the refresh token. On success, the UserCredentials are now refreshed. The caller should take care of storing those in persistent storage.
// Callback: Takes one parameter: error.
GoogleUserCredentials.prototype.refreshSecurityTokens = function (callback) {
    var self = this;
    
    // See https://github.com/google/google-api-nodejs-client/#google-apis-nodejs-client
    
    self.oauth2Client.refreshAccessToken(function(err, tokens) {
        // your access_token is now refreshed and stored in oauth2Client
        // store these new tokens in a safe place (e.g. database)
        callback(err);
    });
    /* An example of what we get back in tokens:{"access_token":"ya29.RQLpOad7la5HEZwsVVDIXOLL5eXHyLwVoEqsOeymU3fxTxcgd075gO_bO1-2zfGxDviIJA","token_type":"Bearer","id_token":"eyJhbGciOiJSUzI1NiIsImtpZCI6ImI0MzZlODVkMTNhNTkzOTA2MmYxMjU3ZmE2YjZkYmQ0MjhlMTZhMWUifQ.eyJpc3MiOiJhY2NvdW50cy5nb29nbGUuY29tIiwiYXRfaGFzaCI6ImVVQWR5ZjJGVm0zQnc1eG5mVkpWcHciLCJhdWQiOiI5NzMxNDAwMDQ3MzItYmJnYnFoNWw4cG1jcjZsaG1vaDJjZ2dnZGtlbGg5Z2YuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMDI4NzkwNjc2NzE2MjcxNTY0OTciLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiYXpwIjoiOTczMTQwMDA0NzMyLWJiZ2JxaDVsOHBtY3I2bGhtb2gyY2dnZ2RrZWxoOWdmLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwiZW1haWwiOiJjcnNweWJpdHNAZ21haWwuY29tIiwiaWF0IjoxNDQ5NjMyODY4LCJleHAiOjE0NDk2MzY0Njh9.S0uOy3d-r0Liq2ITiQYZgwN0bm6inkMmVp-oNd-BB8Y_rJq0KUzGCG_hJBS_vb7Q0Y15mq4der3cB1QewEhbRxCIyh3JJuFL0CKyBKwZruGO0Bnv-sHYLo4QphqqoXb-n9LvmdNrvfwS6DDGrO5Ss8wJllSpzF46vj2lVbw99RpLpVD2r1XZ48uWtsaoOK7RZOwCl9-FR0vpo8gLs54LO6MKK2P9ihcd88zQ901vLObaCAjKrgD3H3AgUPsjlOJJli2Y_HVarOyl3xI5X2-tsi5GfaSj5lmFif1tslXeMFmBTVXagA25GTB70s85LldvUgpBNStmjPfL9pFySFvfmw","expiry_date":1449636468758,"refresh_token":"1/gsp8NzEDeIqntWoT4k3WwvydJYsE6ln4GaxbndyLROFIgOrJDtdun6zK6XiATCKT"}
    */
}

// export the class
module.exports = GoogleUserCredentials;

/*
Structure of the id token from Google.
https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo

E.g.,

{"iss":"accounts.google.com",
 "at_hash":"HK6E_P6Dh8Y93mRNtsDB1Q",
 "email_verified":"true",
 "sub":"10769150350006150715113082367",
 "azp":"1234987819200.apps.googleusercontent.com",
 "email":"jsmith@example.com",
 "aud":"1234987819200.apps.googleusercontent.com",
 "iat":1353601026,
 "exp":1353604926,
 "hd":"example.com" }
 
 sub: "An identifier for the user, unique among all Google accounts and never reused. A Google account can have multiple emails at different points in time, but the sub value is never changed. Use sub within your application as the unique-identifier key for the user."
 */

 

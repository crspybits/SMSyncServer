// User credentials in the cloud storage system.

'use strict';

var fs = require('fs');

// See https://github.com/request/request
var request = require('request');

// See https://github.com/google/google-auth-library-nodejs
var googleAuth = require('google-auth-library');

// Local
var ServerConstants = require('./ServerConstants');
var logger = require('./Logger');

// Constructor
// Throws an error if credentialsData don't have insufficient info.
// credentialsData is from serverConstants userCredentialsDataKey
// Public members:
//      cloudFolderPath
function UserCredentials(credentialsData) {    
    // always initialize all instance properties
    this.credentialsData = credentialsData;
    
    // TODO: Get this from the app.
    this.username = null;
    
    // Data for signing into Google from client_secret.json
    this.googleServerCredentials = {};
    
    // Credentials specific to the user.
    this.googleUserCredentials = {};
    this.googleUserCredentials.sub = null; // user identifier
    this.googleUserCredentials.oauth2Client = null;
    
    if (credentialsData[ServerConstants.cloudType] != ServerConstants.cloudTypeGoogle) {
        throw new Error("Bad Cloud Type in Credentials: " + credentialsData.cloudType);
    }
    
    this.cloudFolderPath = credentialsData[ServerConstants.cloudFolderPath];
    if (!isDefined(this.cloudFolderPath)) {
        throw new Error("No cloudFolderPath in credentials data!");
    }
    
    // This is not saved into PSUserCredentials -- there may be several of these across users of the same Google Creds. i.e., several devices across which the data is being shared.
    this.mobileDeviceUUID = credentialsData[ServerConstants.mobileDeviceUUIDKey];
    if (!isDefined(this.mobileDeviceUUID)) {
        throw new Error("No mobileDeviceUUID in credentials data!");
    }
    
    this.googleUserCredentials.idToken =
    	credentialsData[ServerConstants.googleUserCredentialsIdToken];
    if (!isDefined(this.googleUserCredentials.idToken)) {
        throw new Error("No Google IdToken in credentials data!");
    }
    
    // logger.debug("IdToken: " + this.googleUserCredentials.idToken);
    this.googleUserCredentials.authCode =
    	credentialsData[ServerConstants.googleUserCredentialsAuthCode];
    
    logger.debug("AuthCode: " + this.googleUserCredentials.authCode);
    logger.debug("Created UserCredentials object");
}

// instance methods

// Returns a info suitable for storing user credentials is cloud_storage field in persistent storage.
// See the PSUserCredentials data model.
// Returns this info, or null if it could not be obtained.
UserCredentials.prototype.persistent = function () {
    var self = this;
    var cloud_storage = null;
    
    // Make sure we have a refresh_token. The access_token can be obtained if we have
    // the refresh_token. Also make sure we have the "sub" field (the user identifier).
    
    if (self.googleUserCredentials.oauth2Client.refresh_token !== null && 
    		self.googleUserCredentials.sub !== null) {
    		
        cloud_storage = {
            cloud_type: "Google",
			cloud_creds: {
				sub: self.googleUserCredentials.sub,
				access_token: 
					self.googleUserCredentials.oauth2Client.credentials.access_token,
				refresh_token: 
					self.googleUserCredentials.oauth2Client.credentials.refresh_token
			}
        };
    }
    
    return cloud_storage;
}

// The parameter is the same data that was returned from a call to the .persistent function.
// The callback method has one parameter: error
UserCredentials.prototype.setPersistent = function (cloud_storage, callback) {
	var self = this;

    fs.readFile('client_secret.json', function (err, content) {
        if (err) {
            logger.error('Error loading client secret file: ' + err);
            callback(err);
            return;
        }
        
        if (!cloud_storage.cloud_creds.access_token ||
            !cloud_storage.cloud_creds.refresh_token ||
            !cloud_storage.cloud_creds.sub) {
            callback("One more of the cloud_storage properties was empty.");
            return;
        }

		var parsedContent = JSON.parse(content);
		self.googleServerCredentials = parsedContent.installed;

        var auth = new googleAuth();
        self.googleUserCredentials.oauth2Client = 
                new auth.OAuth2(self.googleServerCredentials.client_id,
                    self.googleServerCredentials.client_secret,
                    self.googleServerCredentials.redirect_uris[0]);
                
        self.googleUserCredentials.oauth2Client.setCredentials({
            access_token: cloud_storage.cloud_creds.access_token,
            refresh_token: cloud_storage.cloud_creds.refresh_token
        });
        
        self.googleUserCredentials.sub = cloud_storage.cloud_creds.sub;
        callback(null);
    });
}

// Returns an object suitable for querying persistent data, i.e., some of the data in the .persistent method may change over time, but that returned here doesn't change over time.
UserCredentials.prototype.persistentInvariant = function () {
	var self = this;
	
	var cloud_storage = self.persistent();
	
	if (cloud_storage) {
		// Need to actually remove these elements, and not just set them to null, 
		// otherwise, mongo will search for null valued items in the db.
		delete cloud_storage.cloud_creds.access_token;
		delete cloud_storage.cloud_creds.refresh_token;
	}
	
	return cloud_storage;
}

// Returns any possibly time varying parts of the persistent data. Returns null if no time-variant parts.
UserCredentials.prototype.persistentVariant = function () {
	var self = this;
	
	var cloud_storage = self.persistent();
	
	if (cloud_storage) {
        // These are the invariant parts.
        delete cloud_storage.cloud_type;
        delete cloud_storage.cloud_creds.sub;
        
		// Removing null elements as I don't want to save null elements to the database.
        if (!cloud_storage.cloud_creds.access_token) {
            delete cloud_storage.cloud_creds.access_token;
        }
        if (!cloud_storage.cloud_creds.refresh_token) {
            delete cloud_storage.cloud_creds.refresh_token;
        }
        
        // http://stackoverflow.com/questions/679915/how-do-i-test-for-an-empty-javascript-object
        if (Object.keys(cloud_storage.cloud_creds).length == 0) {
            cloud_storage = null;
        }
	}
	
	return cloud_storage;
}

// Check to see if these are valid credentials. Returns true or false.
// Callback takes two parameters: 1) error, and 2) if error is not null, a boolean which is true iff the error that occurred is that the user security information is stale. E.g., user should sign back in again.
UserCredentials.prototype.validate = function (callback) {
    // See http://stackoverflow.com/questions/20279484/how-to-access-the-correct-this-context-inside-a-callback
    var self = this;
    
    fs.readFile('client_secret.json', function (err, content) {
        if (err) {
            logger.error('Error loading client secret file: ' + err);
            callback(err, false);
            return;
        }

		var parsedContent = JSON.parse(content);
		self.googleServerCredentials = parsedContent.installed;

        var auth = new googleAuth();
        self.googleUserCredentials.oauth2Client = 
                new auth.OAuth2(self.googleServerCredentials.client_id,
                    self.googleServerCredentials.client_secret,
                    self.googleServerCredentials.redirect_uris[0]);

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
        
        // The second parameter to the callback is a LoginTicket object, 
        // which is just a thin wrapper over the parsed idToken.
        self.googleUserCredentials.oauth2Client.verifyIdToken(
            self.googleUserCredentials.idToken, audience, 
            
            function(err, loginTicket) {
                // console.log('verifyIdToken loginTicket: ' + JSON.stringify(loginTicket));
				if (err) {
                    var stringMessage = "failed on verifyIdToken: error: "  + err.message;
                    if (stringMessage.indexOf("Token used too late") != -1) {
                        logger.error("User security token is stale");
                        callback(err, true);
                    }
                    else {
                        logger.error(stringMessage);
                        callback(err, false);
                    }
					
					return;
				}
				
                // See code. https://github.com/google/google-auth-library-nodejs/blob/master/lib/auth/loginticket.js
				// getUserId returns the "sub" field.
            	self.googleUserCredentials.sub = loginTicket.getUserId();
                
                // console.log(self.googleUserCredentials.oauth2Client.credentials);
                
                // If there is an authorization code, I'm going to exchange it for an access token, and a refresh token (using exchangeAuthorizationCode), which generates a call to the Google servers, and thus takes some time. My assumption is that we will only have an authorization code here infrequently-- e.g., when the user initially signs into the app, this will generate an authorization code. Subsequently (and the main use case), when a silent sign in is used, there will be no authorization code, and hence no Google server access.
                if (!self.googleUserCredentials.authCode) {
                    logger.debug("We got no authorization code");
                	callback(null, null);
                	return;
                }
                
				exchangeAuthorizationCode(self.googleUserCredentials.authCode, 
					self.googleServerCredentials.client_id, 
					self.googleServerCredentials.client_secret, 
					function (err, exchangedContent) {

						if (err) {
							logger.error('Error exchanging authorization code: ' + err);
                            callback(err, false);
                        }
                        else if (!exchangedContent || !exchangedContent.access_token || !exchangedContent.refresh_token) {
                            callback("ERROR: Could not exchange authorization code", false);
						}
                        else {
							logger.debug("exchangedContent.access_token: " +
								exchangedContent.access_token);
							logger.debug("exchangedContent.refresh_token: " +
								 exchangedContent.refresh_token);

							self.googleUserCredentials.oauth2Client.setCredentials({
								access_token: exchangedContent.access_token,
								refresh_token: exchangedContent.refresh_token
							});
                            
                            callback(null, null);
						}
					});
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
function exchangeAuthorizationCode(authorizationCode, clientId, clientSecret, callback) {
    var args = 
        {url:'https://www.googleapis.com/oauth2/v3/token', 
         form: {code: authorizationCode,
                client_id: clientId,
                client_secret: clientSecret,
                grant_type: "authorization_code"
               }
        }
    
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
UserCredentials.prototype.refreshSecurityTokens = function (callback) {
    var self = this;
    
    // See https://github.com/google/google-api-nodejs-client/#google-apis-nodejs-client
    
    self.googleUserCredentials.oauth2Client.refreshAccessToken(function(err, tokens) {
        // your access_token is now refreshed and stored in oauth2Client
        // store these new tokens in a safe place (e.g. database)
        callback(err);
    });
    /* An example of what we get back in tokens:{"access_token":"ya29.RQLpOad7la5HEZwsVVDIXOLL5eXHyLwVoEqsOeymU3fxTxcgd075gO_bO1-2zfGxDviIJA","token_type":"Bearer","id_token":"eyJhbGciOiJSUzI1NiIsImtpZCI6ImI0MzZlODVkMTNhNTkzOTA2MmYxMjU3ZmE2YjZkYmQ0MjhlMTZhMWUifQ.eyJpc3MiOiJhY2NvdW50cy5nb29nbGUuY29tIiwiYXRfaGFzaCI6ImVVQWR5ZjJGVm0zQnc1eG5mVkpWcHciLCJhdWQiOiI5NzMxNDAwMDQ3MzItYmJnYnFoNWw4cG1jcjZsaG1vaDJjZ2dnZGtlbGg5Z2YuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMDI4NzkwNjc2NzE2MjcxNTY0OTciLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiYXpwIjoiOTczMTQwMDA0NzMyLWJiZ2JxaDVsOHBtY3I2bGhtb2gyY2dnZ2RrZWxoOWdmLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwiZW1haWwiOiJjcnNweWJpdHNAZ21haWwuY29tIiwiaWF0IjoxNDQ5NjMyODY4LCJleHAiOjE0NDk2MzY0Njh9.S0uOy3d-r0Liq2ITiQYZgwN0bm6inkMmVp-oNd-BB8Y_rJq0KUzGCG_hJBS_vb7Q0Y15mq4der3cB1QewEhbRxCIyh3JJuFL0CKyBKwZruGO0Bnv-sHYLo4QphqqoXb-n9LvmdNrvfwS6DDGrO5Ss8wJllSpzF46vj2lVbw99RpLpVD2r1XZ48uWtsaoOK7RZOwCl9-FR0vpo8gLs54LO6MKK2P9ihcd88zQ901vLObaCAjKrgD3H3AgUPsjlOJJli2Y_HVarOyl3xI5X2-tsi5GfaSj5lmFif1tslXeMFmBTVXagA25GTB70s85LldvUgpBNStmjPfL9pFySFvfmw","expiry_date":1449636468758,"refresh_token":"1/gsp8NzEDeIqntWoT4k3WwvydJYsE6ln4GaxbndyLROFIgOrJDtdun6zK6XiATCKT"}
    */
}

// export the class
module.exports = UserCredentials;

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
 
// Common methods on API operations.

'use strict';

// TODO: Temporary: Just for testing
// See https://developers.google.com/api-client-library/javascript/reference/referencedocs
var google = require('googleapis');

var PSUserCredentials = require('./PSUserCredentials');
var ServerConstants = require('./ServerConstants');
var UserCredentials = require('./UserCredentials.sjs');
var logger = require('./Logger');
var PSOperationId = require('./PSOperationId')
var PSLock = require('./PSLock')

// instance methods

// Constructor
// If no errors occur, creates a UserCredentials member named .userCreds and 
// Give errorHandling == true for handling server errors; the UserCredentials object will not be created in that case. Otherwise, give no errorHandling parameter and it will have a value of false by default.
// If an error occurs, the .error member is set to true. I have handled the error this way and not using an exception because I suspect that if we throw an exception, we don't get an Operation object back. And I need an Operation object to call the end method, for error handling.
function Operation(request, response, errorHandling) {
    var self = this;
    
    self.error = false;
    
    if (typeof(errorHandling) === "undefined") {
        errorHandling = false;
    }
    
    self.request = request;
    self.response = response;
    
    // The client expects a dictionary in response.
    self.result = {};
    
    // Many more cases fail than succeed, so make failure the default.
    self.result[ServerConstants.resultCodeKey] = ServerConstants.rcOperationFailed;
    
    // See macros.sjs for usage. Only used in development.
    // TODO: "Compile" this out (using a macro?) in development.
    self.debugTestCase = request.body[ServerConstants.debugTestCaseKey];
    
    // This important output on logging- may want to change the color to be something more distinctive.
    logger.trace("OPERATION: request.url: " + request.url);
    
    if (!errorHandling) {
        // Only log the request info in non-error handling cases.
        // logger.info("request.body: " + JSON.stringify(request.body));

        var credentialsData = request.body[ServerConstants.userCredentialsDataKey];
        if (!credentialsData) {
            var error = "No user credentials sent in request!";
            self.result[ServerConstants.errorDetailsKey] = error; // just for convenience.
            self.error = true;
        }
        else {
            //logger.debug("Creating a new UserCredentials object");
            
            try {
                self.userCreds = new UserCredentials(credentialsData);
            } catch (error) {
                logger.error("Failed creating UserCredentials: ", error.toString());
                self.result[ServerConstants.errorDetailsKey] = error; // just for convenience.
                self.error = true;
            }
            
            //logger.debug("Finished creating a new UserCredentials object: this.error: " + this.error);
        }
    }
}

// Checks if the user is on the system, and as a side effect (if no error), adds a PSUserCredentials object as a new member, .psUserCreds
// userMustBeOnSystem is optional, and defaults to true.
// On failure, ends the operation connection.
// Callback has parameters: 1) psLock (null if no lock), and 2) psOperationId (null if no lock or operationId). Callback is *not* called on an error.
Operation.prototype.validateUser = function (userMustBeOnSystem, callback) {
    var self = this;

    if (typeof userMustBeOnSystem === 'function') {
        callback = userMustBeOnSystem;
        userMustBeOnSystem = true;
    }
    
    self.validateUserAlwaysCallback(userMustBeOnSystem, function (error, staleUserSecurityInfo) {
        if (error) {
            if (staleUserSecurityInfo) {
                logger.error("validateUser: Invalid user: rcStaleUserSecurityInfo");
                self.endWithRCAndErrorDetails(ServerConstants.rcStaleUserSecurityInfo, error);
            }
            else {
                logger.error("validateUser: Invalid user: security info is not stale");
                self.endWithErrorDetails(error);
            }
        }
        else {
            // Because this is commonly something we want, check to see if we have a lock/operationId.
            
            PSLock.checkForOurLock(self.userId(), self.deviceId(), function (err, lock) {
                if (err) {
                    logger.error("Error on checkForOurLock: %j", err);
                    self.endWithErrorDetails(err);
                }
                else if (!lock) {
                    logger.info("Valid user: No lock");
                    callback(null, null);
                }
                else {
                    if (!isDefined(lock.operationId)) {
                        logger.info("Valid user: With lock, but no operationId");
                        callback(lock, null);
                        return;
                    }
                    
                    var psOperationId = null;
                    
                    const operationIdData = {
                        _id: lock.operationId,
                        userId: self.userId(),
                        deviceId: self.deviceId()
                    };
                    
                    try {
                        psOperationId = new PSOperationId(operationIdData);
                    } catch (error) {
                        self.endWithErrorDetails(error);
                        return;
                    }
                    
                    PSOperationId.getFor(lock.operationId, self.userId(), self.deviceId(), function (error, psOperationId) {
                        if (error) {
                            self.endWithErrorDetails(error);
                        }
                        else if (!isDefined(psOperationId)) {
                            var message = "validateUser: Could not get operation id:" +
                                lock.operationId;
                            logger.error(message);
                            self.endWithErrorDetails(message);
                        }
                        else {
                            logger.info("Valid user: With lock & operationId");
                            callback(lock, psOperationId);
                        }
                    });
                }
            });
        }
    });
}

// userMustBeOnSystem is optional, and defaults to true.
// With the default value of userMustBeOnSystem, if the user is not on the system, this is an error. If you set userMustBeOnSystem to false, this is not an error.
// Callback has two parameters: error, and if error != null a boolean, staleUserSecurityInfo
Operation.prototype.validateUserAlwaysCallback = function (userMustBeOnSystem, callback) {
    var self = this;
    
    if (typeof userMustBeOnSystem === 'function') {
        callback = userMustBeOnSystem;
        userMustBeOnSystem = true;
    }
    
    // Pass update as false because I'm assuming we won't have an authorization code when checking for an existing user.
    self.checkForExistingUser(false, function (error, staleUserSecurityInfo, psUserCreds) {
        if (error) {
			callback(error, staleUserSecurityInfo);
		}
        else {
            self.psUserCreds = psUserCreds;
            
            logger.info("UserId: " + self.userId());
            logger.info("DeviceId: " + self.deviceId());

            if (userMustBeOnSystem && !self.psUserCreds.stored) {
                callback("User is not on the system!", false);
                return;
            }
            
            callback(null, null);
        }
    });
}

Operation.prototype.end = function () {
    this.response.setHeader('Content-Type', 'application/json');
    // The client expects a dictionary in response.
    logger.trace("Sending response back to client: " + JSON.stringify(this.result));
    this.response.end(JSON.stringify(this.result));
    
    /*
    if (this.userCreds) {
        // A test just to see if the Google creds are actually working...
        listFiles(this.userCreds.googleUserCredentials.oauth2Client);
    }
    else {
        logger.info("No this.userCreds defined (Can't run Google list files test)");
    }*/
}

// Error details can be a string or an object.
Operation.prototype.endWithErrorDetails = function (errorDetails) {
    this.result[ServerConstants.errorDetailsKey] = errorDetails;
    this.end();
}

Operation.prototype.endWithRCAndErrorDetails = function (returnCode, errorDetails) {
    this.result[ServerConstants.errorDetailsKey] = errorDetails;
    this.result[ServerConstants.resultCodeKey] = returnCode;
    this.end();
}

Operation.prototype.endWithRC = function (returnCode) {
    this.result[ServerConstants.resultCodeKey] = returnCode;
    this.end();
}

// I'm dealing with ending downloads differently as I can't see a general way to get JSON params AND the file back to the client/app, other than using a custom HTTP header in the response.
Operation.prototype.prepareToEndDownload = function () {
    var result =  JSON.stringify(this.result);
    return result;
}

Operation.prototype.prepareToEndDownloadWithRC = function (returnCode) {
    this.result[ServerConstants.resultCodeKey] = returnCode;
    return this.prepareToEndDownload();
}

Operation.prototype.prepareToEndDownloadWithRCAndErrorDetails = function (returnCode, error) {
    this.result[ServerConstants.errorDetailsKey] = error;
    return this.prepareToEndDownloadWithRC(returnCode);
}

/* 
    update is of type bool:
        If the user exists in persistent storage, and:
        a) If update is true, this will update the persistent storage with any changes in the user credentials. (The intent here is for Google parameters where the access token, and refresh token will change if an authorization code is given in the user creds; this assumes that validate may change the user creds).
        b) If update is false, this will populate the user creds object with data from persistent storage. This should be the normal case: An API call needs to check the user creds, and update them with details from persistent storage if the user creds are valid.
    Callback has parameters: 
        1) error;
        2) if error != null, a boolean, which if true indicates the error was that the user could not be validated because ther security information is stale; this parameter is given as null if error is null
        2) if error is null, a PSUserCredentials object (use the .stored property of that object to see if the user exists in persistent storage).
*/
Operation.prototype.checkForExistingUser = function (update, callback) {
    var self = this;
    
	self.userCreds.validate(function(error, staleUserSecurityInfo) {
		if (error) {
			callback(error, staleUserSecurityInfo, null);
		}
		else {
            logger.info("self.userCreds.googleUserCredentials.oauth2Client.credentials: " + JSON.stringify(self.userCreds.googleUserCredentials.oauth2Client.credentials));
            
            var psUserCreds = null;
            try {
                psUserCreds = new PSUserCredentials(self.userCreds);
            } catch (error) {
                callback(error, false, null);
            }
            
			psUserCreds.lookup(function (error) {
				if (error) {
                    callback(error, false, null);
				}
				else if (psUserCreds.stored) {
                    if (update) {
                        // Update persistent store with user creds data.
                        psUserCreds.update(function (error) {
                            if (error) {
                                callback(error, false, null);
                            }
                            else {
                                callback(null, null, psUserCreds);
                            }
                        });
                    }
                    else {
                        // Populate user creds object from persistent store.
                        psUserCreds.populateFromUserCreds(function (error) {
                            if (error) {
                                callback(error, false, null);
                            }
                            else {
                                callback(null, null, psUserCreds);
                            }
                        });
                    }
				} 
				else {
					callback(null, null, psUserCreds);
				}
			});
		}
	});
}

Operation.prototype.userId = function() {
    return this.psUserCreds._id;
}

Operation.prototype.deviceId = function() {
    return this.userCreds.mobileDeviceUUID;
}

/**
 * Lists the names and IDs of up to 10 files.
 *
 * @param {google.auth.OAuth2} auth An authorized OAuth2 client.
 */
function listFiles(auth) {
    logger.info("Listing files...");
    var service = google.drive('v2');
    service.files.list({auth: auth, maxResults: 10}, function(err, response) {
        if (err) {
            logger.error('The API returned an error: ' + JSON.stringify(err));
            return;
        }
        var files = response.items;
        if (files.length == 0) {
            logger.info('No files found.');
        } else {
            logger.info('Files:');
            for (var i = 0; i < files.length; i++) {
                var file = files[i];
                logger.info('%s (%s)', file.title, file.id);
            }
        }
    });
}

// export the class
module.exports = Operation;

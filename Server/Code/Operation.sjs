// Common methods on API operations.

'use strict';

// TODO: Temporary: Just for testing
// See https://developers.google.com/api-client-library/javascript/reference/referencedocs
var google = require('googleapis');
var ObjectID = require('mongodb').ObjectID;

var PSUserCredentials = require('./PSUserCredentials');
var ServerConstants = require('./ServerConstants');
var logger = require('./Logger');

// instance methods

// Constructor
// If no errors occur, creates a PSUserCredentials member named .psUserCreds and
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
    
    // The client expects a dictionary in response to the HTTP request.
    self.result = {};
    
    // Many more cases fail than succeed, so make failure the default.
    self.result[ServerConstants.resultCodeKey] = ServerConstants.rcOperationFailed;
    
    // See macros.sjs for usage. Only used in development.
    // TODO: "Compile" this out (using a macro?) in development.
    self.debugTestCase = request.body[ServerConstants.debugTestCaseKey];
    
    // This is important output on logging- may want to change the color to be something more distinctive.
    logger.trace("OPERATION: request.url: " + request.url);
    
    if (!errorHandling) {
        // logger.info("request.body: " + JSON.stringify(request.body));

        var credentialsData = request.body[ServerConstants.userCredentialsDataKey];
        if (!isDefined(credentialsData)) {
            var error = "No user credentials sent in request!";
            self.result[ServerConstants.errorDetailsKey] = error; // just for convenience.
            self.error = true;
        }
        else {
            try {
                self.psUserCreds = new PSUserCredentials(credentialsData);
            } catch (error) {
                logger.error("Failed creating PSUserCredentials: ", error.toString());
                self.result[ServerConstants.errorDetailsKey] = error.toString(); // just for convenience.
                self.error = true;
            }
        }
    }
}

// Must have retrieved/stored psUserCreds from/to Mongo
// Returns the underlying owner user id.
Operation.prototype.userId = function() {
    var self = this;
    
    if (self.owningUserSignedIn()) {
        return self.psUserCreds._id;
    }
    else {
        if (! isDefined(self.psUserCreds.linkedOwningUserId)) {
            throw new Error("linkedOwningUserId is not defined!")
        }
        
        var userId = self.psUserCreds.linkedOwningUserId;
        
        if (typeof userId === 'string') {
            // Just allow the createFromHexString to throw. It's a problem, we need to catch it.
            userId = new ObjectID.createFromHexString(userId);
        }
    
        return userId;
    }
}

Operation.prototype.signedInUserId = function() {
    return this.psUserCreds._id;
}

Operation.prototype.deviceId = function() {
    return this.psUserCreds.mobileDeviceUUID;
}

Operation.prototype.owningUserSignedIn = function () {
    var self = this;
    return self.psUserCreds.owningUserSignedIn();
}

Operation.prototype.sharingUserSignedIn = function () {
    var self = this;
    return self.psUserCreds.sharingUserSignedIn();
}

// Is the current signed in user authorized to do this operation?
// One parameter: A sharingType (e.g., ServerConstants.sharingAdmin)
// Returns true or false. If it returns false, it ends the operation.
Operation.prototype.endIfUserNotAuthorizedFor = function (sharingType) {
    var self = this;
    
    if (self.psUserCreds.userAuthorizedFor(sharingType)) {
        return true;
    }
    else {
        var message = "User is not authorized for: " + sharingType;
        logger.error(message);
        self.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        return false;
    }
}

/* Checks if the user is on the system, and checks for an operationId.
    Parameters:
    1) Option object (optional):
        userMustBeOnSystem:Boolean (defaults to true)
        mustHaveLinkedOwningUserId:Boolean (defaults to true)
            When true, requires linkedOwningUserId when have a sharing user.
    2) Callback has no parameters
 
    On error, ends the operation connection.
*/
Operation.prototype.validateUser = function (options, callback) {
    var self = this;

    var userMustBeOnSystem = true;
    var mustHaveLinkedOwningUserId = true;
    
    if (typeof options === 'function') {
        callback = options;
    }
    else {
        if (isDefined(options.userMustBeOnSystem)) {
            userMustBeOnSystem = options.userMustBeOnSystem;
        }
        if (isDefined(options.mustHaveLinkedOwningUserId)) {
            mustHaveLinkedOwningUserId = options.mustHaveLinkedOwningUserId;
        }
    }
    
    // logger.debug("validateUser: ");
    // logger.debug(self);
    
    // When userMustBeOnSystem is true, validateUser is only called to perform operations, not to create users or check for existing users. When a sharing user is performing an operation, they *must* have a linkedOwningUserId
    if (mustHaveLinkedOwningUserId && self.psUserCreds.userType == ServerConstants.userTypeSharing && !isDefined(self.psUserCreds.linkedOwningUserId)) {
    
        self.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, "Sharing user, but no linkedOwningUserId");
        return;
    }
    
    self.validateUserAlwaysCallback(userMustBeOnSystem, function (error, staleUserSecurityInfo) {
        if (error) {
            if (staleUserSecurityInfo) {
                logger.error("validateUser: Invalid user: rcStaleUserSecurityInfo");
                self.endWithRCAndErrorDetails(ServerConstants.rcStaleUserSecurityInfo, error);
            }
            else {
                logger.error("validateUser: Invalid user: security info is not stale: " + JSON.stringify(error));
                self.endWithErrorDetails(error);
            }
        }
        else {
            logger.info("Valid user");
            callback();
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
    
    self.checkForExistingUser(function (error, staleUserSecurityInfo) {
        if (error) {
			callback(error, staleUserSecurityInfo);
		}
        else {
            logger.info("SignInUserId: " + self.signedInUserId());
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
Callback has parameters:
    1) error;
    2) if error != null, a boolean, which if true indicates the error was that the user could not be validated because there security information is stale; this parameter is given as null if error is null
*/
Operation.prototype.checkForExistingUser = function (callback) {
    var self = this;
    self.psUserCreds.lookupAndValidate(callback);
}

// export the class
module.exports = Operation;

var logger = require('../Logger');
var Operation = require('../Operation');
var ServerConstants = require('../ServerConstants');

// Not used, but needed to define name.
function UserEP() {
}

// Enable creation of an owning or sharing user.
// TODO: Eventually this needs to contain a check to ensure that only certain apps are calling this entry point. So that other apps don't use our server resources.
UserEP.createNewUser = function(request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }

    op.checkForExistingUser(function (error, staleUserSecurityInfo) {
        if (error) {
            if (staleUserSecurityInfo) {
                op.endWithRCAndErrorDetails(ServerConstants.rcStaleUserSecurityInfo, error);
            }
            else {
                op.endWithErrorDetails(error);
            }
        }
        else {
            logger.info("psUserCreds.stored: " + op.psUserCreds.stored);
            if (op.psUserCreds.stored) {
                op.endWithRC(ServerConstants.rcUserOnSystem);
            }
            else {
                // User creds not yet stored in Mongo. Store 'em.
                op.psUserCreds.storeNew(function (error) {
                    if (error) {
                        op.endWithErrorDetails(error);
                    }
                    else {
                        op.result[ServerConstants.internalUserId] = op.psUserCreds._id;
                        op.endWithRC(ServerConstants.rcOK);
                    }
                });
            }
        }
    });
};

UserEP.checkForExistingUser = function(request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }

    op.validateUser({userMustBeOnSystem:false, mustHaveLinkedOwningUserId:false}, function () {
        if (op.psUserCreds.stored) {
            op.result[ServerConstants.internalUserId] = op.psUserCreds._id;
            op.endWithRC(ServerConstants.rcUserOnSystem);
        }
        else {
            op.endWithRC(ServerConstants.rcUserNotOnSystem);
        }
    });
};

// export the class
module.exports = UserEP;

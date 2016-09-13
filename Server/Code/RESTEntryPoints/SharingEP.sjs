var logger = require('../Logger');
var Operation = require('../Operation');
var ServerConstants = require('../ServerConstants');
var Mongo = require('../Mongo');

// Not used, but needed to define name.
function SharingEP() {
}

SharingEP.createSharingInvitation = function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        // User is on the system.

        if (!op.endIfUserNotAuthorizedFor(ServerConstants.sharingAdmin)) {
            return;
        }
                    
        var sharingType = request.body[ServerConstants.sharingType];
        if (!isDefined(sharingType)) {
            var message = "No sharingType was sent!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        var possibleSharingTypeValues = [ServerConstants.sharingDownloader, ServerConstants.sharingUploader, ServerConstants.sharingAdmin];
        
        // Ensure we got a valid sharingType

        if (possibleSharingTypeValues.indexOf(sharingType) == -1) {
            var message = "You gave an unknown sharingType: " + sharingType;
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        var sharingInvitation = new Mongo.SharingInvitation({
            owningUser: op.userId(),
            sharingType: sharingType
        });
        
        sharingInvitation.save(function (err, sharingInvitation) {
            if (err) {
                op.endWithErrorDetails(err);
            }
            else {
                logger.trace("New Sharing Invitation:");
                logger.debug(sharingInvitation);
                op.result[ServerConstants.sharingInvitationCode] = sharingInvitation._id;
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
};

SharingEP.lookupSharingInvitation = function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        // User is on the system.
        
        var invitationCode = request.body[ServerConstants.sharingInvitationCode];
        if (!isDefined(invitationCode)) {
            var message = "No invitation code was sent!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        Mongo.SharingInvitation.findOne({ _id: invitationCode }, function (err, sharingInvitation) {
            if (err) {
                op.endWithErrorDetails(err);
            }
            else {
                logger.trace("Found Sharing Invitation:");
                logger.debug(sharingInvitation);
                
                // Make sure that the owningUser is us-- otherwise, this is a security issue.
                if (!op.userId().equals(sharingInvitation.owningUser)) {
                    logger.error("Current userId: " + op.userId() + "; owningUser: " + sharingInvitation.owningUser + "; typeof owningUser: " + typeof sharingInvitation.owningUser);
                    
                    var message = "You didn't own this sharing invitation!";
                    logger.error(message);
                    op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                    return;
                }

                var invitationContents = {};
                invitationContents[ServerConstants.invitationExpiryDate] = sharingInvitation.expiry;
                invitationContents[ServerConstants.invitationOwningUser] = sharingInvitation.owningUser;
                invitationContents[ServerConstants.invitationSharingType] = sharingInvitation.sharingType;
                
                op.result[ServerConstants.resultInvitationContentsKey] = invitationContents;
                
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
};

// You can redeem a sharing invitation for a new user (user created by this call), or for an existing user.
SharingEP.redeemSharingInvitation = function (request, response) {
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
    
            // Make sure the creds are for a SharingUser. Do this after checkForExistingUser because in general, we may need to do a mongo lookup to determine if this user can be a sharing user.
            if (!op.sharingUserSignedIn()) {
                var message = "Error: Attempt to redeem sharing invitation by a non-sharing user!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }
    
            var invitationCode = request.body[ServerConstants.sharingInvitationCode];
            if (!isDefined(invitationCode)) {
                var message = "No invitation code was sent!";
                logger.error(message);
                op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
                return;
            }

            finishRedeemingSharingInvitation(op, invitationCode, op.psUserCreds);
        }
    });
};

function finishRedeemingSharingInvitation(op, invitationCode, psUserCreds) {
    // The following query for findOneAndUpdate also does validation: It ensures the invitation hasn't already been redeemed, and hasn't expired. I'm assuming that this will take place atomically across possibly multiple server instances.
    
    // http://mongoosejs.com/docs/api.html#model_Model.findOneAndUpdate
    var now = new Date ();
    var query = {
        _id: invitationCode,
        redeemed: false,
        
        // I'm looking for an invitation that has an expiry that is >= the date right now. This defines expiry. E.g., say an expiry is: 2016-06-16T22:42:19.393Z
        // and the current date is: 2016-06-15T22:52:02.593Z
        "expiry": {$gte: now}
    };
    var update = { $set: {redeemed: true} };
    
    Mongo.SharingInvitation.findOneAndUpdate(query, update, function (err, invitationDoc) {
        if (err || !invitationDoc) {
            var message = "Error updating/redeeming invitation: It was a bad invitation, expired, or had already been redeemed.";
            logger.error(message + " error: " + JSON.stringify(err));
            op.endWithRCAndErrorDetails(
                ServerConstants.rcCouldNotRedeemSharingInvitation, message);
        }
        else {
            
            // Errors after this point will fail and will have marked the invitation as redeemed. Not the best of techniques, but once we get initial testing done, failures after this point should be rare. It would, of course, be better to rollback our db changes. :(. Thanks MongoDB! Not!
            // In the worst case we get an invitation that is marked as redeemed, but it fails to allow linking for the user. Presumably, the person that did the inviting in that case would have to generate a new invitation.
            
            logger.trace("Found and redeemed Sharing Invitation: " + JSON.stringify(invitationDoc));
                
            // Need to link the invitation into the sharing user's account.
            
            var newLinked = {
                owningUser: invitationDoc.owningUser,
                sharingType: invitationDoc.sharingType
            };
                        
            // First, let's see if the given owningUser is already present in the sharing user's linked accounts.
            var found = false;
            if (psUserCreds.stored) {
                logger.debug("looking for owningUser in linked accounts");
                
                for (var linkedIndex in psUserCreds.linked) {
                    var linkedCreds = psUserCreds.linked[linkedIndex];
                    var linkedOwningUser = linkedCreds.owningUser;
                    var invitationOwningUser = invitationDoc.owningUser;
                    
                    // See http://stackoverflow.com/questions/11060213/mongoose-objectid-comparisons-fail-inconsistently/38298148#38298148 for the reason for using string comparison and not the .equals method of ObjectID's.
                    
                    if (String(invitationOwningUser) === String(linkedOwningUser)) {
                        logger.info("Redeeming with existing owningUser: Replacing.");
                        found = true;
                        psUserCreds.linked[linkedIndex] = newLinked;
                        break;
                    }
                }
            }
            
            if (psUserCreds.stored) {
                if (!found) {
                    psUserCreds.linked.push(newLinked);
                }
                
                var saveAll = true;
                psUserCreds.update(function (err) {
                    if (err) {
                        op.endWithErrorDetails(err);
                    }
                    else {
                        op.result[ServerConstants.linkedOwningUserId] = invitationDoc.owningUser;
                        op.endWithRC(ServerConstants.rcUserOnSystem);
                    }
                });
            }
            else {
                psUserCreds.linked.push(newLinked);
                
                // User creds not yet stored in Mongo. Store 'em.
                psUserCreds.storeNew(function (error) {
                    if (error) {
                        op.endWithErrorDetails(error);
                    }
                    else {
                        op.result[ServerConstants.linkedOwningUserId] = invitationDoc.owningUser;
                        op.result[ServerConstants.internalUserId] = psUserCreds._id;
                        op.endWithRC(ServerConstants.rcOK);
                    }
                });
            }
        }
    });
}

SharingEP.getLinkedAccountsForSharingUser = function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
        
    op.validateUser({mustHaveLinkedOwningUserId:false}, function () {
        // User is on the system.

        if (!op.sharingUserSignedIn()) {
            var message = "Error: Attempt to get linked accounts by a non-sharing user!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        op.psUserCreds.makeAccountList(function (error, accountList) {
            if (error) {
                logger.error("Failed on makeAccountList for PSUserCredentials: " + JSON.stringify(error));
                op.endWithErrorDetails(error);
            }
            else {
                op.result[ServerConstants.resultLinkedAccountsKey] = accountList;
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
};

// export the class
module.exports = SharingEP;

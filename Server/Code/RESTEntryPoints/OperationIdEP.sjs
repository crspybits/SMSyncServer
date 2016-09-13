app.post('/' + ServerConstants.operationCheckOperationStatus, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
    
        var operationId = request.body[ServerConstants.operationIdKey];
        if (!isDefined(operationId)) {
            var message = "No operationIdKey given in HTTP params!";
            logger.error(message);
            op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
            return;
        }
        
        // We already have the psOperationId, but go ahead and use the app/client's operationId to look it up.
        PSOperationId.getFor(operationId, op.userId(), op.deviceId(), function (error, psOperationId) {
            if (error) {
                op.endWithErrorDetails(error);
            }
            else if (!isDefined(psOperationId)) {
                var errorMessage = "operationCheckOperationStatus: Could not get operation id: "
                    + operationId;
                logger.error(errorMessage);
                op.endWithErrorDetails(errorMessage);
            }
            else {
                op.result[ServerConstants.resultOperationStatusCountKey] = psOperationId.operationCount;
                op.result[ServerConstants.resultOperationStatusCodeKey] = psOperationId.operationStatus;
                op.result[ServerConstants.resultOperationStatusErrorKey] = psOperationId.error;
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
});

// Returns no operation Id if there is none.
app.post('/' + ServerConstants.operationGetOperationId, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        if (isDefined(psOperationId)) {
            logger.info("Returning operationId to client: " + psOperationId._id);
            op.result[ServerConstants.resultOperationIdKey] = psOperationId._id;
        }
        
        op.endWithRC(ServerConstants.rcOK);
    });
});

app.post('/' + ServerConstants.operationRemoveOperationId, function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        removeOperationId(op, request);
    });
});

// Remove the operation id, and send the result back to REST/API caller.
function removeOperationId(op, request) {
    // operationId is a string-- a parameter from the client.
    var operationId = request.body[ServerConstants.operationIdKey];
    
    if (!isDefined(operationId)) {
        var message = "No operationIdKey given in HTTP params!";
        logger.error(message);
        op.endWithRCAndErrorDetails(ServerConstants.rcServerAPIError, message);
        return;
    }
    
    // Specifically *not* checking to see if we have a lock. If the operation has successfully completed, the lock will have been removed.

    // We already have the psOperationId, but go ahead and use the app/client's operationId to look it up. On second thoughts, look for any PSOperationId for the client. Then, compare, if any to the operationId string. We can check for more different types of errors this way.
    PSOperationId.getFor(null, op.userId(), op.deviceId(), function (error, psOperationId) {
        if (error) {
            op.endWithErrorDetails(error);
        }
        else if (!isDefined(psOperationId)) {
            // 4/27/16; We're not going to treat this as an error, in order to enable self-recovery for this method. That is, if the operationId has already been removed, but communication back to client failed, then we shouldn't fail if we don't find the operationId now.
            logger.info("Apparent recovery: Couldn't remove operation id: " + operationId);
            op.endWithRC(ServerConstants.rcOK);
        }
        else if (operationId != psOperationId._id) { // Seems we can use equality/inequality test directly across a string and ObjectID
            // Found operationId, but it wasn't the one we were looking for. Ouch!!
            var errorMessage = "removeOperationId: Could not get operation id: " + operationId + "; instead found: " + JSON.stringify(psOperationId);
            logger.error(errorMessage);
            op.endWithErrorDetails(errorMessage);
        }
        else {
            psOperationId.remove(function (error) {
                if (error) {
                    op.endWithErrorDetails(error);
                }
                else {
                    op.endWithRC(ServerConstants.rcOK);
                }
            });
        }
    });
}


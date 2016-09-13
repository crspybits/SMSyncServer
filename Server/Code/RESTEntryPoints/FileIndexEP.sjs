var logger = require('../Logger');
var Operation = require('../Operation');
var ServerConstants = require('../ServerConstants');
var PSFileIndex = require('../PSFileIndex');
var Mongo = require('../Mongo');

// Not used, but needed to define name.
function FileIndexEP() {
}

FileIndexEP.getFileIndex = function (request, response) {
    var op = new Operation(request, response);
    if (op.error) {
        op.end();
        return;
    }
    
    op.validateUser(function () {
        logger.debug("Getting list of files for userId: " + op.userId());

        // 1) Get the File Index Lock
        // 2) Get the Global Version for the file index (making one if necessary).
        // 3) Get the File Index
        // 4) Release the lock.
        
        Mongo.fileIndexLock.pollAquire(function(err, lockAcquired) {
            if (err || !lockAcquired) {
                var message = "Could not acquire the lock: " + JSON.stringify(err);
                logger.error(message);
                op.endWithErrorDetails(message);
                return;
            }

            logger.debug("Lock was successfully acquired.");
            
            Mongo.GlobalVersion.findOne({ userId: op.userId() }, function (err, globalVersionDoc) {
                if (err) {
                    op.endWithErrorDetails(err);
                }
                else if (!isDefined(globalVersionDoc)) {
                    // No global version for this users file index: Need to create one.

                    var globalVersion = new Mongo.GlobalVersion({
                        userId: op.userId(),
                        version: 0
                    });
                    
                    globalVersion.save(function (err, globalVersionDoc) {
                        if (err || !globalVersionDoc) {
                            op.endWithErrorDetails(err);
                        }
                        else {
                            finishOperationGetFileIndex(op, globalVersionDoc.version);
                        }
                    });
                }
                else {
                    finishOperationGetFileIndex(op, globalVersionDoc.version);
                }
            });
        });
    });
};

function finishOperationGetFileIndex(op, fileIndexVersion) {
    PSFileIndex.getAllFor(op.userId(), function (psFileIndexError, fileIndexObjs) {
        if (psFileIndexError) {
            op.endWithErrorDetails(psFileIndexError);
            return;
        }

        // Get rid of _id and userId properties because neither is no business of the client's.
        for (var index in fileIndexObjs) {
            var obj = fileIndexObjs[index];
            delete obj._id;
            delete obj.userId;
        }
        
        Mongo.fileIndexLock.release(function(err, lockTimedOut) {
            if (err || lockTimedOut) {
                const message = "Could not release lock at end of operation: " + JSON.stringify(err);
                logger.error(message);
                op.endWithErrorDetails(psFileIndexError);
            }
            else {
                op.result[ServerConstants.fileIndexVersionKey] = fileIndexVersion;
                op.result[ServerConstants.resultFileIndexKey] = fileIndexObjs;
                op.endWithRC(ServerConstants.rcOK);
            }
        });
    });
}

// export the class
module.exports = FileIndexEP;

#!/bin/sh

clear

mongo << EOF

// Tried using this Javascript function to do db[collection].find().pretty() directly, but doesn't show output
function showCollectionNameFor(collection) {
    print()
    var count = db[collection].count()
    if (count >= 1) {
        print (collection)
    }
    else {
        print (collection + " is empty")
    }
}

showCollectionNameFor("OutboundFileChanges");
db.OutboundFileChanges.find().pretty()

showCollectionNameFor("UserCredentials");
db.UserCredentials.find().pretty()

showCollectionNameFor("Locks");
db.Locks.find().pretty()

showCollectionNameFor("FileIndex");
db.FileIndex.find().pretty()

showCollectionNameFor("OperationIds");
db.OperationIds.find().pretty()

showCollectionNameFor("PSFileTransferLog");
db.PSFileTransferLog.find().pretty()

EOF

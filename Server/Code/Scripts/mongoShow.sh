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

showCollectionNameFor("UserCredentials");
db.UserCredentials.find().pretty()

showCollectionNameFor("FileIndex");
db.FileIndex.find().pretty()

showCollectionNameFor("SharingInvitations");
db.SharingInvitations.find().pretty()

showCollectionNameFor("GlobalVersions");
db.GlobalVersions.find().pretty()

showCollectionNameFor("Uploads");
db.Uploads.find().pretty()

showCollectionNameFor("distributedlocks");
db.distributedlocks.find().pretty()

EOF

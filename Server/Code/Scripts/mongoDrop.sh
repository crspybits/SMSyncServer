#!/bin/sh

clear

mongo << EOF

db.FileIndex.drop()
db.SharingInvitations.drop()
db.Uploads.drop()
db.GlobalVersions.drop()
db.distributedlocks.drop()

EOF

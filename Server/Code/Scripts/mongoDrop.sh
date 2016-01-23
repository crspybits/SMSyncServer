#!/bin/sh

clear

mongo << EOF

db.Locks.drop()
db.OutboundFileChanges.drop()
db.OperationIds.drop()
db.FileIndex.drop()
db.FileTransferLog.drop()
db.InboundFiles.drop()

EOF

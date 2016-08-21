#!/bin/sh

# This starts or restarts the app on Bluemix

cp ../../../Private/SharedNotes/serverSecrets.json .

DATE=`date`

# In normal operation, I'm keeping the Server .git directory named as .ignored.git so it doesn't conflict with my overall Git project for the SMSyncServer. I.e., I see no reason to have a Git submodule for the server just because Bluemix has the requirement to push the server in Git format.
mv .ignored.git .git

git add .
git commit -a -m "Updated server: ${DATE}"
git push

# Move it back
mv .git .ignored.git 

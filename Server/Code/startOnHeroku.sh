#!/bin/sh

# This starts or restarts the app on Heroku

DATE=`date`

# In normal operation, I'm keeping the .git directory named as .ignored.git so it doesn't conflict with my overall Git project for the SMSyncServer
mv .ignored.git .git

# googleClientSecretSource.json is a symbolically linked file-- so we don't get the client secret stored to the public git repo. When  We copy it, it traverses the sym link. The file googleClientSecret.json is the one referenced in the JavaScript code.
cp googleClientSecretSource.json googleClientSecret.json

git add .
git commit -a -m "Updated server: ${DATE}"
git push heroku master

# Move it back
mv .git .ignored.git 

# So we don't store the secrets to public git repo.
rm googleClientSecret.json
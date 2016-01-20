When I started the node.js server, I got:
Failed to load c++ bson extension, using pure JS version
(Haven't resolved this).

Also, I wasn't getting any records inserted until I did this:
 "mongodb":"1.4.34"
 in the package.json and ran
 npm update
 
 Looks like the driver has changed to 2.0
 http://mongodb.github.io/node-mongodb-native/2.0/meta/changes-from-1.0/
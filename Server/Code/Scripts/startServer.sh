#!/bin/bash

# Start our server

clear

# Regenerate constants used both in Swift and in Javascript. Eventually, once we've finished with testing on my local system, we'll run this before uploading to the server.
# Comment this out for production server!
./Scripts/makeServerConstants.sh

node index.js


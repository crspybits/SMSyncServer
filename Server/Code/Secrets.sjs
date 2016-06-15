// Accessing server secrets stored in an external file.

'use strict';

var logger = require('./Logger');
var fs = require('fs');

// See README.md for the structure of this file
const secretsFile = "serverSecrets.json";

const mongoURL = "MongoDbURL";
const cloudStorage = "CloudStorageServices";
const sharingServices = "SharingServices";

var secrets = null;

// Call this just once, when the server starts.
// Callback is a function with one parameter: error
exports.load = function(callback) {
    fs.readFile(secretsFile, function (err, fileContents) {
        var parsedFileContents = JSON.parse(fileContents);

        if (!isDefined(parsedFileContents)) {
            logger.error('Error loading server secrets file: ' + err);
            callback(err);
            return;
        }
        
        logger.info("Server secrets are loaded.");
        secrets = parsedFileContents;
        
        //logger.info("secrets: " + JSON.stringify(secrets));
        //logger.info("secrets[mongoURL]: " + secrets[mongoURL] + " " + typeof secrets[mongoURL]);
        
        callback(null);
    });
};

// 5/3/16; When running on Heroku, they would have you use a Heroku configuration variable to get the Mongodb URL (see https://devcenter.heroku.com/articles/getting-started-with-nodejs#define-config-vars). However, I want to reduce hosting environmental dependencies, so I'm putting this URL in the serverSecrets.json file.

exports.mongoDbURL = function() {
    var mURL = secrets[mongoURL];
    return mURL;
};

// Strangeness for exporting constant strings...
function define(name, value) {
	Object.defineProperty(exports, name, {
		value:      value,
		enumerable: true
	});
}

// Cloud storage serviceName's
define("googleCloudStorageService", "GoogleDrive");

// serviceName needs to be one of the above
// Returns undefined if the service cannot be found.
exports.cloudStorageService = function(serviceName) {
    var serviceSecrets = secrets[cloudStorage];
    var serviceSecret = serviceSecrets[serviceName];
    return serviceSecret;
};

// SharingServices
define("facebookSharingService", "Facebook");

// serviceName needs to be one of the above
// Returns undefined if the service cannot be found.
exports.sharingService = function(serviceName) {
    var serviceSecrets = secrets[sharingServices];
    var serviceSecret = serviceSecrets[serviceName];
    return serviceSecret;
};

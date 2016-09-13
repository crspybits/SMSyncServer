'use strict';

// Before the files get moved to their specific-user destination.
const initialUploadDirectory = './initialUploads/';

// TODO: What is safe mode in mongo? E.g., see https://mongodb.github.io/node-mongodb-native/api-generated/collection.html#insert
// See also options on insert https://mongodb.github.io/node-mongodb-native/api-generated/collection.html#insert
// Look at WriteConcern in mongo; see http://edgystuff.tumblr.com/post/93523827905/how-to-implement-robust-and-scalable-transactions
// WriteConcern is the same as safe mode http://api.mongodb.org/c/0.6/write_concern.html

// TODO: Need some logging to an external file: E.g., of error messages, of server failures/restarts (assuming that technically we can actually do that in [3] below), and other important events.
// TODO: It would also be good to log some analytics to a MongoDb collection for usage stats. E.g., the number of uploads/downloads etc. so we could do a little tracking of the amount of usage of the server. This wouldn't have to be on the basis of individual users-- it could be anonymized and comprise combined stats across all users.

var express = require('express');
var bodyParser = require('body-parser');
var app = express();
var assert = require('assert');

// Local modules.
var ServerConstants = require('../ServerConstants');
var Mongo = require('../Mongo');
var Operation = require('../Operation');
var logger = require('../Logger');
var Common = require('../Common');
var Secrets = require('../Secrets');
require('../Globals');

var UserEP = require('./UserEP');
var FileIndexEP = require('./FileIndexEP');
var UploadEP = require('./UploadEP');
var DownloadEP = require('./DownloadEP');
var SharingEP = require('./SharingEP');

// http://stackoverflow.com/questions/4295782/how-do-you-extract-post-data-in-node-js
app.use(bodyParser.json({extended: true}));

var serverPort = 8081;
var serverIPAddress = '0.0.0.0';

// 5/1/16; Changes for running on Heroku. process.env.PORT is an environmental dependency on Heroku. The only Heroku dependency in the server I think.
//if (isDefined(process.env.PORT)) {
//    serverPort = process.env.PORT;
//}

// 7/31/16
// Changes for running on Bluemix.
// https://console.ng.bluemix.net/docs/runtimes/nodejs/index.html#nodejs_runtime

if (isDefined(process.env.VCAP_APP_PORT)) {
    logger.info("Found VCAP_APP_PORT: Assuming that we're running on Bluemix.");

    serverPort = process.env.VCAP_APP_PORT;
    
    if (!isDefined(process.env.VCAP_APP_HOST)) {
        throw("Could not find process.env.VCAP_APP_HOST");
    }
    
    serverIPAddress = process.env.VCAP_APP_HOST;
}

// Server main.
Secrets.load(function (error) {
    assert.equal(null, error);
    
    var mongoDbURL = Secrets.mongoDbURL();
    if (!isDefined(mongoDbURL)) {
        throw new Error("mongoDbURL is not defined!");
    }
    
    Mongo.connect(mongoDbURL);
});

// UserEP
app.post("/" + ServerConstants.operationCreateNewUser, function(request, response) {
    UserEP.createNewUser(request, response);
});

app.post("/" + ServerConstants.operationCheckForExistingUser, function(request, response) {
    UserEP.checkForExistingUser(request, response);
});

// FileIndexEP
app.post('/' + ServerConstants.operationGetFileIndex, function (request, response) {
    FileIndexEP.getFileIndex(request, response);
});

// UploadEP
app.post('/' + ServerConstants.operationUploadFile, function (request, response) {
    UploadEP.uploadFile(request, response);
});

app.post('/' + ServerConstants.operationDeleteFiles, function (request, response) {
    UploadEP.deleteFiles(request, response);
});

app.post('/' + ServerConstants.operationFinishUploads, function (request, response) {
    UploadEP.finishUploads(request, response);
});

// DownloadEP

app.post('/' + ServerConstants.operationDownloadFile, function (request, response) {
    DownloadEP.downloadFile(request, response);
});

// SharingEP
app.post('/' + ServerConstants.operationCreateSharingInvitation, function (request, response) {
    SharingEP.createSharingInvitation(request, response);
});

app.post('/' + ServerConstants.operationLookupSharingInvitation, function (request, response) {
    SharingEP.lookupSharingInvitation(request, response);
});

app.post('/' + ServerConstants.operationRedeemSharingInvitation, function (request, response) {
    SharingEP.redeemSharingInvitation(request, response);
});

app.post('/' + ServerConstants.operationGetLinkedAccountsForSharingUser, function (request, response) {
    SharingEP.getLinkedAccountsForSharingUser(request, response);
});

app.post('/*' , function (request, response) {
    logger.error("Bad Operation URL");
    var op = new Operation(request, response, true);
    op.endWithRC(ServerConstants.rcUndefinedOperation);
});

// Error handling: http://expressjs.com/guide/error-handling.html
app.use(function(err, req, res, next) {
    // TODO: If I get a syntax error in my code will this get called? What I'd like to do is set up an error handler that gets called in the case of syntax errors, and mark the PSOperationId entry as done, but having had an error. Is there a way I can handle exceptions globally and get at least a final block of code executed? Syntax errors seem to throw exceptions.
    logger.error("Error occurred: %j" + JSON.stringify(err));
    var op = new Operation(req, res, true);
    op.endWithErrorDetails(err);
    logger.error(err.stack);
});

app.listen(serverPort, serverIPAddress, function() {
  logger.info('Node app is running on port ' + serverPort);
  logger.info('     with IP address: ' + serverIPAddress);
});


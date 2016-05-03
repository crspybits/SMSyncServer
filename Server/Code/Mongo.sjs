// Some common MongoDb operations and data.

'use strict';

var MongoClient = require('mongodb').MongoClient;
var assert = require('assert');
var logger = require('./Logger');

var connectedDb = null;

// Call this just once, at the start of the server.
// TODO: Need better error handling when can't initially connect. Right now have an ugly looking error when Mongo is not already started and we try to start our server.
exports.connect = function(mongoDbURL) {
	MongoClient.connect(mongoDbURL, function(err, db) {
	  assert.equal(null, err);
	  if (!db) {
	  	logger.error("**** ERROR ****: Cannot connect to MongoDb database!");
	  }
	  else {
	  	connectedDb = db;
	  	logger.info("Connected to MongoDb database");
	  }
	});
};

exports.db = function () {
    return connectedDb;
};

// Call this just once, when the server shuts down.
exports.disconnect = function() {
};
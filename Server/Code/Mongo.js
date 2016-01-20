// Some common MongoDb operations and data.

'use strict';

var MongoClient = require('mongodb').MongoClient;
var assert = require('assert');

var logger = require('./Logger');

const mongoURL = 'mongodb://localhost:27017/test';

var connectedDb = null;

// Call this just once, at the start of the server.
exports.connect = function() {
	MongoClient.connect(mongoURL, function(err, db) {
	  assert.equal(null, err);
	  if (!db) {
	  	logger.error("**** ERROR ****: Cannot connect to MongoDb database!");
	  }
	  else {
	  	connectedDb = db;
	  	logger.info("Connected to MongoDb database at URL: " + mongoURL);
	  }
	});
};

exports.db = function () {
    return connectedDb;
};

// Call this just once, when the server shuts down.
exports.disconnect = function() {
};
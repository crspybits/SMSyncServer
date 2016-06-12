// Some common MongoDb operations and data.

'use strict';

var MongoClient = require('mongodb').MongoClient;
var assert = require('assert');
var logger = require('./Logger');

var mongoose = require('mongoose');
// TODO: Take this out for production.
mongoose.set('debug, true');

var PSSharingInvitations = require('./PSSharingInvitations')

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
            mongoose.connect(mongoDbURL);
            var db = mongoose.connection;
            db.on('error', console.error.bind(console, 'connection error:'));
            db.once('open', function() {
                // SCHEMA's
                exports.SharingInvitation = PSSharingInvitations.buildSchema(mongoose);
                
                logger.info("Mongoose: Connected to MongoDb database");
            });
            
            connectedDb = db;
            logger.info("Mongo: Connected to MongoDb database");
        }
    });
};

exports.db = function () {
    return connectedDb;
};

// Call this just once, when the server shuts down.
exports.disconnect = function() {
};
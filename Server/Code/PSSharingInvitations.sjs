// Persistent Storage for inviting users to share; stored using Mongoose/MongoDb

'use strict';

var logger = require('./Logger');

const modelName = "SharingInvitation";
const collectionName = modelName + "s";

const numberOfHoursBeforeExpiry = 24;

exports.buildSchema = function(mongoose) {
    var Schema = mongoose.Schema;
    var ObjectId = Schema.ObjectId;

    var expiryDate = new Date ();
    expiryDate.setHours(expiryDate.getHours() + numberOfHoursBeforeExpiry);

    var invitationSchema = new Schema({
        // _id: (ObjectId), // Uniquely identifies the invitation (autocreated by Mongo)
        
        // gives time/day that the invitation will expire
        expiry: { type: Date, default: expiryDate },
        
        // The user is being invited to share the following:
        owningUser: ObjectId, // The _id of a PSUserCredentials object.
        capabilities: [String] // capability names
    }, { collection: collectionName });
    
    // The collection parameter above is so I can use camel case in my collection names, as I've been doing already
    // Otherwise, with Mongoose, collection name will be (a) lower case and (b) have an "s" at the end. Odd!
    // http://samwize.com/2014/03/07/what-mongoose-never-explain-to-you-on-case-sentivity/
    // and see http://mongoosejs.com/docs/guide.html#collection
    // and http://stackoverflow.com/questions/18256707/mongoose-doesnt-save-data-to-the-mongodb/37768904#37768904
    
    /*
    // For debugging.
    invitationSchema.pre('save', function(next) {
        logger.trace("'save' pre method called!");
        next();
    });
    */
    
    // The initial string below is the model name, not the collection name. The collection name is assumed to be the same, but with a plural.
    return mongoose.model(modelName, invitationSchema);
}

// For example operations, see http://mongoosejs.com/docs/index.html
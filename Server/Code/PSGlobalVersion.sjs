// Persistent Storage for the global version number for a specific owning users data. This is directly related to the state of the PSFileIndex. This has a single row per owning user.

'use strict';

var logger = require('./Logger');

const modelName = "GlobalVersion";
const collectionName = modelName + "s";

exports.buildSchema = function(mongoose) {
    var Schema = mongoose.Schema;
    var ObjectId = Schema.ObjectId;

    var globalVersionSchema = new Schema({
        // _id: (ObjectId), // Uniquely identifies the global version number (autocreated by Mongo)

		userId: ObjectId, // reference into PSUserCredentials (i.e., _id from PSUserCredentials) for an owning user.
        
        version: {
          type: Number,
          min:  0,
          validate: {
            validator: Number.isInteger,
            message: '{VALUE} is not an integer value'
          }
        }
        
    }, { collection: collectionName });
    
    // The initial string below is the model name, not the collection name. The collection name is assumed to be the same, but with a plural.
    return mongoose.model(modelName, globalVersionSchema);
}

// Persistent Storage for temporarily storing meta data for file uploads and file deletions before finally storing that info in the PSFileIndex. This also represents files that need to be purged from cloud storage-- this will be for losers of PSFileIndex update races and for upload deletions.

'use strict';

var logger = require('./Logger');

const modelName = "Upload";
const collectionName = modelName + "s";

// Values for .state property of the schema. The first three only apply for file-uploads. The last one applies to file-uploads and upload-deletions.
exports.uploadingState = 0;
exports.uploadedState = 1;
exports.toPurgeState = 2;

exports.maxStateValue = exports.toPurgeState;

exports.buildSchema = function(mongoose) {
    var Schema = mongoose.Schema;
    var ObjectId = Schema.ObjectId;

    var uploadsSchema = new Schema({
        // _id: (ObjectId), // Uniquely identifies the upload (autocreated by Mongo)
        
        // Together, these three form a unique key. The deviceId is needed because two devices using the same userId (i.e., the same owning user credentials) could be uploading the same file at the same time.
		fileId: String, // UUID; permanent reference to file, assigned by app
		userId: ObjectId, // reference into PSUserCredentials (i.e., _id from PSUserCredentials)
        deviceId: String, // UUID; identifies a specific mobile device (assigned by app)

        cloudFileName: String, // name of the file in cloud storage excluding the folder path.

        mimeType: String, // MIME type of the file
        appMetaData: Schema.Types.Mixed, // Free-form JSON Structure; App-specific meta data
        
        fileUpload: Boolean, // true if file-upload, false if upload-deletion.
        
        fileVersion: {
          type: Number,
          min:  0,
          validate: {
            validator: Number.isInteger,
            message: '{VALUE} is not an integer value'
          }
        },
        
        state: {
          type: Number,
          min:  0,
          max: exports.maxStateValue,
          validate: {
            validator: Number.isInteger,
            message: '{VALUE} is not an integer value'
          }
        },
        
        fileSizeBytes: {
          type: Number,
          min:  0,
          validate: {
            validator: Number.isInteger,
            message: '{VALUE} is not an integer value'
          }
        }
        
    }, { collection: collectionName });
    
    // The initial string below is the model name, not the collection name. The collection name is assumed to be the same, but with a plural.
    return mongoose.model(modelName, uploadsSchema);
}

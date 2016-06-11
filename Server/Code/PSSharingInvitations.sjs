// Persistent Storage for inviting users to share; stored using MongoDb

'use strict';

var logger = require('./Logger');

/* Data model
	{
		_id: (ObjectId), // Uniquely identifies the invitation
        expiry: (Date), // gives time/day that the invitation will expire
        
        // The user is being invited to share the following:
        owningUser: ObjectId, // The _id of a PSUserCredentials object.
        capabilities: (Array of strings) // capability names
    }
*/


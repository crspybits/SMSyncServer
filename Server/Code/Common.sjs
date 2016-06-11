// Common methods.

'use strict';

var Mongo = require('./Mongo');
var logger = require('./Logger');
var jsonExtras = require('./JSON');

// Not used, but needed to define name "Common".
function Common() {
}

// Checks to make sure that all of the keys used in sourceObj are in the validPropsArray, and assigns them to the destObj, if the destObj is not null. With destObj null this provides a means of validation of the properties in sourceObj.
// Errors: Can throw an Error object.
Common.assignPropsTo = function (destObj, sourceObj, validPropsArray) {
    var usedKeysArray = Object.keys(sourceObj);
    for (var index in usedKeysArray) {
        var key = usedKeysArray[index];
        if (validPropsArray.indexOf(key) == -1) {
            var error = new Error("Bad property in object: " +
                key + "; valid properties: " + JSON.stringify(validPropsArray));
            logger.error(error);
            throw error;
        }
        else if (isDefined(destObj)) {
            destObj[key] = sourceObj[key];
        }
    }
}

// Pulls all the properties (present in propsArray) out of the sourceObj, puts them in a new object, and returns that object.
Common.extractPropsFrom = function (sourceObj, propsArray) {
    var newObj = {};
    
    for (var index in propsArray) {
        var key = propsArray[index];
        if (isDefined(sourceObj[key])) {
            newObj[key] = sourceObj[key];
        }
    }
    
    return newObj;
}

// Just copies over all key/values to new object. Returns that new object.
Common.shallowClone = function (objectToClone) {
    var newObject = {};
    var keysArray = Object.keys(objectToClone);
    for (var index in keysArray) {
        var key = keysArray[index];
        newObject[key] = objectToClone[key];
    }
    
    return newObject;
}

// Looks up a MongoDb object in the given collection based on the instance values. On success the instance has its values populated by the found object.
// Callback parameters: 1) error, 2) if error is null, a boolean indicating if the object could be found. It is an error for more than one object to be found in a query using the instance values.
Common.lookup = function (self, props, mongoCollectionName, callback) {

    var query = Common.extractPropsFrom(self, props);
    query = jsonExtras.flatten(query);
    
	var cursor = Mongo.db().collection(mongoCollectionName).find(query);
		
	if (!cursor) {
		callback(new Error("Failed on find!"));
		return;
	}
		
	// See docs https://mongodb.github.io/node-mongodb-native/api-generated/cursor.html#count
	cursor.count(function (err, count) {
		logger.info("cursor.count: " + count);
		
		if (err) {
            logger.error(err);
			callback(err, null);
		}
		else if (count > 1) {
            var err = new Error("More than one object with those instance values!");
            logger.error(err);
			callback(err, null);
		}
		else if (0 == count) {
			callback(null, false);
		}
		else {
			// Just one matched. We need to get it.
			cursor.nextObject(function (err, doc) {
				if (err) {
                    callback(err, null);
				}
                else {
                    try {
                        Common.assignPropsTo(self, doc, props);
                    } catch (error) {
                        callback(error, null);
                        return;
                    }
                    
                    callback(null, true);
                }
			});
		}
	});
}

// Recursively applies the method to each successive object in arrayToApplyTo. method is assumed to take a single parameter, a callback. The callback is assumed to take a single parameter, error.
// The callback parameter to this apply method is similarly assumed to take a single parameter, error.
Common.applyMethodToEach = function (methodStringName, arrayOfObjsToApplyTo, callback) {
    // Make a copy of the array. applyMethodToEachAux changes it.
    var shallowArrayCopy = arrayOfObjsToApplyTo.slice(0);
    applyMethodToEachAux(methodStringName, shallowArrayCopy, callback);
}

function applyMethodToEachAux(methodStringName, arrayOfObjsToApplyTo, callback) {
    if (arrayOfObjsToApplyTo.length > 0) {
        var firstObj = arrayOfObjsToApplyTo[0];
        firstObj[methodStringName](function (error) {
            if (error) {
                callback(error);
            }
            else {
                // Remove the 0th element from the array. i.e., leaves arrayOfObjsToApplyTo as the tail.
                arrayOfObjsToApplyTo.shift()
                applyMethodToEachAux(methodStringName, arrayOfObjsToApplyTo, callback);
            }
        });
    }
    else {
        // Success!
        callback(null);
    }
}

// Recursively applies the func function to each successive object in arrayToApplyTo. The function is assumed to take two parameters: an element from the array and a callback. The callback is assumed to take a single parameter, error.
// The callback parameter to this apply method is similarly assumed to take a single parameter, error.
Common.applyFunctionToEach = function (func, arrayOfObjsToApplyTo, callback) {
    // Make a copy of the array. applyFunctionToEachAux changes it.
    var shallowArrayCopy = arrayOfObjsToApplyTo.slice(0);
    applyFunctionToEachAux(func, shallowArrayCopy, callback);
}

function applyFunctionToEachAux(func, arrayOfObjsToApplyTo, callback) {
    if (arrayOfObjsToApplyTo.length > 0) {
        var firstObj = arrayOfObjsToApplyTo[0];
        
        func(firstObj, function (error) {
            if (error) {
                callback(error);
            }
            else {
                // Remove the 0th element from the array. i.e., leaves arrayOfObjsToApplyTo as the tail.
                arrayOfObjsToApplyTo.shift()
                applyFunctionToEachAux(func, arrayOfObjsToApplyTo, callback);
            }
        });
    }
    else {
        // Success!
        callback(null);
    }
}

// Removes the doc from collectionName with self._id
// Callback has one parameter: error.
Common.remove = function (self, collectionName, callback) {
    var query = {
        _id: self._id
    };
    
    logger.debug("Removing doc id: " + self._id + " from: " + collectionName);
    
    Mongo.db().collection(collectionName).deleteOne(query,
        function(err, results) {            
            if (err) {
                callback(err);
            }
            else if (0 == results.deletedCount) {
                callback(new Error("Could not remove doc!"));
            }
            else if (results.deletedCount > 1) {
                callback(new Error("Yikes! Removed more than one PSOperationId!"));
            }
            else {
                callback(null);
            }
        });
}

// Store self as a new instance in collectionName. Adds the new _id to self on success.
// Callback has one parameter: error.
Common.storeNew = function (self, collectionName, props, callback) {
    var insertionData = Common.extractPropsFrom(self, props);
    
   	Mongo.db().collection(collectionName).insertOne(insertionData,
   		function(err, result) {
            if (!err) {
                // Get the new _id out of the result
                var newObj = result.ops[0];
                self._id = newObj._id;
            }

    		callback(err);
  		});
}

// Update persistent store from self.
// Callback has one parameter: error.
Common.update = function (self, collectionName, props, callback) {    
    var query = {
        _id: self._id
    };
    
    // Make a clone so that I can remove the _id; don't want to update the _id.
    // Not this though. Bad puppy!!
    // var updatedData = JSON.parse(JSON.stringify(self.idData));
    
    var updatedData = Common.extractPropsFrom(self, props);
    delete updatedData._id;
    
    var updates = {
        $set: updatedData
    };

    logger.debug("updates: %j", updates);

    Mongo.db().collection(collectionName).updateOne(query, updates,
        function(err, results) {
            callback(err);
        });
}

// export the class
module.exports = Common;

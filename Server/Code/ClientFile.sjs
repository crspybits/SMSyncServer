// A data object representing a description of a file from the client/app-- for upload or for deletion.

'use strict';

var logger = require('./Logger');
var Common = require('./Common');
var ServerConstants = require('./ServerConstants');

const requiredProps = [ServerConstants.cloudFileNameKey, ServerConstants.fileUUIDKey, ServerConstants.fileVersionKey, ServerConstants.fileVersionKey, ServerConstants.fileMIMEtypeKey];
var props = requiredProps.slice(0);
props.push(ServerConstants.appFileTypeKey);

// Constructor
// properties in fileData can include other properties not in props.
// Can throw error.
function ClientFile(fileData) {
    var self = this;
    
    var onlyFileDataProps = Common.extractPropsFrom(fileData, props);
    logger.debug("onlyFileDataProps: %j", onlyFileDataProps);
    Common.assignPropsTo(self, onlyFileDataProps, props);
    logger.debug("self: %j", self);

    for (var index in requiredProps) {
        var key = requiredProps[index];
        if (!isDefined(self[key])) {
            throw new Error(key + " was not given for fileData!");
        }
    }
}

// Returns a (possibly zero length) array of ClientFile objects representing the JSON in the fileDataArray.
// Can throw error.
ClientFile.objsFromArray = function (fileDataArray) {
    var result = [];
    
    for (var index in fileDataArray) {
        var fileData = fileDataArray[index];
        var clientFileObj = new ClientFile(fileData);
        result.push(clientFileObj);
    }
    
    return result;
}

// export the class
module.exports = ClientFile;

// Info on files and their folders. Includes local SyncServer info and remote cloud info.

'use strict';

// fileId is optional, but must be given if you want to use the fileNameWithPath function.
/* Optional public member properties can be added later:
    cloudFileName: Name of the file (without path) in the cloud.
    mimeType: MIME type for the file.
    fileReadStream: stream for file
*/
// See [1] below for reason for having deviceId has parameter.
function File(userId, deviceId, fileId) {
    var self = this;
    
    self.userId  = userId;
    self.deviceId = deviceId;
    self.fileId = fileId;
    
    // TODO: UUID's are always letters and character?
    // TODO: Make sure MongoDb default assigned Id's are always letters and characters.
    // TODO: It would be good to lock down the permissions on these directories (and files) the barest minimum.
    
    // Format "uploads/userN.deviceM/" directory name, which will hold the uploads.
    
    // [1]. The reason the subdirectory has both userId and deviceId components (and not just userId) is because, while in normal operation, all we need is the userId, upon failures (e.g., say a series of file transfers to cloud storage fails), we want to be able to restart those file transfers without paying the cost of transferring all the data again from the device to the SyncServer. So, this acts as a temporary directory for this specific userId/deviceId.
    var subDir = self.userId + "." + self.deviceId;
    
    self.dir = __dirname + '/uploads/' + subDir;
}

// The path of the SyncServer upload/download directory for this userId. This can be used for both uploads and downloads because when we have a PSLock, no other devices for this userId can be using this directory.
File.prototype.localDirectoryPath = function() {
    var self = this;
    return self.dir;
}

File.prototype.localFileNameWithPath = function() {
    var self = this;
    
    if (!isDefined(self.fileId)) {
        throw "fileId was not given in constructor!";
    }
    
    return self.dir + "/" + self.fileId;
}

// export the class
module.exports = File;

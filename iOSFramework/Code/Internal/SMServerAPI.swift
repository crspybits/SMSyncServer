//
//  SMSyncServer.swift
//  NetDb
//
//  Created by Christopher Prince on 12/1/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Networking interface to access SyncServer REST API.

// TODO: Can a stale security token from Google Drive be dealt with by doing a silent sign in?

import Foundation
import SMCoreLib

public class SMOperationResult {
    var status:Int!
    var error:String!
    var count:Int!
}

// Describes a file that is present on the local and/or remote systems.
// This inherits from NSObject so I can use the .copy() method.
internal class SMServerFile : NSObject, NSCopying {
    internal var localURL: NSURL?
    
    // This must be unique across all remote files for the cloud user. (Because currently all remote files are required to be in a single remote directory).
    internal var remoteFileName:String!
    
    // TODO: Add MD5 hash of file.
    
    // The UUID is the permanent identifier for the file on the app and SyncServer.
    internal var uuid: NSUUID!
    
    internal var mimeType:String!
    
    // An app-dependent type, so that the app can know, when it downloads a file from the SyncServer, how to process the file. This is optional as the app may or may not want to use it.
    internal var appFileType:String?
    
    // Files newly uploaded to the server (i.e., their UUID doesn't exist yet there) must have version 0. Updated files must have a version equal to +1 of that on the server currently.
    internal var version: Int!
    
    // Used when uploading changes to the SyncServer to keep track of the local file meta data.
    internal var localFile:SMLocalFile?
    
    // Used in a file index reply from the server to indicate the size of the file stored in cloud storage. (Will not be present in all replies, e.g., in a fileChangesRecovery).
    internal var sizeBytes:Int32?
    
    private override init() {
    }
    
    internal init(localURL url:NSURL?, remoteFileName fileName:String, mimeType fileMIMEType:String, appFileType fileType:String?, uuid fileUUID:NSUUID, version fileVersion:Int) {
        self.localURL = url
        self.remoteFileName = fileName
        self.uuid = fileUUID
        self.version = fileVersion
        self.mimeType = fileMIMEType
        self.appFileType = fileType
    }
    
    @objc internal func copyWithZone(zone: NSZone) -> AnyObject {
        let copy = SMServerFile()
        copy.localURL = self.localURL
        copy.remoteFileName = self.remoteFileName
        copy.uuid = self.uuid
        copy.mimeType = self.mimeType
        copy.appFileType = self.appFileType
        copy.version = self.version
        
        // Not creating a copy of localFile because it's a CoreData object and a copy doesn't make sense-- it refers to the same persistent object.
        copy.localFile = self.localFile
        
        copy.sizeBytes = self.sizeBytes
        
        return copy
    }
    
    override internal var description: String {
        get {
            return "localURL: \(self.localURL); remoteFileName: \(self.remoteFileName); uuid: \(self.uuid); version: \(self.version); mimeType: \(self.mimeType); appFileType: \(self.appFileType)"
        }
    }
    
    internal class func create(fromDictionary dict:[String:AnyObject]) -> SMServerFile? {
        let props = [SMServerConstants.fileIndexFileId, SMServerConstants.fileIndexFileVersion, SMServerConstants.fileIndexCloudFileName, SMServerConstants.fileIndexMimeType]
        // Not including SMServerConstants.fileIndexAppFileType as it's optional
    
        for prop in props {
            if (nil == dict[prop]) {
                Log.msg("Didn't have key \(prop) in the dict")
                return nil
            }
        }
        
        let newObj = SMServerFile()
        
        if let cloudName = dict[SMServerConstants.fileIndexCloudFileName] as? String {
            newObj.remoteFileName = cloudName
        }
        else {
            Log.msg("Didn't get a string for cloudName")
            return nil
        }
        
        if let uuid = dict[SMServerConstants.fileIndexFileId] as? String {
            newObj.uuid = NSUUID(UUIDString: uuid)
        }
        else {
            Log.msg("Didn't get a string for uuid")
            return nil
        }
        
        newObj.version = SMServerAPI.getIntFromServerResponse(dict[SMServerConstants.fileIndexFileVersion])
        if nil == newObj.version {
            Log.msg("Didn't get an Int for fileVersion: \(dict[SMServerConstants.fileIndexFileVersion].dynamicType)")
            return nil
        }
        
        if let mimeType = dict[SMServerConstants.fileIndexMimeType] as? String {
            newObj.mimeType = mimeType
        }
        else {
            Log.msg("Didn't get a String for mimeType")
            return nil
        }
        
        if let fileType = dict[SMServerConstants.fileIndexAppFileType] as? String {
            newObj.appFileType = fileType
        }
        else {
            Log.msg("Didn't get a String for appfileType")
        }
        
        let sizeBytes = SMServerAPI.getIntFromServerResponse(dict[SMServerConstants.fileSizeBytes])
        if nil == sizeBytes {
            Log.msg("Didn't get an Int for sizeInBytes: \(dict[SMServerConstants.fileSizeBytes].dynamicType)")
        }
        else {
            newObj.sizeBytes = Int32(sizeBytes!)
        }
        
        return newObj
    }
    
    // Adds all except for localURL.
    internal var dictionary:[String:AnyObject] {
        get {
            var result = [String:AnyObject]()
            
            result[SMServerConstants.fileUUIDKey] = self.uuid.UUIDString
            result[SMServerConstants.fileVersionKey] = self.version
            result[SMServerConstants.cloudFileNameKey] = self.remoteFileName
            result[SMServerConstants.fileMIMEtypeKey] = self.mimeType
            
            if (self.appFileType != nil) {
                result[SMServerConstants.appFileTypeKey] = self.appFileType
            }
            
            return result
        }
    }
}

// http://stackoverflow.com/questions/24051904/how-do-you-add-a-dictionary-of-items-into-another-dictionary
private func += <KeyType, ValueType> (inout left: Dictionary<KeyType, ValueType>, right: Dictionary<KeyType, ValueType>) {
    for (k, v) in right { 
        left.updateValue(v, forKey: k) 
    } 
}

internal class SMServerAPI {
    internal var serverURL:NSURL!
    
    internal var serverURLString:String {
        return serverURL.absoluteString
    }
    
    internal static let session = SMServerAPI()
    
    // Design-wise, it seems better to access a user/credentials delegate in the SMServerAPI class instead of letting this class access the SMSyncServerUser directly. This is because the SMSyncServerUser class needs to call the SMServerAPI interface (to sign a user in or create a new user), and such a direct cyclic dependency seems a poor design.
    internal weak var userDelegate:SMUserServerParamsDelegate!
    
    private init() {
    }

    //MARK: Authentication/user-sign in
    
    // All credentials parameters must be provided by serverCredentialParams.
    internal func createNewUser(serverCredentialParams:[String:AnyObject], completion:((returnCode:Int?, error:NSError?)->(Void))?) {
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCreateNewUser)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverCredentialParams) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            let (returnCode, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            
            completion?(returnCode:returnCode, error: error)
        }
    }
    
    // All credentials parameters must be provided by serverCredentialParams.
    internal func checkForExistingUser(serverCredentialParams:[String:AnyObject], completion:((returnCode:Int?, error:NSError?)->(Void))?) {
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCheckForExistingUser)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverCredentialParams) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            let (returnCode, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            
            completion?(returnCode:returnCode, error: error)
        }
    }

    //MARK: File operations
    
    internal func lock(completion:((error:NSError?)->(Void))?) {
        let serverParams = self.userDelegate.serverParams
        Assert.If(nil == serverParams, thenPrintThisString: "No user server params!")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationLock)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(error: error)
        }
    }
    
    // You must have initiated startFileChanges beforehand.
    // fileToUpload must have a localURL.
    private func uploadFile(fileToUpload: SMServerFile, completion:((returnCode:Int?, error:NSError?)->(Void))?) {
    
        let serverOpURL = NSURL(string: self.serverURLString + "/" + SMServerConstants.operationUploadFile)!
        
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var parameters = userParams!
        parameters += fileToUpload.dictionary
        
        SMServerNetworking.session.uploadFileTo(serverOpURL, fileToUpload: fileToUpload.localURL!, withParameters: parameters) { serverResponse, error in
            let (returnCode, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(returnCode:returnCode, error: error)
        }
    }
    
    // Recursive multiple file upload implementation. If there are no files in the filesToUpload parameter array, this doesn't call the server, and has no effect but calling the completion handler with nil parameters.
    internal func uploadFiles(filesToUpload: [SMServerFile], perUploadCallback:((uuid:NSUUID)->())?, completion:((returnCode:Int?, error:NSError?)->(Void))?) {
        if filesToUpload.count >= 1 {
            self.uploadFilesAux(filesToUpload, perUploadCallback: perUploadCallback, completion: completion)
        }
        else {
            Log.warning("No files to upload")
            completion?(returnCode:nil, error: nil)
        }
    }
    
    // Assumes we've already validated that there is at least one file to upload.
    // TODO: If we get a failure uploading an individual file, retry some MAX number of times.
    private func uploadFilesAux(filesToUpload: [SMServerFile], perUploadCallback:((uuid:NSUUID)->())?, completion:((returnCode:Int?, error:NSError?)->(Void))?) {
        if filesToUpload.count >= 1 {
            let serverFile = filesToUpload[0]
            Log.msg("Uploading file: \(serverFile.localURL)")
            self.uploadFile(serverFile) { returnCode, error in
                if (nil == error) {
                    perUploadCallback?(uuid: serverFile.uuid)
                    let remainingFiles = Array(filesToUpload[1..<filesToUpload.count])
                    self.uploadFilesAux(remainingFiles, perUploadCallback:perUploadCallback, completion: completion)
                }
                else {
                    completion?(returnCode:returnCode, error:error)
                }
            }
        }
        else {
            // The base-case of the recursion: All has completed normally, will have nil parameters for completion.
            completion?(returnCode:nil, error: nil)
        }
    }
    
    // Indicates that a group of files in the cloud should be deleted.
    // You must have initiated startFileChanges beforehand. This does nothing, but calls the callback if filesToDelete is nil or is empty.
    internal func deleteFiles(filesToDelete: [SMServerFile]?, completion:((error:NSError?)->(Void))?) {
    
        if filesToDelete == nil || filesToDelete!.count == 0 {
            completion?(error: nil)
            return
        }
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationDeleteFiles)!
        
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        var serverParams = userParams!
        var deletionServerParam = [AnyObject]()
        
        for serverFile in filesToDelete! {
            let serverFileDict = serverFile.dictionary
            deletionServerParam.append(serverFileDict)
        }
        
        serverParams[SMServerConstants.filesToDeleteKey] = deletionServerParam

        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverParams) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(error: error)
        }
    }
    
    // You must have obtained a lock beforehand, and uploaded/deleted one file after that.
    internal func startOutboundTransfer(completion:((serverOperationId:String?, error:NSError?)->(Void))?) {
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationStartOutboundTransfer)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
                        
            var resultError = error
            let serverOperationId:String? = serverResponse?[SMServerConstants.resultOperationIdKey] as? String
            Log.msg("\(serverOpURL); OperationId: \(serverOperationId)")
            if (nil == resultError && nil == serverOperationId) {
                resultError = Error.Create("No server operationId obtained")
            }
            
            completion?(serverOperationId: serverOperationId, error: resultError)
        }
    }
    
    // On success, the returned SMSyncServerFile objects will have nil localURL members.
    internal func getFileIndex(completion:((fileIndex:[SMServerFile]?, error:NSError?)->(Void))?) {
    
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        Log.msg("parameters: \(userParams)")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationGetFileIndex)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            
            if (error != nil) {
                completion?(fileIndex: nil, error: error)
                return
            }
            
            var errorResult:NSError? = nil
            let fileIndex = self.processFileIndex(serverResponse, error:&errorResult)
            
            if (nil == fileIndex) {
                if (nil == error) {
                    errorResult = Error.Create("No file index was obtained from server")
                }
                completion?(fileIndex: nil, error: errorResult)
            } else {
                completion?(fileIndex: fileIndex, error: nil)
            }
        }
    }
    
    // If there was just no resultFileIndexKey in the server response, a nil file index is returned and error is nil.
    // If the returned file index is not nil, then error will be nil.
    private func processFileIndex(
        serverResponse:[String:AnyObject]?, inout error:NSError?) -> [SMServerFile]? {
    
        Log.msg("\(serverResponse?[SMServerConstants.resultFileIndexKey])")

        var result = [SMServerFile]()
        error = nil

        if let fileIndex = serverResponse?[SMServerConstants.resultFileIndexKey] {
            if let arrayOfDicts = fileIndex as? [[String:AnyObject]] {
                for dict in arrayOfDicts {
                    let newFileMetaData = SMServerFile.create(fromDictionary: dict)
                    if (nil == newFileMetaData) {
                        error = Error.Create("Bad file index object!")
                        return nil
                    }
                    
                    result.append(newFileMetaData!)
                }
                
                return result
            }
            else {
                error = Error.Create("Did not get array of dicts from server")
                return nil
            }
        }
        else {
            return nil
        }
    }
    
    // Call this for an operation that has been successfully committed to see if it has subsequently completed and if it was successful.
    // In the completion closure, operationError refers to a possible error in regards to the operation running on the server. The NSError refers to an error in communication with the server checking the operation status. Only when the NSError is nil can the other two completion handler parameters be non-nil. With a nil NSError, operationStatus will be non-nil.
    internal func checkOperationStatus(serverOperationId operationId:String, completion:((operationResult: SMOperationResult?, error:NSError?)->(Void))?) {
        
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        var parameters = userParams!
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCheckOperationStatus)!
        
        parameters[SMServerConstants.operationIdKey] = operationId
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            if (nil == error) {
                let operationResult = SMOperationResult()
                
                operationResult.status = SMServerAPI.getIntFromServerResponse(serverResponse![SMServerConstants.resultOperationStatusCodeKey])
                if nil == operationResult.status {
                    completion?(operationResult: nil, error: Error.Create("Didn't get an operation status code from server"))
                    return
                }
                
                operationResult.count = SMServerAPI.getIntFromServerResponse(serverResponse![SMServerConstants.resultOperationStatusCountKey])
                if nil == operationResult.count {
                    completion?(operationResult: nil, error: Error.Create("Didn't get an operation status count from server"))
                    return
                }
                
                operationResult.error = serverResponse![SMServerConstants.resultOperationStatusErrorKey] as? String
                
                completion?(operationResult: operationResult, error: nil)
            }
            else {
                completion?(operationResult: nil, error: error)
            }
        }
    }
    
    // The Operation Id is not removed by a call to checkOperationStatus because if that method were to fail, the app would not know if the operation failed or succeeded. Use this to remove the Operation Id from the server.
    internal func removeOperationId(serverOperationId operationId:String, completion:((error:NSError?)->(Void))?) {
    
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var parameters = userParams!
        parameters[SMServerConstants.operationIdKey] = operationId

        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationRemoveOperationId)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(error:error)
        }
    }
    
    // You must have obtained a lock beforehand. The serverOperationId may be returned nil even when there is no error: Just because an operationId has not been generated on the server yet.
    internal func getOperationId(completion:((serverOperationId:String?, error:NSError?)->(Void))?) {
    
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationGetOperationId)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
                        
            let serverOperationId:String? = serverResponse?[SMServerConstants.resultOperationIdKey] as? String
            Log.msg("\(serverOpURL); OperationId: \(serverOperationId)")
            
            completion?(serverOperationId: serverOperationId, error: error)
        }
    }
    
    /* 
    Prepare so that we can recover from an error that occurred *prior* to any files being transferred to cloud storage.
    The input parameter serverOperationId can be given as nil if lock reported failure, but actually did create a lock on the server.
    
    On success, this returns either: 
    
    (1) Both a fileIndex and serverOperationId.
        The fileIndex objects indicate the collection of files that have already been either uploaded or marked for deletion. The lock is still held and the operation Id is still present.
    (2) Neither of these.
        Indicates that recovery can take place by just restarting the upload process. No files have been uploaded/marked for deletion already. No lock is held. No OperationId is present.
    */
    internal func uploadRecovery(completion:((serverOperationId:String?, fileIndex:[SMServerFile]?, error:NSError?)->(Void))?) {
    
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        Log.msg("parameters: \(userParams)")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationUploadRecovery)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            
            if (error != nil) {
                completion?(serverOperationId: nil, fileIndex: nil, error: error)
                return
            }
            
            let serverOperationId:String? = serverResponse?[SMServerConstants.resultOperationIdKey] as? String
            Log.msg("\(serverOpURL); OperationId: \(serverOperationId)")

            var errorResult:NSError? = nil
            let fileIndex = self.processFileIndex(serverResponse, error:&errorResult)
            
            completion?(serverOperationId: serverOperationId, fileIndex: fileIndex, error: errorResult)
        }
    }
 
    // Removes PSOutboundFileChange's, removes the PSLock, and removes the PSOperationId.
    // This is useful for cleaning up in the case of an error/failure during an upload/download operation.
    internal func cleanup(completion:((error:NSError?)->(Void))?) {

        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        Log.msg("parameters: \(userParams)")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCleanup)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(error: error)
        }
    }
    
    internal func outboundTransferRecovery(completion:((error:NSError?)->(Void))?) {

        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        Log.msg("parameters: \(userParams)")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationOutboundTransferRecovery)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(error: error)
        }
    }
    
    internal func startTransferFromCloudStorage(completion:((serverOperationId:String?, error:NSError?)->(Void))?) {
    
        let userParams = self.userDelegate.serverParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationStartInboundTransfer)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            let (_, error) = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var resultError = error
            let serverOperationId:String? = serverResponse?[SMServerConstants.resultOperationIdKey] as? String
            Log.msg("\(serverOpURL); OperationId: \(serverOperationId)")
            if (nil == resultError && nil == serverOperationId) {
                resultError = Error.Create("No server operationId obtained")
            }
            
            completion?(serverOperationId: serverOperationId, error: resultError)
        }
    }
    
    /* Running into an issue here when I try to convert the fileVersion out of the dictionary directly to an Int:
    
    2015-12-10 07:17:32 +0000: [fg0,0,255;Didn't get an Int for fileVersion: Optional<AnyObject>[; [create(fromDictionary:) in SMSyncServer.swift, line 69]
    2015-12-10 07:17:32 +0000: [fg0,0,255;Error: Optional(Error Domain= Code=0 "Bad file index object!" UserInfo={NSLocalizedDescription=Bad file index object!})[; [getFileIndexAction() in Settings.swift, line 82]
    
    Apparently, an Int is not an object in Swift http://stackoverflow.com/questions/25449080/swift-anyobject-is-not-convertible-to-string-int
    And actually, despite the way it looks:
    {
        cloudFileName = "upload.txt";
        deleted = 0;
        fileId = "ADB50CE8-E254-44A0-B8C4-4A3A8240CCB5";
        fileVersion = 8;
        lastModified = "2015-12-09T04:55:05.866Z";
        mimeType = "text/plain";
    }
    fileVersion is really a string in the dictionary. Odd. http://stackoverflow.com/questions/32616309/convert-anyobject-to-an-int
    */
    private class func getIntFromServerResponse(responseValue:AnyObject?) -> Int? {
        // Don't know why but sometimes I'm getting a NSString value back from the server, and sometimes I'm getting an NSNumber value back. Try both.
        
        if let intString = responseValue as? NSString {
            return intString.integerValue
        }
        
        if let intNumber = responseValue as? NSNumber {
            return intNumber.integerValue
        }
        
        return nil
    }
    
    private func initialServerResponseProcessing(serverResponse:[String:AnyObject]?, error:NSError?) -> (returnCode:Int?, error:NSError?) {

        if let rc = serverResponse?[SMServerConstants.resultCodeKey] as? Int {
            if error != nil {
                return (returnCode: rc, error: error)
            }
        
            switch (rc) {
            case SMServerConstants.rcOK:
                return (returnCode: rc, error: nil)
                
            default:
                var message = "Return code value \(rc): "
                
                switch(rc) {
                // 12/12/15; This is a failure of the immediate operation, but in general doesn't necessarily represent an error. E.g., we'll be here if the user already existed on the system when attempting to create a user.
                
                case SMServerConstants.rcStaleUserSecurityInfo:
                    // TODO: How to handle this?
                    // [1]. Perhaps just pass this back up to the caller and assume that they will: (a) do something useful with SMServerCredentials to refresh the stale security info, and (b) use the SMServerAPI to sign in again with the server? Will need to document this assumption too. ALTERNATIVELY, could use a delegate callback to more explicitly phrase this assumption/requirement.
                    break
                    
                case SMServerConstants.rcOperationFailed:
                    message += "Operation failed"
                    
                case SMServerConstants.rcUndefinedOperation:
                    message += "Undefined operation"

                default:
                    message += "Other reason for non-\(SMServerConstants.rcOK) valued return code"
                }
                
                Log.msg(message)
                
                return (returnCode: rc, error: Error.Create("An error occured when doing server operation."))
            }
        }
        else {
            return (returnCode: SMServerConstants.rcInternalError, error: Error.Create("Bad return code value: \(serverResponse?[SMServerConstants.resultCodeKey])"))
        }
    }
}


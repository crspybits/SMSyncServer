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

internal struct SMOperationResult {
    var status:Int!
    var error:String!
    var count:Int!
}

internal struct SMServerAPIResult {
    var returnCode:Int?
    var error: NSError?

    internal init() {
    }
    
    internal init(returnCode:Int?, error:NSError?) {
        self.error = error
        self.returnCode = returnCode
    }
}

// Describes a file that is present on the local and/or remote systems.
// This inherits from NSObject so I can use the .copy() method.
internal class SMServerFile : NSObject, NSCopying, NSCoding {
    
    // The permanent identifier for the file on the app and SyncServer.
    internal var uuid: NSUUID!
    
    internal var localURL: SMRelativeLocalURL?
    
    // This must be unique across all remote files for the cloud user. (Because currently all remote files are required to be in a single remote directory).
    // This optional for the case of transfering files from cloud storage where only a UUID is needed.
    internal var remoteFileName:String?
    
    // TODO: Add MD5 hash of file.

    // This optional for the case of transfering files from cloud storage where only a UUID is needed.
    internal var mimeType:String?
    
    // App-dependent meta data, e.g., so that the app can know, when it downloads a file from the SyncServer, how to process the file. This is optional as the app may or may not want to use it.
    internal var appMetaData:SMAppMetaData?
    
    // Files newly uploaded to the server (i.e., their UUID doesn't exist yet there) must have version 0. Updated files must have a version equal to +1 of that on the server currently.
    // This optional for the case of transfering files from cloud storage where only a UUID is needed.
    internal var version: Int?
    
    // Used when uploading changes to the SyncServer to keep track of the local file meta data.
    internal var localFile:SMLocalFile?
    
    // Used in a file index reply from the server to indicate the size of the file stored in cloud storage. (Will not be present in all replies, e.g., in a fileChangesRecovery).
    internal var sizeBytes:Int?
    
    // Indicates whether or not the file has been deleted on the server.
    internal var deleted:Bool?
    
    // To deal with conflict resolution. Leave this as nil if you don't want undeletion. Set to true if you do want undeletion.
    internal var undeleteServerFile:Bool?
    
    private override init() {
    }
    
    // Does not initialize localURL.
    internal init(uuid fileUUID:NSUUID, remoteFileName fileName:String?=nil, mimeType fileMIMEType:String?=nil, appMetaData:SMAppMetaData?=nil, version fileVersion:Int?=nil) {
        self.remoteFileName = fileName
        self.uuid = fileUUID
        self.version = fileVersion
        self.mimeType = fileMIMEType
        self.appMetaData = appMetaData
    }
    
    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(self.uuid, forKey: "uuid")
        aCoder.encodeObject(self.localURL, forKey: "localURL")
        aCoder.encodeObject(self.remoteFileName, forKey: "remoteFileName")
        aCoder.encodeObject(self.mimeType, forKey: "mimeType")
        
        // Since the appMetaData is JSON serializable, it should be encodable, right?
        aCoder.encodeObject(self.appMetaData, forKey: "appMetaData")
        
        aCoder.encodeObject(self.version, forKey: "version")
        aCoder.encodeObject(self.sizeBytes, forKey: "sizeBytes")
        aCoder.encodeObject(self.deleted, forKey: "deleted")
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init()
        
        self.uuid = aDecoder.decodeObjectForKey("uuid") as? NSUUID
        self.localURL = aDecoder.decodeObjectForKey("localURL") as? SMRelativeLocalURL
        self.remoteFileName = aDecoder.decodeObjectForKey("remoteFileName") as? String
        self.mimeType = aDecoder.decodeObjectForKey("mimeType") as? String
        self.appMetaData = aDecoder.decodeObjectForKey("appMetaData") as? [String:AnyObject]
        self.version = aDecoder.decodeObjectForKey("version") as? Int
        self.sizeBytes = aDecoder.decodeObjectForKey("sizeBytes") as? Int
        self.deleted = aDecoder.decodeObjectForKey("deleted") as? Bool
    }
    
    @objc internal func copyWithZone(zone: NSZone) -> AnyObject {
        let copy = SMServerFile()
        copy.localURL = self.localURL
        copy.remoteFileName = self.remoteFileName
        copy.uuid = self.uuid
        copy.mimeType = self.mimeType
        
        // This is not a deep copy.
        copy.appMetaData = self.appMetaData
        
        copy.version = self.version
        
        // Not creating a copy of localFile because it's a CoreData object and a copy doesn't make sense-- it refers to the same persistent object.
        copy.localFile = self.localFile
        
        copy.sizeBytes = self.sizeBytes
        
        return copy
    }
    
    override internal var description: String {
        get {
            return "localURL: \(self.localURL); remoteFileName: \(self.remoteFileName); uuid: \(self.uuid); version: \(self.version); mimeType: \(self.mimeType); appFileType: \(self.appMetaData)"
        }
    }
    
    internal class func create(fromDictionary dict:[String:AnyObject]) -> SMServerFile? {
        let props = [SMServerConstants.fileIndexFileId, SMServerConstants.fileIndexFileVersion, SMServerConstants.fileIndexCloudFileName, SMServerConstants.fileIndexMimeType, SMServerConstants.fileIndexDeleted]
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
        
        newObj.version = SMExtras.getIntFromDictValue(dict[SMServerConstants.fileIndexFileVersion])
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
        
        let fileDeleted = SMExtras.getIntFromDictValue(dict[SMServerConstants.fileIndexDeleted])
        if nil == fileDeleted {
            Log.msg("Didn't get an Int for fileDeleted: \(dict[SMServerConstants.fileIndexDeleted].dynamicType)")
            return nil
        }
        else {
            newObj.deleted = Bool(fileDeleted!)
        }
        
        if let appMetaData = dict[SMServerConstants.fileIndexAppMetaData] as? SMAppMetaData {
            newObj.appMetaData = appMetaData
        }
        else {
            Log.msg("Didn't get JSON for appMetaData")
        }
        
        let sizeBytes = SMExtras.getIntFromDictValue(dict[SMServerConstants.fileSizeBytes])
        if nil == sizeBytes {
            Log.msg("Didn't get an Int for sizeInBytes: \(dict[SMServerConstants.fileSizeBytes].dynamicType)")
        }
        else {
            newObj.sizeBytes = sizeBytes!
        }
        
        return newObj
    }
    
    // Adds all except for localURL.
    internal var dictionary:[String:AnyObject] {
        get {
            var result = [String:AnyObject]()
            
            result[SMServerConstants.fileUUIDKey] = self.uuid.UUIDString
            
            if self.version != nil {
                result[SMServerConstants.fileVersionKey] = self.version
            }
            
            if self.remoteFileName != nil {
                result[SMServerConstants.cloudFileNameKey] = self.remoteFileName
            }
            
            if self.mimeType != nil {
                result[SMServerConstants.fileMIMEtypeKey] = self.mimeType
            }
            
            if self.appMetaData != nil {
                result[SMServerConstants.appMetaDataKey] = self.appMetaData
            }
            
            return result
        }
    }
    
    class func getFile(fromFiles files:[SMServerFile]?, withUUID uuid: NSUUID) -> SMServerFile? {
        if nil == files || files?.count == 0  {
            return nil
        }
        
        let result = files?.filter({$0.uuid.isEqual(uuid)})
        if result!.count > 0 {
            return result![0]
        }
        else {
            return nil
        }
    }
}

internal protocol SMServerAPIUploadDelegate : class {
    func smServerAPIFileUploaded(serverFile: SMServerFile)
}

internal protocol SMServerAPIDownloadDelegate : class {
    func smServerAPIFileDownloaded(file: SMServerFile)
}

// http://stackoverflow.com/questions/24051904/how-do-you-add-a-dictionary-of-items-into-another-dictionary
internal func += <KeyType, ValueType> (inout left: Dictionary<KeyType, ValueType>, right: Dictionary<KeyType, ValueType>) {
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
    internal weak var userDelegate:SMServerAPIUserDelegate!
    
    internal weak var uploadDelegate: SMServerAPIUploadDelegate?
    internal weak var downloadDelegate: SMServerAPIDownloadDelegate?
    
    private init() {
    }

    //MARK: Authentication/user-sign in
    
    // All credentials parameters must be provided by serverCredentialParams.
    internal func createNewUser(serverCredentialParams:[String:AnyObject], completion:((internalUserId:SMInternalUserId?, apiResult:SMServerAPIResult)->(Void))?) {
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCreateNewUser)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverCredentialParams) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var internalUserId:SMInternalUserId?
            if nil == result.error {
                internalUserId = serverResponse![SMServerConstants.internalUserId] as? String
                if nil == internalUserId {
                    result.error = Error.Create("Didn't get InternalUserId back from server")
                }
            }
            
            completion?(internalUserId: internalUserId, apiResult: result)
        }
    }
    
    // All credentials parameters must be provided by serverCredentialParams.
    internal func checkForExistingUser(serverCredentialParams:[String:AnyObject], completion:((internalUserId:String?, apiResult:SMServerAPIResult)->(Void))?) {
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCheckForExistingUser)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverCredentialParams) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var internalUserId:String?
            if nil == result.error {
                internalUserId = serverResponse![SMServerConstants.internalUserId] as? String
                if nil == internalUserId && SMServerConstants.rcUserOnSystem == result.returnCode {
                    result.error = Error.Create("Didn't get InternalUserId back from server")
                }
            }
            
            completion?(internalUserId: internalUserId, apiResult: result)
        }
    }

    //MARK: File operations

    // On success, the returned SMSyncServerFile objects will have nil localURL members.
    internal func getFileIndex(completion:((fileIndex:[SMServerFile]?, fileIndexVersion:Int?, apiResult:SMServerAPIResult)->(Void))?) {
    
        var params = self.userDelegate.userCredentialParams
        Assert.If(nil == params, thenPrintThisString: "No user server params!")
        Log.msg("parameters: \(params)")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationGetFileIndex)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: params!) { (serverResponse:[String:AnyObject]?, requestError:NSError?) in
        
            let result = self.initialServerResponseProcessing(serverResponse, error: requestError)
            
            if (result.error != nil) {
                completion?(fileIndex: nil, fileIndexVersion:nil, apiResult:result)
                return
            }
            
            var errorResult:NSError? = nil
            var fileIndexVersion:Int?
            let fileIndex = self.processFileIndex(serverResponse, error:&errorResult)
            
            if (nil == fileIndex && nil == errorResult) {
                errorResult = Error.Create("No file index was obtained from server")
            }
            
            if errorResult == nil {
                fileIndexVersion = serverResponse?[SMServerConstants.fileIndexVersionKey] as? Int
                if fileIndexVersion == nil {
                    errorResult = Error.Create("No file index version obtained from server")
                }
            }
            
            completion?(fileIndex: fileIndex,  fileIndexVersion: fileIndexVersion, apiResult:SMServerAPIResult(returnCode: result.returnCode, error: errorResult))
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
    // Does not require a server lock be held before the call.
    internal func checkOperationStatus(serverOperationId operationId:String, completion:((operationResult: SMOperationResult?, apiResult:SMServerAPIResult)->(Void))?) {
        
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        var parameters = userParams!
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCheckOperationStatus)!
        
        parameters[SMServerConstants.operationIdKey] = operationId
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, requestError:NSError?) in
            let result = self.initialServerResponseProcessing(serverResponse, error: requestError)
            if (nil == result.error) {
                var operationResult = SMOperationResult()
                
                operationResult.status = SMExtras.getIntFromDictValue(serverResponse![SMServerConstants.resultOperationStatusCodeKey])
                if nil == operationResult.status {
                    completion?(operationResult: nil, apiResult:SMServerAPIResult(returnCode: result.returnCode, error: Error.Create("Didn't get an operation status code from server")))
                    return
                }
                
                operationResult.count = SMExtras.getIntFromDictValue(serverResponse![SMServerConstants.resultOperationStatusCountKey])
                if nil == operationResult.count {
                    completion?(operationResult: nil, apiResult:SMServerAPIResult(returnCode: result.returnCode, error: Error.Create("Didn't get an operation status count from server")))
                    return
                }
                
                operationResult.error = serverResponse![SMServerConstants.resultOperationStatusErrorKey] as? String
                
                completion?(operationResult: operationResult, apiResult:result)
            }
            else {
                completion?(operationResult: nil, apiResult:result)
            }
        }
    }
    
    // The Operation Id is not removed by a call to checkOperationStatus because if that method were to fail, the app would not know if the operation failed or succeeded. Use this to remove the Operation Id from the server.
    internal func removeOperationId(serverOperationId operationId:String, completion:((apiResult:SMServerAPIResult)->(Void))?) {
    
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var parameters = userParams!
        parameters[SMServerConstants.operationIdKey] = operationId

        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationRemoveOperationId)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let result = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(apiResult: result)
        }
    }
    
    // You must have obtained a lock beforehand. The serverOperationId may be returned nil even when there is no error: Just because an operationId has not been generated on the server yet.
    internal func getOperationId(completion:((serverOperationId:String?, apiResult:SMServerAPIResult)->(Void))?) {
    
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationGetOperationId)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let result = self.initialServerResponseProcessing(serverResponse, error: error)
                        
            let serverOperationId:String? = serverResponse?[SMServerConstants.resultOperationIdKey] as? String
            Log.msg("\(serverOpURL); OperationId: \(serverOperationId)")
            
            completion?(serverOperationId: serverOperationId, apiResult:result)
        }
    }
 
    // You must have the server lock before calling.
    // Removes PSOutboundFileChange's, removes the PSLock, and removes the PSOperationId.
    // This is useful for cleaning up in the case of an error/failure during an upload/download operation.
    internal func cleanup(completion:((apiResult:SMServerAPIResult)->(Void))?) {

        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")

        Log.msg("parameters: \(userParams)")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCleanup)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            let result = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(apiResult: result)
        }
    }

    // Must have server lock.
    internal func setupInboundTransfer(filesToTransfer: [SMServerFile], completion:((apiResult:SMServerAPIResult)->(Void))?) {
    
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var serverParams = userParams!
        var fileTransferServerParam = [AnyObject]()
        
        for serverFile in filesToTransfer {
            let serverFileDict = serverFile.dictionary
            fileTransferServerParam.append(serverFileDict)
        }
        
        serverParams[SMServerConstants.filesToTransferFromCloudStorageKey] = fileTransferServerParam
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationSetupInboundTransfers)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverParams) { (serverResponse:[String:AnyObject]?, requestError:NSError?) in
            let result = self.initialServerResponseProcessing(serverResponse, error: requestError)
            completion?(apiResult: result)
        }
    }
    
    // Must have server lock or operationId.
    internal func startInboundTransfer(completion:((serverOperationId:String?, apiResult:SMServerAPIResult)->(Void))?) {
    
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationStartInboundTransfer)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, requestError:NSError?) in
        
            var result = self.initialServerResponseProcessing(serverResponse, error: requestError)
            
            let serverOperationId:String? = serverResponse?[SMServerConstants.resultOperationIdKey] as? String
            Log.msg("\(serverOpURL); OperationId: \(serverOperationId)")
            if (nil == result.error && nil == serverOperationId) {
                result.error = Error.Create("No server operationId obtained")
            }
            
            completion?(serverOperationId: serverOperationId, apiResult:result)
        }
    }
    
    internal func inboundTransferRecovery(
        completion:((serverOperationId:String?, apiResult:SMServerAPIResult)->(Void))?) {

        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        Log.msg("parameters: \(userParams)")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationInboundTransferRecovery)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            let serverOperationId:String? = serverResponse?[SMServerConstants.resultOperationIdKey] as? String
            Log.msg("\(serverOpURL); OperationId: \(serverOperationId)")
            if (nil == result.error && nil == serverOperationId) {
                result.error = Error.Create("No server operationId obtained")
            }
            
            completion?(serverOperationId:serverOperationId, apiResult: result)
        }
    }
    
    // Aside from testing, we're only using this method inside of this class. Use downloadFiles() for non-testing.
    // File will be downloaded to fileToDownload.localURL (which is required). (No other SMServerFile attributes are required, except, of course for the uuid).
    internal func downloadFile(fileToDownload: SMServerFile, completion:((apiResult:SMServerAPIResult)->(Void))?) {

        Assert.If(fileToDownload.localURL == nil, thenPrintThisString: "Didn't give localURL with file")
        
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var serverParams = userParams!
        let serverFileDict = fileToDownload.dictionary
        serverParams[SMServerConstants.downloadFileAttributes] = serverFileDict
        
        Log.msg("parameters: \(serverParams)")

        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationDownloadFile)!
        
        SMServerNetworking.session.downloadFileFrom(serverOpURL, fileToDownload: fileToDownload.localURL!, withParameters: serverParams) { (serverResponse, error) in
        
            let result = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(apiResult: result)
        }
    }
    
    // Recursive multiple file download implementation. If there are no files in the filesToDownload parameter array, this doesn't call the server, and has no effect but to give a SMServerAPIResult callback.
    internal func downloadFiles(filesToDownload: [SMServerFile], completion:((apiResult:SMServerAPIResult)->(Void))?) {
        if filesToDownload.count >= 1 {
            self.downloadFilesAux(filesToDownload, completion: completion)
        }
        else {
            Log.warning("No files to download")
            completion?(apiResult: SMServerAPIResult(returnCode: nil, error: nil))
        }
    }
    
    // Assumes we've already validated that there is at least one file to download.
    // TODO: If we get a failure download an individual file, retry some MAX number of times.
    private func downloadFilesAux(filesToDownload: [SMServerFile], completion:((apiResult:SMServerAPIResult)->(Void))?) {
        if filesToDownload.count >= 1 {
            let serverFile = filesToDownload[0]
            Log.msg("Downloading file: \(serverFile.localURL)")
            self.downloadFile(serverFile) { downloadResult in
                if (nil == downloadResult.error) {
                    // I'm going to remove the downloaded file from the server immediately after a successful download. Partly, this is so I don't have to push the call to this SMServerAPI method higher up; partly this is an optimization-- so that we can release temporary file storage on the server more quickly.
                    
                    self.removeDownloadFile(serverFile) { removeResult in
                        if removeResult.error == nil {
                            // 3/26/16; Wait until after the file is removed before reporting the download event. This is because internally, in smServerAPIFileDownloaded, we're removing the file from our list of files to download-- and we want to make sure the file gets removed from the server.
                            self.downloadDelegate?.smServerAPIFileDownloaded(serverFile)
                            
                            let remainingFiles = Array(filesToDownload[1..<filesToDownload.count])
                            self.downloadFilesAux(remainingFiles, completion: completion)
                        }
                        else {
                            completion?(apiResult: removeResult)
                        }
                    }
                }
                else {
                    completion?(apiResult: downloadResult)
                }
            }
        }
        else {
            // The base-case of the recursion: All has completed normally, will have nil parameters for completion.
            completion?(apiResult: SMServerAPIResult(returnCode: nil, error: nil))
        }
    }
    
    // Remove the temporary downloadable file from the server. (Doesn't remove the info from the file index).
    // I'm not going to expose this method outside of this class-- we'll just do this removal internally, after a download.
    private func removeDownloadFile(fileToRemove: SMServerFile, completion:((apiResult:SMServerAPIResult)->(Void))?) {
        
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var serverParams = userParams!
        let serverFileDict = fileToRemove.dictionary
        serverParams[SMServerConstants.downloadFileAttributes] = serverFileDict
        
        Log.msg("parameters: \(serverParams)")

        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationRemoveDownloadFile)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: serverParams) { (serverResponse, error) in
        
            let result = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(apiResult: result)
        }
    }
    
    // Previously, I had this marked as "private". However, it was convenient to add extensions for additional ServerAPI functionality. This method is not intended for callers outside of the SMServerAPI.
    internal func initialServerResponseProcessing(serverResponse:[String:AnyObject]?, error:NSError?) -> SMServerAPIResult {
        
        if let rc = serverResponse?[SMServerConstants.resultCodeKey] as? Int {
            if error != nil {
                return SMServerAPIResult(returnCode: rc, error: error)
            }
        
            switch (rc) {
            case SMServerConstants.rcOK:
                return SMServerAPIResult(returnCode: rc, error: nil)
                
            default:
                var message = "Return code value \(rc): "
                
                switch(rc) {
                // 12/12/15; This is a failure of the immediate operation, but in general doesn't necessarily represent an error. E.g., we'll be here if the user already existed on the system when attempting to create a user.
                
                case SMServerConstants.rcStaleUserSecurityInfo:
                    // In the case of Google API creds, I believe this will kick off a network request to refresh the creds. We might get a second request to refresh quickly following on this (i.e., a second rcStaleUserSecurityInfo from the server) -- because of our recovery attempt. BUT-- we do exponential fallback with the recovery, so perhaps our delays will be enough to let the refresh occur first.
                    self.userDelegate.refreshUserCredentials()
                    
                case SMServerConstants.rcOperationFailed:
                    message += "Operation failed"
                    
                case SMServerConstants.rcUndefinedOperation:
                    message += "Undefined operation"

                default:
                    message += "Other reason for non-\(SMServerConstants.rcOK) valued return code"
                }
                
                Log.msg(message)
                return SMServerAPIResult(returnCode: rc, error: Error.Create("An error occurred when doing server operation."))
            }
        }
        else {
            return SMServerAPIResult(returnCode: SMServerConstants.rcInternalError, error: Error.Create("Bad return code value: \(serverResponse?[SMServerConstants.resultCodeKey])"))
        }
    }
}

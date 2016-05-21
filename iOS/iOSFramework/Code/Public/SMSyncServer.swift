// TODO: When initiating a batch of uploads, e.g., when deploying the SyncServer for the first time to users, we may want to make an overt user interface that asks the users to wait while data is synced with the server. And give them some kind of progress indication so they know how long they will wait.

//
//  SMSyncServer.swift
//  NetDb
//
//  Created by Christopher Prince on 12/27/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// The client/app facing interface to the SyncServer for uploading, deleting, and downloading files.

import Foundation
import SMCoreLib

public class SMSyncAttributes {
    // The identifier for the file/data item.
    public var uuid:NSUUID!
    
    // Must be provided when uploading for a new uuid. (If you give a remoteFileName for an existing uuid it *must* match that already present in cloud storage). Will be provided when a file is downloaded from the server.
    public var remoteFileName:String?
    
    // Must be provided when uploading for a new uuid; optional after that.
    public var mimeType:String?
    
    // TODO: Optionally provides the app with some app-specific type information about the file.
    public var appFileType:String?
    
    // Only used by SMSyncServer fileStatus method. true indicates that the file was deleted on the server.
    public var deleted:Bool?
    
    // TODO: An optional app-specific identifier for a logical group or category that the file/data item belongs to. The intent behind this identifier is to make downloading logical groups of files easier. E.g., so that not all changed files need to be downloaded at once.
    //public var appGroupId:NSUUID?
    
    public init(withUUID id:NSUUID) {
        self.uuid = id
    }
    
    public init(withUUID theUUID:NSUUID, mimeType theMimeType:String, andRemoteFileName theRemoteFileName:String) {
        self.mimeType = theMimeType
        self.uuid = theUUID
        self.remoteFileName = theRemoteFileName
    }
}

// MARK: Events

public enum SMSyncServerEvent {
    // Deletion operations have been sent to the SyncServer. All pending deletion operations are sent as a group. Deletion of the file from cloud storage hasn't yet occurred.
    case DeletionsSent(uuids:[NSUUID])
    
    // A single file/item has been uploaded to the SyncServer. Transfer of the file to cloud storage hasn't yet occurred.
    case SingleUploadComplete(uuid:NSUUID)
    
    // As said elsewhere, this information is for debugging/testing. The url/attr here may not be consistent with the atomic/transaction-maintained results from syncServerDownloadsComplete in the SMSyncServerDelegate method. (Because of possible recovery steps).
    case SingleDownloadComplete(url:SMRelativeLocalURL, attr:SMSyncAttributes)
    
    // Server has finished performing the outbound transfers of files to cloud storage/deletions to cloud storage. numberOperations is a heuristic value that includes upload and deletion operations. It is heuristic in that it includes retries if retries occurred due to error/recovery handling. We used to call this the "committed" or "CommitComplete" event because the SMSyncServer commit operation was done at this point.
    case OutboundTransferComplete(numberOperations:Int?)
    
    // Similarly, for inbound transfers of files from cloud storage to the sync server. The numberOperations value has the same heuristic meaning.
    case InboundTransferComplete(numberOperations:Int?)
    
    // The client polled the server and found that there were no files available to download or files that needed deletion.
    case NoFilesToDownload

    // Commit was called, but there were no files to upload and no upload-deletions to send to the server.
    case NoFilesToUpload
    
    // Attempted to do an operation but a lock was already held. This can occur both at the local app level and with the server lock.
    case LockAlreadyHeld
    
    // Internal error recovery event.
    case Recovery
}

// MARK: Conflict management

// If you receive a non-nil conflict in a callback method, you must resolve the conflict by calling resolveConflict.
public class SMSyncServerConflict {
    internal typealias callbackType = ((resolution:ResolutionType)->())!
    
    internal var conflictResolved:Bool = false
    internal var resolutionCallback:((resolution:ResolutionType)->())!
    
    internal init(conflictType: ClientOperation, resolutionCallback:callbackType) {
        self.conflictType = conflictType
        self.resolutionCallback = resolutionCallback
    }
    
    // Because downloads are higher-priority (than uploads) with the SMSyncServer, all conflicts effectively originate from a server download operation: A download-deletion or a file-download. The type of server operation will be apparent from the context.
    // And the conflict is between the server operation and a local, client operation:
    public enum ClientOperation : String {
        case UploadDeletion
        case FileUpload
    }
    
    public var conflictType:ClientOperation!
    
    public enum ResolutionType {
        // E.g., suppose a download-deletion and a file-upload (ClientOperation.FileUpload) are conflicting.
        // Example continued: The client chooses to delete the conflicting file-upload and accept the download-deletion by using this resolution.
        case DeleteConflictingClientOperations
        
        // Example continued: The client chooses to keep the conflicting file-upload, and override the download-deletion, by using this resolution.
        case KeepConflictingClientOperations
    }
    
    public func resolveConflict(resolution resolution:ResolutionType) {
        Assert.If(self.conflictResolved, thenPrintThisString: "Already resolved!")
        self.conflictResolved = true
        self.resolutionCallback(resolution: resolution)
    }
}

// MARK: Delegate

// These delegate methods are called on the main thread.
public protocol SMSyncServerDelegate : class {
    // "class" to make the delegate weak.

    // For all four of the following delegate callbacks, it is up to the callee to check to determine if any modification conflict is occuring for a particular deleted file. i.e., if the client is modifying any of the files referenced.
    
    // Called at the end of all downloads, on non-error conditions. Only called when there was at least one download.
    // The callee owns the files referenced by the NSURL's after this call completes. These files are temporary in the sense that they will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location. See [1] for a design note about this delegate method. This is received/called in an atomic manner: This reflects the current state of files on the server.
    // The recommended action is for the client to replace their existing data with that from the files.
    // The callee must call the acknowledgement callback when it has finished dealing with (e.g., persisting) the list of downloaded files.
    // For any given download only one of the following two delegate methods will be called. I.e., either there is a conflict or is not a conflict for a given download.
    func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement: () -> ())
    
    // The client has to decide how to resolve the file-download conflicts. The resolveConflict method of each SMSyncServerConflict must be called. The above statements apply for the NSURL's.
    func syncServerShouldResolveDownloadConflicts(conflicts: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)])
    
    // Called when deletion indications have been received from the server. I.e., these files have been deleted on the server. This is received/called in an atomic manner: This reflects a snapshot state of files on the server. The recommended action is for the client to delete the files represented by the UUID's.
    // The callee must call the acknowledgement callback when it has finished dealing with (e.g., carrying out deletions for) the list of deleted files.
    func syncServerShouldDoDeletions(downloadDeletions downloadDeletions:[NSUUID], acknowledgement:()->())

    // The client has to decide how to resolve the download-deletion conflicts. The resolveConflict method of each SMSyncServerConflict must be called.
    // Conflicts will not include UploadDeletion.
    func syncServerShouldResolveDeletionConflicts(conflicts:[(downloadDeletion: NSUUID, uploadConflict: SMSyncServerConflict)])
    
    // Reports mode changes including errors. Can be useful for presenting a graphical user-interface which indicates ongoing server/networking operations. E.g., so that the user doesn't close or otherwise the dismiss a client app until server operations have completed.
    func syncServerModeChange(newMode:SMSyncServerMode)
    
    // Reports events. Useful for testing and debugging.
    func syncServerEventOccurred(event:SMSyncServerEvent)
}

// Derived from NSObject because of the use of addTarget from TargetsAndSelectors below.
public class SMSyncServer : NSObject {
    private var _autoCommit = false
    private var _autoCommitIntervalSeconds:Float = 30
        
    // Timer for .Normal mode when doing autoCommit.
    private var normalTimer:TimedCallback?
    
    // Maximum amount of data individually uploaded and downloaded
    internal static let BLOCK_SIZE_BYTES:UInt = 1024 * 100
    
    // This is a singleton because we need centralized control over the file upload/download operations.
    public static let session = SMSyncServer()

    // This delegate is optional because, while usually important for caller operation, the SMSyncServer itself isn't really dependent on the operation of the delegate methods assuming correct operation of the caller.
    public weak var delegate:SMSyncServerDelegate? {
        set {
            SMUploadFiles.session.syncServerDelegate = newValue
            SMDownloadFiles.session.syncServerDelegate = newValue
            SMSyncControl.session.delegate = newValue
        }
        get {
            return SMUploadFiles.session.syncServerDelegate
        }
    }

    // If autoCommit is true, then this is the interval that changes are automatically committed. The interval is timed from the last change enqueued with this class. If no changes are queued, then no commit is done.
    public var autoCommitIntervalSeconds:Float {
        set {
            if newValue < 0 {
                self.callSyncServerModeChange(.NonRecoverableError(Error.Create("Yikes: Bad autoCommitIntervalSeconds")))
            }
            else {
                _autoCommitIntervalSeconds = newValue
                self.startNormalTimer()
            }
        }
        get {
            return _autoCommitIntervalSeconds
        }
    }
    
    // Set this to false if you want to call commit yourself, and true if you want to automatically periodically commit. Default is false.
    public var autoCommit:Bool {
        set {
            _autoCommit = newValue
            
            switch self.mode {
            case .Idle:
                self.startNormalTimer()
            default:
                break
            }
        }
        get {
            return _autoCommit
        }
    }
    
    private func startNormalTimer() {
        switch self.mode {
        case .Idle:
            return
        default:
            break
        }
        
        self.normalTimer?.cancel()

        if (self.autoCommit) {
            self.normalTimer = TimedCallback(duration: _autoCommitIntervalSeconds) {
                self.commit()
            }
        }
    }
    
    private func setMode(mode:SMSyncServerMode) {
        SMSyncControl.session.mode = mode
    }
    
    public var mode:SMSyncServerMode {
        return SMSyncControl.session.mode
    }
    
    // Only retains a weak reference to the cloudStorageUserDelegate
    public func appLaunchSetup(withServerURL serverURL: NSURL, andCloudStorageUserDelegate cloudStorageUserDelegate:SMCloudStorageUserDelegate) {

        Network.session().appStartup()
        SMServerNetworking.session.appLaunchSetup()
        SMServerAPI.session.serverURL = serverURL
        SMUploadFiles.session.appLaunchSetup()
        SMDownloadFiles.session.appLaunchSetup()

        // This seems a little hacky, but can't find a better way to get the bundle of the framework containing our model. I.e., "this" framework. Just using a Core Data object contained in this framework to track it down.
        // Without providing this bundle reference, I wasn't able to dynamically locate the model contained in the framework.
        let bundle = NSBundle(forClass: NSClassFromString(SMLocalFile.entityName())!)
        
        let coreDataSession = CoreData(namesDictionary: [
            CoreDataModelBundle: bundle,
            CoreDataBundleModelName: "SMSyncServerModel",
            CoreDataSqlliteBackupFileName: "~SMSyncServerModel.sqlite",
            CoreDataSqlliteFileName: "SMSyncServerModel.sqlite"
        ]);
        
        CoreData.registerSession(coreDataSession, forName: SMCoreData.name)
                
        // Do this before SMSyncServerUser.session.appLaunchSetup, which will lead to signing a user in.
        SMSyncServerUser.session.signInProcessCompleted.addTarget!(self, withSelector: #selector(SMSyncServer.signInCompletedAction))
        
        SMSyncServerUser.session.appLaunchSetup(withCloudStorageUserDelegate: cloudStorageUserDelegate)
    }
    
    // PRIVATE
    internal func signInCompletedAction() {
        Log.msg("signInCompletedAction")
        
        // TODO: Right now this is being called after sign in is completed. That seems good. But what about the app going into the background and coming into the foreground? This can cause a server API operation to fail, and we should initiate recovery at that point too.
        SMSyncControl.session.nextSyncOperation()
        
        // Leave this until now, i.e., until after sign-in, so we don't start any recovery process until after sign-in.
        Network.session().connectionStateCallbacks.addTarget!(self, withSelector: #selector(SMSyncServer.networkConnectionStateChangeAction))
    }
    
    // PRIVATE
    internal func networkConnectionStateChangeAction() {
        if Network.session().connected() {
            SMSyncControl.session.nextSyncOperation()
        }
    }
    
    // Returns a SMSyncAttributes object iff the file is locally known (on the device) to the SMSyncServer. Nil could be returned if the file was uploaded by another app/client to the server recently, but not downloaded to the current device (app/client) yet.
    public func localFileStatus(uuid: NSUUID) -> SMSyncAttributes? {
        var fileAttr:SMSyncAttributes?
        if let localFileMetaData = SMLocalFile.fetchObjectWithUUID(uuid.UUIDString) {
            fileAttr = SMSyncAttributes(withUUID: uuid)
            fileAttr!.mimeType = localFileMetaData.mimeType
            fileAttr!.remoteFileName = localFileMetaData.remoteFileName
            fileAttr!.appFileType = localFileMetaData.appFileType
            fileAttr!.deleted = localFileMetaData.deletedOnServer
            Log.msg("localFileMetaData.deletedOnServer: \(localFileMetaData.deletedOnServer)")
        }
        
        return fileAttr
    }
    
    // Enqueue a local immutable file for subsequent upload. Immutable files are assumed to not change (at least until after the upload has completed). This immutable characteristic is not enforced by this class but needs to be enforced by the caller of this class.
    // This operation persists across app launches, as long as the the call itself completes. If there is a file with the same uuid, which has been enqueued but not yet committed, it will be replaced by the given file. This operation does not access the server, and thus runs quickly and synchronously.
    // File can be empty.
    public func uploadImmutableFile(localFile:SMRelativeLocalURL, withFileAttributes attr: SMSyncAttributes) {
        self.uploadFile(localFile, ofType: .Immutable, withFileAttributes: attr)
    }
    
    // The same as above, but ownership of the file referenced is passed to this class, and once the upload operation succeeds, the file will be deleted.
    // File can be empty.
    public func uploadTemporaryFile(temporaryLocalFile:SMRelativeLocalURL,withFileAttributes attr: SMSyncAttributes) {
        self.uploadFile(temporaryLocalFile, ofType: .Temporary, withFileAttributes: attr)
    }

    // Analogous to the above, but the data is given in an NSData object not a file. Giving nil data means you are indicating a file with 0 bytes.
    public func uploadData(data:NSData?, withDataAttributes attr: SMSyncAttributes) {
        // Write the data to a temporary file. Seems better this way: So that (a) large NSData objects don't overuse RAM, and (b) we can rely on the same general code that uploads files-- it should make testing/debugging/maintenance easier.
        
        let localFile = SMFiles.createTemporaryRelativeFile()
        
        if localFile == nil {
            self.callSyncServerModeChange(
                .InternalError(Error.Create("Yikes: Could not create file!")))
            return
        }
        
        var dataToWrite:NSData
        if data == nil {
            dataToWrite = NSData()
        }
        else {
            dataToWrite = data!
        }
        
        if !dataToWrite.writeToURL(localFile!, atomically: true) {
            self.callSyncServerModeChange(
                .InternalError(Error.Create("Could not write data to temporary file!")))
            return
        }

        self.uploadFile(localFile!, ofType: .Temporary, withFileAttributes: attr)
    }
    
    private enum TypeOfUploadFile {
        case Immutable
        case Temporary
    }
    
    private func uploadFile(localFileURL:SMRelativeLocalURL, ofType typeOfUpload:TypeOfUploadFile, withFileAttributes attr: SMSyncAttributes) {
        // Check to see if we already know about this file in our SMLocalFile meta data.
        var localFileMetaData = SMLocalFile.fetchObjectWithUUID(attr.uuid.UUIDString)
        
        Log.msg("localFileMetaData: \(localFileMetaData)")
        
        if (nil == localFileMetaData) {
            localFileMetaData = SMLocalFile.newObject() as? SMLocalFile
            localFileMetaData!.syncState = .InitialUpload
            localFileMetaData!.uuid = attr.uuid.UUIDString
            
            if nil == attr.mimeType {
                self.callSyncServerModeChange(
                    .NonRecoverableError(Error.Create("mimeType not given!")))
                return
            }
            
            localFileMetaData!.mimeType = attr.mimeType
            
            localFileMetaData!.appFileType = attr.appFileType
            
            if nil == attr.remoteFileName {
                let error = Error.Create("remoteFileName not given!")
                Log.error("\(error)")
                self.callSyncServerModeChange(.NonRecoverableError(error))
                return
            }
            
            localFileMetaData!.remoteFileName = attr.remoteFileName
            
            // Just created for upload -- it must have a version of 0.
            localFileMetaData!.localVersion = 0
        }
        else {
            // Existing file
            
            // This should never occur: How could we get the UUID locally for a file that's being downloaded?
            Assert.If(localFileMetaData!.syncState == .InitialDownload, thenPrintThisString: "This file is being downloaded!")
            
            if attr.remoteFileName != nil &&  (localFileMetaData!.remoteFileName! != attr.remoteFileName) {
                let error = Error.Create("You gave a different remote file name than was present on the server!")
                Log.error("\(error)")
                self.callSyncServerModeChange(.NonRecoverableError(error))
                return
            }
        }
        
        // TODO: Compute an MD5 hash of the file and store that in the meta data. This needs to be shipped up to the server too so that when the file is downloaded the receiving client can verify the hash. 
        
        let change = SMUploadFile.newObject() as! SMUploadFile
        change.fileURL = localFileURL
        
        switch (typeOfUpload) {
        case .Immutable:
            change.deleteLocalFileAfterUpload = false
        case .Temporary:
            change.deleteLocalFileAfterUpload = true
        }
        
        change.localFile = localFileMetaData!
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        // This also checks the .deletedOnServer property.
        if !SMQueues.current().addToUploadsBeingPrepared(change) {
            self.callSyncServerModeChange(.ClientAPIError(Error.Create("File was already deleted!")))
            return
        }
        
        // The localVersion property of the SMLocalFile object will get updated, if needed, when we sync this file meta data to the server meta data.
        
        self.startNormalTimer()
    }
    
    // Enqueue a deletion operation. The operation persists across app launches. It is an error to try again later to upload, download, or delete the data/file referenced by this UUID. You can only delete files that are already known to the SMSyncServer (e.g., that you've uploaded). Any previous queued uploads for this uuid are expunged-- only the delete is carried out.
    public func deleteFile(uuid:NSUUID) {
        // We must already know about this file in our SMLocalFile meta data.
        let localFileMetaData = SMLocalFile.fetchObjectWithUUID(uuid.UUIDString)
        Log.msg("localFileMetaData: \(localFileMetaData)")
        
        if (nil == localFileMetaData) {
            self.callSyncServerModeChange(.ClientAPIError(Error.Create("Attempt to delete a file unknown to SMSyncServer!")))
            return
        }
        
        // TODO: Is there any kind of a race condition here? Can an upload currently being processed change the syncState of the local file meta data?
        if localFileMetaData!.syncState == .InitialUpload {
            // A new file was queued for upload, and before upload was deleted. We'll just mark the file as deleted, and return. The file will never be uploaded to the server (so the .deletedOnServer naming is incorrect in this case).
            localFileMetaData!.deletedOnServer = true
            
            let uploads = NSOrderedSet(orderedSet: localFileMetaData!.pendingUploads!)
            for managedObject in uploads {
                let uploadFile = managedObject as! SMUploadFile
                let queue = uploadFile.queue
                uploadFile.removeObject()
                queue!.removeIfNoFileOperations()
            }
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
            return
        }
        
        Assert.If(localFileMetaData!.localVersion == nil, thenPrintThisString: "Why is the .localVersion nil?")
        Assert.If(localFileMetaData!.syncState == .InitialDownload, thenPrintThisString: "This file is being downloaded!")
        
        let change = SMUploadDeletion.newObject() as! SMUploadDeletion
        change.localFile = localFileMetaData!
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        // Also checks the .deletedOnServer property.
        if !SMQueues.current().addToUploadsBeingPrepared(change) {
            change.removeObject()
            self.callSyncServerModeChange(.ClientAPIError(Error.Create("File was already deleted!")))
            return
        }
        
        self.startNormalTimer()
    }

#if DEBUG
    // For Debugging/Development. Removes the local meta data for the item insofar as the SMSyncServer is concerned. Doesn't contact the server.
    public func cleanupFile(uuid:NSUUID) {
        let localFileMetaData = SMLocalFile.fetchObjectWithUUID(uuid.UUIDString)
        Assert.If(localFileMetaData == nil, thenPrintThisString: "Yikes: Couldn't find uuid: \(uuid)")
        localFileMetaData!.removeObject()
    }
    
    public enum ResetType {
        // Entirely removes meta data. Default operation.
        case DeleteMetaData
        
        // For meta data indicating file is deleted, now marks file as not deleted.
        case Undelete
        
        // Go back to a version 1 earlier
        case DecrementVersion
    }
    
    // Reset/clear meta data in SMSyncServer. E.g., useful for testing downloads so that files will now need to be downloaded from server. If you just want to reset for a single file, pass the UUID of that file. Does not result directly with interaction with the server.
    // Only use the ResetType parameter if you are giving a UUID.
    public func resetMetaData(forUUID uuid:NSUUID?=nil, resetType:ResetType?=nil) {
        Assert.If(self.isOperating, thenPrintThisString: "Should not be operating!")
        Assert.If(uuid == nil && resetType != nil, thenPrintThisString: "Needs a UUID to give a reset type")

        if uuid == nil {
            if let metaDataArray = SMLocalFile.fetchAllObjects() as? [SMLocalFile] {
                for localFile in metaDataArray {
                    localFile.removeObject()
                }
            }
        }
        else {
            if let localFile = SMLocalFile.fetchObjectWithUUID(uuid!.UUIDString) {
                switch resetType {
                case .None, .Some(.DeleteMetaData):
                    localFile.removeObject()
                    
                case .Some(.Undelete):
                    localFile.deletedOnServer = false
                    
                case .Some(.DecrementVersion):
                    localFile.localVersion = localFile.localVersion!.integerValue - 1
                }
            }
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
#endif

    // Returns true iff the SMSyncServer is currently in the process of upload or download file operations. Any upload or delete operation you enqueue will wait until it is not operating. (Mostly useful for testing/debugging). This is just a synonym for self.mode == .Synchronizing
    public var isOperating: Bool {
        switch self.mode {
        case .Synchronizing:
            return true
            
        default:
            return false
        }
    }
    
    // Syncs the enqueued changes with the sync server. If you enqueue multiple requests for the same UUID to this class, prior to a commit, then the historically most recent enqueue request for that UUID is used and the others are discarded.
    // The intent of this method is to enable the app to logically segment collections of changes to files that are to be atomically synced with the server. E.g., suppose you have 10 files that should be updated in an all-or-none manner to the server.
    // If autoCommit is currently true, then this resets the timer interval *after* the commit has completed.
    // If there is currently a commit operation in progress, the commit will be carried out after the current one (unless an error is reported by the syncServerError delegate method).
    // There must be a user signed to the cloud storage system when you call this method.
    // If you do a commit and no files have changed (i.e., no uploads or deletes have been enqueued), then the commit does nothing (and false is returned). (No delegate methods are called in this case).
    public func commit() -> Bool? {
        // Testing for network availability is done by the SMServerNetworking class accessed indirectly through SMSyncControl, so I'm not going to do that here. ALSO: Our intent is to enable the client API to queue up uploads and upload-deletions independent of network access.
        
        // 5/18/16; There are some problems with optional chaining combined with equality/inequality tests. E.g., SMQueues.current().uploadsBeingPrepared?.operations!.count == 0
        // See http://stackoverflow.com/questions/31460395/does-anybody-know-the-rationale-behind-nil-0-true-and-nil-0-tr
        // And that's why I'm not using them.
        
        Log.msg("Attempting to commit: \(SMQueues.current().uploadsBeingPrepared)")

        if SMQueues.current().uploadsBeingPrepared == nil || SMQueues.current().uploadsBeingPrepared!.operations!.count == 0 {
            Log.msg("Attempting to commit: But there were no changed files!")
            NSThread.runSyncOnMainThread() {
                self.delegate?.syncServerEventOccurred(.NoFilesToUpload)
            }
            return false
        }
        
        if !SMSyncServerUser.session.delegate.syncServerUserIsSignedIn {
            self.callSyncServerModeChange(.ClientAPIError(Error.Create("There is no user signed in")))
            return nil
        }
        
        // Add a wrapup to the uploadsBeingPrepared, then we're ready for the commit.
        let wrapUp = SMUploadWrapup.newObject() as! SMUploadWrapup
        let result = SMQueues.current().addToUploadsBeingPrepared(wrapUp)
        Assert.If(!result, thenPrintThisString: "Couldn't add SMUploadWrapup!")

        // The reason for this locking operation is to deal with a race condition between queueing a committed collection of uploads and stopping a currently running sync operation.
        SMSyncControl.session.lockAndNextSyncOperation() {
            SMQueues.current().moveBeingPreparedToCommitted()
        }
        
        return true
    }
    
    // Check for downloads and perform any other pending sync operations.
    public func sync() {
        SMSyncControl.session.nextSyncOperation()
    }
    
    // MARK: Functions calling delegate methods
    
    private func callSyncServerModeChange(mode:SMSyncServerMode) {
        self.setMode(mode)
        NSThread.runSyncOnMainThread() {
            self.delegate?.syncServerModeChange(mode)
        }
    }
    
    // MARK: End calling delegate methods

#if DEBUG
    public func getFileIndex() {
        SMServerAPI.session.getFileIndex() { fileIndex, apiResult in
            if (nil == apiResult.error) {
                Log.msg("Success!")
            }
            else {
                Log.msg("Error: \(apiResult.error)")
            }
        }
    }
#endif

#if DEBUG
    public func showLocalFiles() {
        var numberOfFiles = 0
        if let fileArray = SMLocalFile.fetchAllObjects() as? [SMLocalFile] {
            for localFile:SMLocalFile in fileArray {
                Log.msg("localFile: \(localFile.localVersion); \(localFile)")
                numberOfFiles += 1
            }
        }
        
        Log.msg("\(numberOfFiles) files described in the meta data")
    }
#endif

    // USE CAREFULLY!
    /* Doesn't actually recover from the error. Expects the caller to somehow do that.
    
    Has two behaviors:
    
    1) Local cleanup: resets the pending upload operations to the initial state (i.e., all uploads/deletions you have queued will be lost).
    
    2) Server cleanup: resets the server so that it can operate again (e.g., removes the server lock), and if the server reset is successful, resets the mode to .Idle. The client *must* have the server lock in order for this to succeed.
    
    For .ClientAPIError's: Does only behavior 1) and does it *synchronously*.
    
    For .InternalError's and .NonRecoverableError's: Does behavior 2) asynchronously, and if behavior 2) is successful, does behavior 1). So effectively, both behaviors are *asynchronous*.
    
    On normal reset operation (i.e., the reset worked properly), the callback error parameter will be nil.
    */
    public func resetFromError(completion:((error:NSError?)->())?=nil) {
        SMSyncControl.session.resetFromError(completion)
    }
    
    // Convenience function to get data from smSyncServerClientPlist
    public class func getDataFromPlist(syncServerClientPlistFileName fileName:String) -> (serverURL:String, cloudFolderPath:String, googleServerClientId:String) {
        // Extract parameters out of smSyncServerClientPlist
        let bundlePath = NSBundle.mainBundle().bundlePath as NSString
        let syncServerClientPlistPath = bundlePath.stringByAppendingPathComponent(fileName)
        let syncServerClientPlistData = NSDictionary(contentsOfFile: syncServerClientPlistPath)
        
        Assert.If(syncServerClientPlistData == nil, thenPrintThisString: "Could not access your \(fileName) file at: \(syncServerClientPlistPath)")
        
        var serverURLString:String?
        var cloudFolderPath:String?
        var googleServerClientId:String?
        
        func getDictVar(varName:String, inout result:String?) {
            result = syncServerClientPlistData![varName] as? String
            Assert.If(result == nil, thenPrintThisString: "Could not access \(varName) in \(fileName)")
            Log.msg("Using: \(varName): \(result)")
        }
        
        getDictVar("ServerURL", result: &serverURLString)
        getDictVar("CloudFolderPath", result: &cloudFolderPath)
        getDictVar("GoogleServerClientID", result: &googleServerClientId)
        
        return (serverURL:serverURLString!, cloudFolderPath:cloudFolderPath!, googleServerClientId:googleServerClientId!)
    }
}

/* [1]. 2/24/16; Up until today, the design for the download delegate provided a callback to the app/client for each single file downloaded. However, that doesn't seem to be the right way to go because of the possibility that downloads will fail part way through. E.g., there could be two files to download and only one gets downloaded successfully at this point in time. This partial download scenario doesn't fit with the atomic/transactional character of the operations we are trying to provide. So I've switched the delegates over to a single callback indicating to the app/client that all downloads have completed.
*/

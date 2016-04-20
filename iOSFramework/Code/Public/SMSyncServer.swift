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

/*
public enum SMSyncConflictType {
    case ServerNewer(version:Int)
    case AppNewer(version:Int)
}

public class SMSyncConflicts : SMSyncAttributes {
    public var conflictType:SMSyncConflictType
    
    public init(withUUID theUUID:NSUUID, mimeType theMimeType:String, andRemoteFileName theRemoteFileName:String, conflictType theConflictType:SMSyncConflictType) {
        self.conflictType = theConflictType
        super.init(withUUID: theUUID, mimeType: theMimeType, andRemoteFileName: theRemoteFileName)
    }
}
*/

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
    
    // Internal error recovery event.
    case Recovery
}

// "class" to make the delegate weak.
// TODO: These delegate methods are called on the main thread.
public protocol SMSyncServerDelegate : class {
    // Called at the end of all downloads, on non-error conditions. Only called when there was at least one download.
    // The callee owns the files referenced by the NSURL's after this call completes. These files are temporary in the sense that they will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location. See [1] for a design note about this delegate method. This is received/called in an atomic manner: This reflects the current state of files on the server.
    func syncServerDownloadsComplete(downloadedFiles:[(NSURL, SMSyncAttributes)])
    
    // Called when deletions indications have been received from the server. I.e., these files has been deleted on the server. This is received/called in an atomic manner: This reflects the current state of files on the server. The recommended action is for the client to delete the files represented by the UUID's.
    func syncServerClientShouldDeleteFiles(uuids:[NSUUID])
    
    // TODO: Reports conflicting file versions when uploading or downloading. The callee should use the resolution callback to indicate how to deal with these conflicts.
    // TODO: Can these occur both on upload and download?
    // func syncServerFileConflicts(conflictingFiles:[SMSyncConflicts], resolution:([SMSyncConflicts])->())
    
    // Reports mode changes including errors. Can be useful for presenting a graphical user-interface which indicates ongoing server/networking operations. E.g., so that the user doesn't close or otherwise the dismiss the app until server operations have completed.
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
            SMSyncControl.session.delegate = newValue
            //SMDownloadFiles.session.delegate = newValue
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
    
    // Persisting this variable because we need to be know what mode we are operating in even if the app is restarted or crashes.
    private static let _mode = SMPersistItemData(name: "SMSyncServer.Mode", initialDataValue: NSKeyedArchiver.archivedDataWithRootObject(SMSyncServerModeWrapper(withMode: .Idle)), persistType: .UserDefaults)
    
    private func setMode(mode:SMSyncServerMode) {
        SMSyncServer._mode.dataValue = NSKeyedArchiver.archivedDataWithRootObject(SMSyncServerModeWrapper(withMode: mode))
    }
    
    public var mode:SMSyncServerMode {
        // `mode` is an instance variable and not a class variable just for consistency for the client API, i.e., to access it from the session member.
        let syncServerMode = NSKeyedUnarchiver.unarchiveObjectWithData(SMSyncServer._mode.dataValue) as! SMSyncServerModeWrapper
        return syncServerMode.mode
    }
    
    // Only retains a weak reference to the cloudStorageUserDelegate
    public func appLaunchSetup(withServerURL serverURL: NSURL, andCloudStorageUserDelegate cloudStorageUserDelegate:SMCloudStorageUserDelegate) {

        Network.session().appStartup()
        SMServerNetworking.session.appLaunchSetup()
        SMServerAPI.session.serverURL = serverURL
        SMUploadFiles.session.appLaunchSetup()
        //SMDownloadFiles.session.appLaunchSetup()

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
            fileAttr!.deleted = false
            if localFileMetaData.deletedOnServer != nil {
                fileAttr!.deleted = localFileMetaData.deletedOnServer!.boolValue
            }
        }
        
        return fileAttr
    }
    
    // Enqueue a local immutable file for subsequent upload. Immutable files are assumed to not change (at least until after the upload has completed). This immutable characteristic is not enforced by this class but needs to be enforced by the caller of this class.
    // This operation persists across app launches, as long as the the call itself completes. If there is a file with the same uuid, which has been enqueued but not yet committed, it will be replaced by the given file. This operation does not access the server, and thus runs quickly and synchronously.
    public func uploadImmutableFile(localFile:SMRelativeLocalURL, withFileAttributes attr: SMSyncAttributes) {
        self.uploadFile(localFile, ofType: .Immutable, withFileAttributes: attr)
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
            localFileMetaData!.newUpload = true
            localFileMetaData!.uuid = attr.uuid.UUIDString
            
            if nil == attr.mimeType {
                self.callSyncServerModeChange(
                    .NonRecoverableError(Error.Create("mimeType not given!")))
                return
            }
            
            localFileMetaData!.mimeType = attr.mimeType
            
            localFileMetaData!.appFileType = attr.appFileType
            
            if nil == attr.remoteFileName {
                self.callSyncServerModeChange(
                    .NonRecoverableError(Error.Create("remoteFileName not given!")))
                return
            }
            
            localFileMetaData!.remoteFileName = attr.remoteFileName
        }
        else {
            // Existing file
            
            if attr.remoteFileName != nil &&  (localFileMetaData!.remoteFileName! != attr.remoteFileName) {
                self.callSyncServerModeChange(
                    .NonRecoverableError(Error.Create("You gave a different remote file name than was present on the server!")))
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
        
        if !SMQueues.current().addToUploadsBeingPrepared(change) {
            self.callSyncServerModeChange(.NonRecoverableError(Error.Create("File was already deleted!")))
        }
        
        // The localVersion property of the SMLocalFile object will get updated, if needed, when we sync this file meta data to the server meta data.
        
        self.startNormalTimer()
    }
    
    // The same as above, but ownership of the file referenced is passed to this class, and once the upload operation succeeds, the file will be deleted.
    public func uploadTemporaryFile(temporaryLocalFile:SMRelativeLocalURL, withFileAttributes attr: SMSyncAttributes) {
        self.uploadFile(temporaryLocalFile, ofType: .Temporary, withFileAttributes: attr)
    }

    // Analogous to the above, but the data is given in an NSData object not a file.
    public func uploadData(data:NSData, withDataAttributes attr: SMSyncAttributes) {
        // Write the data to a temporary file. Seems better this way: So that (a) large NSData objects don't overuse RAM, and (b) we can rely on the same general code that uploads files-- it should make testing/debugging/maintenance easier.
        
        let localFile = SMFiles.createTemporaryRelativeFile()
        
        if localFile == nil {
            self.callSyncServerModeChange(
                .InternalError(Error.Create("Yikes: Could not create file!")))
            return
        }
        
        if !data.writeToURL(localFile!, atomically: true) {
            self.callSyncServerModeChange(
                .InternalError(Error.Create("Could not write data to temporary file!")))
            return
        }

        self.uploadFile(localFile!, ofType: .Temporary, withFileAttributes: attr)
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
        
        let change = SMUploadDeletion.newObject() as! SMUploadDeletion
        change.localFile = localFileMetaData!
        
        if !SMQueues.current().addToUploadsBeingPrepared(change) {
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
        CoreData.sessionNamed(SMCoreData.name).removeObject(localFileMetaData!)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    // Reset/clear meta data in SMSyncServer. E.g., useful for testing downloads so that files will now need to be downloaded from server. If you just want to reset for a single file, pass the UUID of that file.
    public func resetMetaData(forUUID uuid:NSUUID?=nil) {
        Assert.If(self.isOperating, thenPrintThisString: "Should not be operating!")
        
        if uuid == nil {
            if let metaDataArray = SMLocalFile.fetchAllObjects() {
                for localFile in metaDataArray {
                    CoreData.sessionNamed(SMCoreData.name).removeObject(localFile as! NSManagedObject)
                }
            }
        }
        else {
            if let localFile = SMLocalFile.fetchObjectWithUUID(uuid!.UUIDString) {
                CoreData.sessionNamed(SMCoreData.name).removeObject(localFile)
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
        
        Log.msg("Attempting to commit")

        if SMQueues.current().uploadsBeingPrepared!.operations!.count == 0 {
            Log.msg("Attempting to commit: But there were no changed files!")
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
    
    // MARK: Functions calling delegate methods
    
    private func callSyncServerModeChange(mode:SMSyncServerMode) {
        self.setMode(mode)
        self.delegate?.syncServerModeChange(mode)
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

    // Doesn't actually recover from the error. Expect the caller to somehow do that. Just resets the mode so this class can later proceed.
    public func resetFromError() {
        self.setMode(.Idle)
    }
}

/* [1]. 2/24/16; Up until today, the design for the download delegate provided a callback to the app/client for each single file downloaded. However, that doesn't seem to be the right way to go because of the possibility that downloads will fail part way through. E.g., there could be two files to download and only one gets downloaded successfully at this point in time. This partial download scenario doesn't fit with the atomic/transactional character of the operations we are trying to provide. So I've switched the delegates over to a single callback indicating to the app/client that all downloads have completed.
*/

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

public enum SMSyncServerRecovery {
    case Upload
    case MayHaveCommitted
    case OutboundTransfer
}

public class SMSyncAttributes {
    // The identifier for the file/data item.
    public var uuid:NSUUID!
    
    // Must be provided when uploading for a new uuid. (If you give a remoteFileName for an existing uuid it *must* match that already present in cloud storage).
    public var remoteFileName:String?
    
    // Must be provided when uploading for a new uuid; optional after that.
    public var mimeType:String?
    
    // TODO: Optionally provides the app with some app-specific type information about the file.
    public var appFileType:String?
    
    // TODO: An optional app-specific identifier for a logical group or category that the file/data item belongs to. The intent behind this identifier is to make downloading logical groups of files easier. E.g., so that not all changed files need to be downloaded at once.
    public var appGroupId:NSUUID?
    
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

// "class" to make the delegate weak.
// TODO: These delegate methods are called on the main thread.
public protocol SMSyncServerDelegate : class {
    
    // The callee owns the localFile after this call completes. The file is temporary in the sense that it will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a permanent location.
    func syncServerSingleFileDownloadComplete(temporaryLocalFile:NSURL, withFileAttributes attr: SMSyncAttributes)
    
    // Called at the end of all downloads, on a non-error condition, if at least one download carried out.
    func syncServerAllDownloadsComplete()
    
    // Called after a deletion indication has been received from the server. I.e., this file has been deleted on the server.
    func syncServerDeletionReceived(uuid uuid:NSUUID)
    
    // numberOperations includes upload and deletion operations.
    func syncServerCommitComplete(numberOperations numberOperations:Int?)
    
    // Called after a single file/item has been uploaded to the SyncServer.
    func syncServerSingleUploadComplete(uuid uuid:NSUUID)
    
    // Called after deletion operations have been sent to the SyncServer. All pending deletion operations are sent as a group.
    func syncServerDeletionsSent(uuids:[NSUUID])
    
    // This reports recovery progress from recoverable errors. Mostly useful for testing and debugging.
    func syncServerRecovery(progress:SMSyncServerRecovery)
    
    // TODO: Reports conflicting file versions when uploading or downloading. The callee should use the resolution callback to indicate how to deal with these conflicts.
    // TODO: Can these occur both on upload and download?
    // func syncServerFileConflicts(conflictingFiles:[SMSyncConflicts], resolution:([SMSyncConflicts])->())

    /* This error can occur in one of two types of circumstances:
    1) There was a client API error in which the user of the SMSyncServer (e.g., caller of this interface) made an error (e.g., using the same cloud file name with two different UUID's).
    2) There was an error that, after internal SMSyncServer recovery attempts, could not be dealt with.
    */
    func syncServerError(error:NSError)
    
#if DEBUG
    func syncServerNoFilesToDownload()
#endif
}

// Derived from NSObject because of the use of addTarget from TargetsAndSelectors below.
public class SMSyncServer : NSObject {
    private var _autoCommit = false
    private var _autoCommitIntervalSeconds:Float = 30
        
    // Timer for .Normal mode when doing autoCommit.
    private var normalTimer:TimedCallback?
    
    // This is a singleton because we need centralized control over the file upload/download operations.
    public static let session = SMSyncServer()

    // This delegate is optional because, while usually important for caller operation, the SMSyncServer itself isn't really dependent on the operation of the delegate methods assuming correct operation of the caller.
    public weak var delegate:SMSyncServerDelegate? {
        set {
            SMUploadFiles.session.delegate = newValue
            SMDownloadFiles.session.delegate = newValue
        }
        get {
            return SMUploadFiles.session.delegate
        }
    }

    private func callSyncServerError(error: NSError) {
        Log.error("syncServerError: \(error)")
        self.delegate?.syncServerError(error)
    }
    
    // If autoCommit is true, then this is the interval that changes are automatically committed. The interval is timed from the last change enqueued with this class. If no changes are queued, then no commit is done.
    public var autoCommitIntervalSeconds:Float {
        set {
            if newValue < 0 {
                self.callSyncServerError(Error.Create("Yikes: Bad autoCommitIntervalSeconds"))
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
            if .Normal == SMUploadFiles.mode {
                self.startNormalTimer()
            }
        }
        get {
            return _autoCommit
        }
    }
    
    private func startNormalTimer() {
        if .Normal == SMUploadFiles.mode {
            return
        }
        
        self.normalTimer?.cancel()

        if (self.autoCommit) {
            self.normalTimer = TimedCallback(duration: _autoCommitIntervalSeconds) {
                self.commit()
            }
        }
    }
    
    // Only retains a weak reference to the cloudStorageUserDelegate
    public func appLaunchSetup(withServerURL serverURL: NSURL, andCloudStorageUserDelegate cloudStorageUserDelegate:SMCloudStorageUserDelegate) {

        Network.session().appStartup()
        SMServerNetworking.session.appLaunchSetup()
        SMServerAPI.session.serverURL = serverURL
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
        SMSyncServerUser.session.signInProcessCompleted.addTarget!(self, withSelector: "signInCompletedAction")
        
        SMSyncServerUser.session.appLaunchSetup(withCloudStorageUserDelegate: cloudStorageUserDelegate)
    }
    
    // PRIVATE
    internal func signInCompletedAction() {
        Log.msg("signInCompletedAction")
        
        // This will start a delayed upload, if there was one, so leave this until after user is signed in.
        SMUploadFiles.session.appLaunchSetup()
        
        // Leave this until now, i.e., until after sign-in, so we don't start any recovery process until after sign-in.
        Network.session().connectionStateCallbacks.addTarget!(self, withSelector: "networkConnectionStateChangeAction")
    }
    
    // PRIVATE
    internal func networkConnectionStateChangeAction() {
        if Network.session().connected() {
            SMUploadFiles.session.networkOnline()
        }
    }
    
    // Enqueue a local immutable file for subsequent upload. Immutable files are assumed to not change (at least until after the upload has completed). This immutable characteristic is not enforced by this class but needs to be enforced by the caller of this class.
    // This operation persists across app launches, as long as the the call itself completes. If there is a file with the same uuid, which has been enqueued but not yet committed, it will be replaced by the given file. This operation does not access the server, and thus runs quickly and synchronously.
    public func uploadImmutableFile(localFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        self.uploadFile(localFile, ofType: .Immutable, withFileAttributes: attr)
    }
    
    private enum TypeOfUploadFile {
        case Immutable
        case Temporary
    }
    
    private func uploadFile(localFile:NSURL, ofType typeOfUpload:TypeOfUploadFile, withFileAttributes attr: SMSyncAttributes) {
        // Check to see if we already know about this file in our SMLocalFile meta data.
        var localFileMetaData:SMLocalFile?
        localFileMetaData = SMLocalFile.fetchObjectWithUUID(attr.uuid.UUIDString)
        
        Log.msg("localFileMetaData: \(localFileMetaData)")
        
        if (nil == localFileMetaData) {
            localFileMetaData = SMLocalFile.newObject() as? SMLocalFile
            localFileMetaData!.uuid = attr.uuid.UUIDString
            
            if nil == attr.mimeType {
                self.callSyncServerError(Error.Create("mimeType not given!"))
                return
            }
            
            localFileMetaData!.mimeType = attr.mimeType
            
            localFileMetaData!.appFileType = attr.appFileType
            
            if nil == attr.remoteFileName {
                self.callSyncServerError(Error.Create("remoteFileName not given!"))
                return
            }
            
            localFileMetaData!.remoteFileName = attr.remoteFileName
        }
        else {
            // Existing file
            
            let alreadyDeleted = localFileMetaData!.deletedOnServer != nil && localFileMetaData!.deletedOnServer!.boolValue
            
            if localFileMetaData!.pendingDeletion || alreadyDeleted {
                self.callSyncServerError(Error.Create("Attempt to upload a file/item marked for deletion!"))
                return
            }
                        
            if attr.remoteFileName != nil &&  (localFileMetaData!.remoteFileName! != attr.remoteFileName) {
                self.callSyncServerError(Error.Create("You gave a different remote file name than was present on the server!"))
                return
            }
        }
        
        // TODO: Compute an MD5 hash of the file and store that in the meta data. This needs to be shipped up to the server too so that when the file is downloaded the receiving client can verify the hash. 
        
        let change = SMFileChange.newObject() as! SMFileChange
        // .path is the right NSURL property, not .absoluteString or .relativeString; with both of those you get file:// prepended to the string and I just want the path starting with "/" here.
        change.localFileNameWithPath = localFile.path
        
        switch (typeOfUpload) {
        case .Immutable:
            change.deleteLocalFileAfterUpload = false
        case .Temporary:
            change.deleteLocalFileAfterUpload = true
        }
        
        localFileMetaData!.addPendingLocalChangesObject(change)
        
        // The localVersion property of the SMLocalFile object will get updated, if needed, when we sync this file meta data to the server meta data.
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        self.startNormalTimer()
    }
    
    // The same as above, but ownership of the file referenced is passed to this class, and once the upload operation succeeds, the file will be deleted.
    public func uploadTemporaryFile(temporaryLocalFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        self.uploadFile(temporaryLocalFile, ofType: .Temporary, withFileAttributes: attr)
    }

    // Analogous to the above, but the data is given in an NSData object not a file.
    public func uploadData(data:NSData, withDataAttributes attr: SMSyncAttributes) {
        // Write the data to a temporary file. Seems better this way: So that (a) large NSData objects don't overuse RAM, and (b) we can rely on the same general code that uploads files-- it should make testing/debugging/maintenance easier.
        
        let localFile = SMFiles.createTemporaryFile()
        Assert.If(localFile == nil, thenPrintThisString: "Yikes: Could not create file!")
        
        if !data.writeToURL(localFile!, atomically: true) {
            Assert.badMojo(alwaysPrintThisString:"Could not write data to temporary file!")
            return
        }

        self.uploadFile(localFile!, ofType: .Temporary, withFileAttributes: attr)
    }
    
    // Enqueue a deletion operation. The operation persists across app launches. It is an error to try again later to upload, download, or delete the data/file referenced by this UUID. You can only delete files that are already known to the SMSyncServer (e.g., that you've uploaded). Any previous queued uploads for this uuid are expunged-- only the delete is carried out.
    public func deleteFile(uuid:NSUUID) {
        // We must already know about this file in our SMLocalFile meta data.
        var localFileMetaData:SMLocalFile?
        localFileMetaData = SMLocalFile.fetchObjectWithUUID(uuid.UUIDString)
        
        Log.msg("localFileMetaData: \(localFileMetaData)")
        
        if (nil == localFileMetaData) {
            self.callSyncServerError(Error.Create("Attempt to delete a file unknown to SMSyncServer!"))
            return
        }
        
        let alreadyDeleted = localFileMetaData!.deletedOnServer != nil && localFileMetaData!.deletedOnServer!.boolValue

        if alreadyDeleted {
            self.callSyncServerError(Error.Create("Attempt to delete a file that is already deleted!"))
            return
        }
        
        if localFileMetaData!.pendingDeletion {
            self.callSyncServerError(Error.Create("Attempt to delete a file already marked for deletion!"))
            return
        }
        
        let change = SMFileChange.newObject() as! SMFileChange
        change.deletion = true
        
        // Expunge any pending uploads.
        localFileMetaData!.pendingLocalChanges = nil
        
        localFileMetaData!.addPendingLocalChangesObject(change)
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
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
    
    // Reset/clear meta data in SMSyncServer. E.g., useful for testing downloads so that files will now need to be downloaded from server.
    public func resetMetaData() {
        Assert.If(self.isOperating, thenPrintThisString: "Should not be operating!")
        
        if let metaDataArray = SMLocalFile.fetchAllObjects() {
            for localFile in metaDataArray {
                CoreData.sessionNamed(SMCoreData.name).removeObject(localFile as! NSManagedObject)
            }
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
#endif

    // Returns true iff the SMSyncServer is currently in the process of uploading file operations. Any upload or delete operation you enqueue will wait until it is not operating. (Mostly useful for testing/debugging).
    public var isOperating: Bool {
        get {
            return SMSync.session.isOperating
        }
    }
    
    // Syncs the enqueued changes with the sync server. If you enqueue multiple requests for the same UUID to this class, prior to a commit, then the historically most recent enqueue request for that UUID is used and the others are discarded.
    // The intent of this method is to enable the app to logically segment collections of changes to files that are to be atomically synced with the server. E.g., suppose you have 10 files that should be updated in an all-or-none manner to the server.
    // If autoCommit is currently true, then this resets the timer interval *after* the commit has completed.
    // If there is currently a commit operation in progress, the commit will be carried out after the current one (unless an error is reported by the syncServerError delegate method).
    // There must be a user signed to the cloud storage system when you call this method.
    // If you do a commit and no files have changed (i.e., no uploads or deletes have been enqueued), then the commit does nothing. (No delegate methods are called in this case).
    public func commit() {
        // Testing for network availability is done by the SMServerNetworking class accessed indirectly through SMUploadFiles, so I'm not going to do that here.
        
        Log.msg("Attempting to commit")
        
        if !SMSyncServerUser.session.delegate.syncServerUserIsSignedIn {
            self.callSyncServerError(Error.Create("There is no user signed in"))
            return
        }
        
        SMUploadFiles.session.prepareForUpload()
    }

#if DEBUG
    public func getFileIndex() {
        SMServerAPI.session.getFileIndex() { fileIndex, error in
            if (nil == error) {
                Log.msg("Success!")
            }
            else {
                Log.msg("Error: \(error)")
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
                numberOfFiles++
            }
        }
        
        Log.msg("\(numberOfFiles) files described in the meta data")
    }
#endif

    public func resetFromError() {
        SMUploadFiles.session.resetFromError()
    }
}

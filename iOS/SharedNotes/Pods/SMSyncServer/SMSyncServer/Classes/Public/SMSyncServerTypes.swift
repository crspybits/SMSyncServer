//
//  SMSyncServerTypes.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 2/26/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Misc public utility types for SMSyncServer

import Foundation
import SMCoreLib

public typealias SMInternalUserId = String

public enum SMSharingType : String {
    // Can do file-download and download-deletion, but no upload or invite. This a "read-only" style of access.
    case Downloader
    
    case Uploader // All operations except for inviting.
    case Admin // All operations.
}

public enum SMSyncClientAPIError: ErrorType {
    case BadAutoCommitInterval
    case CouldNotCreateTemporaryFile
    case CouldNotWriteToTemporaryFile
    case MimeTypeNotGiven
    case RemoteFileNameNotGiven
    case DifferentRemoteFileNameThanOnServer
    case FileWasAlreadyDeleted(specificLocation: String)
    case DeletingUnknownFile
    case UserNotSignedIn
}

public typealias SMAppMetaData = [String:AnyObject]

// Attributes for a data object being synced.
public class SMSyncAttributes {
    // The identifier for the file/data item.
    public var uuid:NSUUID!
    
    // Must be provided when uploading for a new uuid. (If you give a remoteFileName for an existing uuid it *must* match that already present in cloud storage). Will be provided when a file is downloaded from the server.
    public var remoteFileName:String?
    
    // Must be provided when uploading for a new uuid; optional after that. The mimeType of an uploaded object must be consistent across its lifetime.
    public var mimeType:String?
    
    // When uploading or downloading, optionally provides the app with app-specific meta information about the object. This must be encodable to JSON for upload/download to the server. This is stored on the SMSyncServer server (not the users cloud storage), so you may want to be careful about not making this too large. On each upload, you can alter this.
    public var appMetaData:SMAppMetaData?
    
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
    
    // This was introduced to allow for a specific test case internally.
    case FrameworkUploadMetaDataUpdated
    
    // Server has finished performing the outbound transfers of files to cloud storage/deletions to cloud storage. numberOperations is a heuristic value that includes upload and upload-deletion operations. It is heuristic in that it includes retries if retries occurred due to error/recovery handling. We used to call this the "committed" or "CommitComplete" event because the SMSyncServer commit operation is done at this point.
    case AllUploadsComplete(numberOperations:Int?)

    // Similarly, for inbound transfers of files from cloud storage to the sync server. The numberOperations value has the same heuristic meaning.
    case InboundTransferComplete(numberOperations:Int?)
    
    // As said elsewhere, this information is for debugging/testing. The url/attr here may not be consistent with the atomic/transaction-maintained results from syncServerDownloadsComplete in the SMSyncServerDelegate method. (Because of possible recovery steps).
    case SingleDownloadComplete(url:SMRelativeLocalURL, attr:SMSyncAttributes)
    
    // Called at the end of a download when one or more files were downloaded, or at the end of a check for downloads if no downloads were performed.
    case DownloadsFinished

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

public enum SMSyncServerMode {
    // The SMSyncServer client is not performing any operation.
    case Idle

    // SMSyncServer client is performing an operation, e.g., downloading or uploading.
    case Synchronizing
    
    // The SMSyncServer resetFromError method was called, asynchronous operation was required, and the process of resetting from an error is occurring.
    case ResettingFromError
    
    // This is not an error, but indicates a loss of network connection. Normal operation will resume once the network is connected again.
    case NetworkNotConnected
    
    // The modes below are errors that the SMSyncServer couldn't recover from. It's up to the client app to deal with these.
    
    // There was an error that, after internal SMSyncServer recovery attempts, could not be dealt with.
    case NonRecoverableError(NSError)
    
    // An error within the SMSyncServer framework. Ooops. Please report this to the SMSyncServer developers!
    case InternalError(NSError)
}

public func ==(lhs:SMSyncServerMode, rhs:SMSyncServerMode) -> Bool {
    switch lhs {
    case .Idle:
        switch rhs {
            case .Idle: return true
            default: return false
        }

    case .Synchronizing:
        switch rhs {
            case .Synchronizing: return true
            default: return false
        }
        
    case .ResettingFromError:
        switch rhs {
            case .ResettingFromError: return true
            default: return false
        }
        
    case .NetworkNotConnected:
        switch rhs {
            case .NetworkNotConnected: return true
            default: return false
        }
        
    case .NonRecoverableError:
        switch rhs {
            case .NonRecoverableError: return true
            default: return false
        }
        
    case .InternalError:
        switch rhs {
            case .InternalError: return true
            default: return false
        }
    }
}

internal class SMSyncServerModeWrapper : NSObject, NSCoding
{
    var mode:SMSyncServerMode
    init(withMode mode:SMSyncServerMode) {
        self.mode = mode
        super.init()
    }

    @objc required init(coder aDecoder: NSCoder) {
        let name = aDecoder.decodeObjectForKey("name") as! String
        
        switch name {
        case "Idle":
            self.mode = .Idle
            
        case "Synchronizing":
            self.mode = .Synchronizing
            
        case "ResettingFromError":
            self.mode = .ResettingFromError
            
        case "NetworkNotConnected":
            self.mode = .NetworkNotConnected
            
        case "NonRecoverableError":
            let error = aDecoder.decodeObjectForKey("error") as! NSError
            self.mode = .NonRecoverableError(error)
            
        case "InternalError":
            let error = aDecoder.decodeObjectForKey("error") as! NSError
            self.mode = .InternalError(error)
        
        default:
            Assert.badMojo(alwaysPrintThisString: "Should not get here")
            self.mode = .Idle // Without this, get compiler error.
        }
        
        super.init()
    }

    @objc func encodeWithCoder(aCoder: NSCoder) {
        var name:String!
        var error:NSError?
        
        switch self.mode {
        case .Idle:
            name = "Idle"
        
        case .Synchronizing:
            name = "Synchronizing"
        
        case .ResettingFromError:
            name = "ResettingFromError"
            
        case .NetworkNotConnected:
            name = "NetworkNotConnected"
            
        case .NonRecoverableError(let err):
            name = "NonRecoverableError"
            error = err
            
        case .InternalError(let err):
            name = "InternalError"
            error = err
        }
        
        aCoder.encodeObject(name, forKey: "name")
        
        if error != nil {
            aCoder.encodeObject(error, forKey: "error")
        }
    }
}

//
//  SMQueues.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMQueues: NSManagedObject, CoreDataModel {
    private static var _current:SMQueues?
    
    // Don't access internalBeingDownloaded directly.
    // If beingDownloaded has no elements, returns nil.
    var beingDownloaded : NSOrderedSet? {
        get {
            if nil == self.internalBeingDownloaded {
                return nil
            }
            else if self.internalBeingDownloaded!.count == 0 {
                return nil
            }
            else {
                return self.internalBeingDownloaded
            }
        }
        
        set {
            self.internalBeingDownloaded = newValue
        }
    }
    
    // Don't access internalCommittedUploads directly.
    // If committedUploads has no elements, returns nil.
    var committedUploads : NSOrderedSet? {
        get {
            if nil == self.internalCommittedUploads {
                return nil
            }
            else if self.internalCommittedUploads!.count == 0 {
                return nil
            }
            else {
                return self.internalCommittedUploads
            }
        }
        
        set {
            self.internalCommittedUploads = newValue
        }
    }
    
    class func entityName() -> String {
        return "SMQueues"
    }

    // Don't use this directly. Use `current` below.
    class func newObject() -> NSManagedObject {
        let queues = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMQueues

        queues.uploadsBeingPrepared = (SMUploadQueue.newObject() as! SMUploadQueue)
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return queues
    }
    
    class func fetchAllObjects() -> [AnyObject]? {
        var resultObjects:[AnyObject]? = nil
        
        do {
            try resultObjects = CoreData.sessionNamed(SMCoreData.name).fetchAllObjectsWithEntityName(self.entityName())
        } catch (let error) {
            Log.msg("Error in fetchAllObjects: \(error)")
            resultObjects = nil
        }
        
        if resultObjects != nil && resultObjects!.count == 0 {
            resultObjects = nil
        }
        
        return resultObjects
    }
    
    class func current() -> SMQueues {
        if nil == self._current {
            if let currentQueues = self.fetchAllObjects() {
                Assert.If(currentQueues.count != 1, thenPrintThisString: "Not exactly one current SMQueues object")
                self._current = (currentQueues[0] as! SMQueues)
            }
            else {
                self._current = (self.newObject() as! SMQueues)
            }
        }
        
        return self._current!
    }
    
    // Adds the .uploadsBeingPrepared property to the .committedUploads property and resets the .uploadsBeingPrepared property. No effect if .uploadsBeingPrepared is empty.
    func moveBeingPreparedToCommitted() {
        if self.uploadsBeingPrepared!.operations!.count > 0 {
            // Don't use self.committedUploads below, but instead use self.internalCommittedUploads. Because self.committedUploads will return nil when self.internalCommittedUploads has 0 elements. 
            let updatedCommitted = NSMutableOrderedSet(orderedSet: self.internalCommittedUploads!)
            
            updatedCommitted.addObject(self.uploadsBeingPrepared!)
            self.committedUploads = updatedCommitted
            
            self.uploadsBeingPrepared = (SMUploadQueue.newObject() as! SMUploadQueue)
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
    
    // Moves one of the committed upload queues to beingUploaded. Creates upload blocks for the SMUploadFileChange's in the beingUploaded.
    // Don't assign to .beingUploaded directly.
    func moveOneCommittedQueueToBeingUploaded() {
        Assert.If(self.beingUploaded != nil && self.beingUploaded!.operations!.count > 0, thenPrintThisString: "Already uploading!")
        Assert.If(self.committedUploads == nil, thenPrintThisString: "No committed queues!")
        
        if self.beingUploaded != nil {
            CoreData.sessionNamed(SMCoreData.name).removeObject(self.beingUploaded!)
        }
        
        self.beingUploaded = (self.committedUploads!.firstObject as! SMUploadQueue)
        
        let mutableCommitted = NSMutableOrderedSet(orderedSet: self.committedUploads!)
        mutableCommitted.removeObjectAtIndex(0)
        self.committedUploads = mutableCommitted
        
        // This doesn't work!
        // self.committed = (self.committed!.dropFirst(1) as! NSOrderedSet)
        
        // We also need to create SMUploadBlocks for self.beingUploaded
        for elem in self.beingUploaded!.operations! {
            if let uploadFileChange = elem as? SMUploadFile {
                uploadFileChange.addUploadBlocks()
            }
        }
    }
    
    func endUploading() {
        Assert.If(self.beingUploaded == nil, thenPrintThisString: "Not uploading!")
        Assert.If(self.beingUploaded!.operations!.count != 0, thenPrintThisString: "Still upload operations!")
        self.beingUploaded = nil
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    /*
    func end(direction:FileSyncDirection) {
        switch direction {

        case .Download:
            Assert.If(self.beingUploaded != nil, thenPrintThisString: "Already uploading!")
            Assert.If(self.beingDownloaded == nil, thenPrintThisString: "Not downloading!")
            Assert.If(self.beingDownloaded!.count != 0, thenPrintThisString: "Still files to download!")
            self.beingDownloaded = nil
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    */
    
    /* Compare our local file meta data against the server files to see which indicate download, download-deletion, and download-conflicts.
    
    The result of this call is stored in .beingDownloaded in the SMQueues object.
    beingDownloaded must be nil before this call.
    */
    func checkForDownloads(fromServerFileIndex serverFileIndex:[SMServerFile]) {
    
        Assert.If(self.beingDownloaded != nil, thenPrintThisString: "There are already files being downloaded")
        
        // This is for downloads, download-deletions and download-conflicts.
        let downloadOperations = NSMutableOrderedSet()
        
        for serverFile in serverFileIndex {
            let localFile = SMLocalFile.fetchObjectWithUUID(serverFile.uuid!.UUIDString)
            
            if serverFile.deleted! {
                // File was deleted on the server.
                if localFile != nil  {
                    // Record this as a file to be deleted locally, only if we haven't already done so.
                    if !localFile!.deletedOnServer!.boolValue {
                        let downloadDeletion = SMDownloadDeletion.newObject( fromLocalFileMetaData: localFile!)
                        downloadOperations.addObject(downloadDeletion)
                        
                        // The caller will be responsible for updating local meta data for this file, to mark it as deleted. The caller should do it at a time that will preserve the atomic nature of the operation.
                        // CONFLICT CASE: What if the download-deletion file has been modified (not deleted) locally?
                        if localFile!.pendingUpload() {
                            let downloadConflict = SMDownloadConflict.newObject() as! SMDownloadConflict
                            downloadConflict.conflictType = .DownloadDeletionLocalUpload
                            downloadOperations.addObject(downloadConflict)
                        }
                        
                        // TODO: What about the situation where .deletedOnServer is false, but there is a pending upload-deletion? This doesn't appear to be a conflict, but an possible issue with timing-- about when we let the local app know about the deletion.
                    }
                    // Else: The local meta data indicates we've already know about the server deletion. No need to locally delete again.
                }
                /* Else:
                    Don't have meta data for this file locally. File must have been uploaded, and deleted by other device(s) all without syncing with this device. I don't see any point in creating local meta data for the file given that I'd just need to mark it as deleted.
                */
            }
            else {
                // File not deleted on the server, i.e., this is a download not a download-deletion case.

                if localFile == nil {
                    // Server file doesn't yet exist on the app/client. SMLocalFile meta data needs to be created after download is completed.
                    let downloadFile = SMDownloadFile.newObject(fromServerFile: serverFile, andLocalFileMetaData: nil)
                    downloadOperations.addObject(downloadFile)
                }
                else {
                    Assert.If(nil == serverFile.version, thenPrintThisString: "No version for server file.")
    
                    let serverVersion = serverFile.version
                    let localVersion = localFile!.localVersion!.integerValue
                    
                    if serverVersion == localVersion {
                        // No update. No need to download. [1].
                        continue
                    }
                    else if serverVersion > localVersion {
                        // Server file is updated version of that on app/client.
                        // Server version is greater. Need to download.
                        let downloadFile = SMDownloadFile.newObject(fromServerFile: serverFile, andLocalFileMetaData: localFile!)
                        downloadOperations.addObject(downloadFile)

                        // Handle conflict cases: These are only relevant when downloading an updated version from the server. If the server version hasn't changed (as in [1] above), and we have a pending upload or pending upload-deletion, then this does not indicate a conflict.
                        var conflictType:SMDownloadConflict.ConflictType?
                        
                        // I'm prioritizing deletion as a conflict. Because deletion is final, and a choice has to be made if we only issue a single conflict per file per round of downloads.
                        if localFile!.pendingUploadDeletion() {
                            conflictType = .DownloadLocalUploadDeletion
                        }
                        else if localFile!.pendingUpload() {
                            conflictType = .DownloadLocalUpload
                        }
                        
                        if conflictType != nil {
                            let downloadConflict = SMDownloadConflict.newObject() as! SMDownloadConflict
                            downloadConflict.conflictType = conflictType!
                            downloadOperations.addObject(downloadConflict)
                        }
                    } else { // serverVersion < localVersion
                        Assert.badMojo(alwaysPrintThisString: "This should never happen.")
                    }
                }
            }
        } // End-for
        
        if downloadOperations.count > 0 {
            self.beingDownloaded = downloadOperations
        }
        else {
            self.beingDownloaded = nil
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    // Adds an operation to the uploadsBeingPrepared queue.
    // For uploads and upload-deletions, also causes any other upload change for the same file in the same queue to be removed. (This occurs both when you are adding uploads and upload-deletions). Uploads in already committed queues are not modified and should never be modified-- e.g., a new upload in the being prepared queue never overrides an already commmitted upload. Assumes that the .changedFile property of this change has been set.
    // Returns false for uploads and upload-deletions iff the file has already been deleted locally, or already marked for deletion. In this case, the change has not been added.
    func addToUploadsBeingPrepared(operation:SMUploadOperation) -> Bool {
        if let change = operation as? SMUploadFileOperation  {
            Assert.If(change.localFile == nil, thenPrintThisString: "changedFile property not set!")
            let localFileMetaData:SMLocalFile = change.localFile!
            
            let alreadyDeleted = localFileMetaData.deletedOnServer != nil && localFileMetaData.deletedOnServer!.boolValue
            
            // Pass the deletion change as a param to pendingUploadDeletion, if it is a deletion change, because we don't want to consider the currently being added operation.
            let deletionChange = change as? SMUploadDeletion
            if localFileMetaData.pendingUploadDeletion(excepting: deletionChange) || alreadyDeleted {
                return false
            }
            
            // Remove any prior upload changes in the same queue with the same uuid
            var toBeDeleted = [SMUploadFileOperation]()
            for elem in self.uploadsBeingPrepared!.operations! {
                if let uploadFileChange = elem as? SMUploadFile {
                    if uploadFileChange.localFile!.uuid == localFileMetaData.uuid {
                        toBeDeleted.append(uploadFileChange)
                    }
                }
            }
            
            // I believe this will remove the uploadFileFile change from self.uploadsBeingPrepared!.changes! as well.
            for uploadFileChange in toBeDeleted {
                CoreData.sessionNamed(SMCoreData.name).removeObject(
                    uploadFileChange)
            }
        }

        let newOperations = NSMutableOrderedSet(orderedSet: self.uploadsBeingPrepared!.operations!)
        newOperations.addObject(operation)
        self.uploadsBeingPrepared!.operations = newOperations

        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        return true
    }
    
    // Returns nil if there are no conflicts.
    func downloadConflicts() -> [SMDownloadConflict]? {        
        if nil == self.beingDownloaded {
            return nil
        }
        else {
            let result = self.beingDownloaded!.filter() { downloadOperation in
                if let _ = downloadOperation as? SMDownloadConflict {
                    return true
                }
                else {
                    return false
                }
            }
            if result.count == 0 {
                return nil
            }
            else {
                return (result as! [SMDownloadConflict])
            }
        }
    }
}

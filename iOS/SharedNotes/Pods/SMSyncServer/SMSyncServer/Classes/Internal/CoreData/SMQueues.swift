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
        if self.uploadsBeingPrepared != nil && self.uploadsBeingPrepared!.operations!.count > 0 {
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
            self.beingUploaded!.removeObject()
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
    
    // Adds an operation to the uploadsBeingPrepared queue.
    // For uploads and upload-deletions, also causes any other upload change for the same file in the same queue to be removed. (This occurs both when you are adding uploads and upload-deletions). Uploads in already committed queues are not modified and should never be modified-- e.g., a new upload in the being prepared queue never overrides an already commmitted upload. Assumes that the .changedFile property of this change has been set.
    // Returns false for uploads and upload-deletions iff the file has already been deleted locally, or already marked for deletion. In this case, the change has not been added.
    func addToUploadsBeingPrepared(operation:SMUploadOperation) -> Bool {
        if self.uploadsBeingPrepared == nil {
            self.uploadsBeingPrepared = (SMUploadQueue.newObject() as! SMUploadQueue)
        }
        
        if let change = operation as? SMUploadFileOperation  {
            Assert.If(change.localFile == nil, thenPrintThisString: "changedFile property not set!")
            let localFileMetaData:SMLocalFile = change.localFile!
            
            let alreadyDeleted = localFileMetaData.deletedOnServer
            
            // Pass the deletion change as a param to pendingUploadDeletion, if it is a deletion change, because we don't want to consider the currently being added operation.
            let deletionChange = change as? SMUploadDeletion
            if localFileMetaData.pendingUploadDeletion(excepting: deletionChange) || alreadyDeleted {
                return false
            }
            
            NSLog("self.uploadsBeingPrepared: \(self.uploadsBeingPrepared)")
            NSLog("self.uploadsBeingPrepared!.operations: \(self.uploadsBeingPrepared!.operations)")
            
            // Remove any prior upload changes in the same queue with the same uuid.
            let operations = NSOrderedSet(orderedSet: self.uploadsBeingPrepared!.operations!)
            for elem in operations {
                if let uploadFileChange = elem as? SMUploadFile {
                    if uploadFileChange.localFile!.uuid == localFileMetaData.uuid {
                        uploadFileChange.removeObject()
                    }
                }
            }
        }

        let newOperations = NSMutableOrderedSet(orderedSet: self.uploadsBeingPrepared!.operations!)
        newOperations.addObject(operation)
        self.uploadsBeingPrepared!.operations = newOperations

        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        return true
    }
    
    // Removes & deletes all objects in all queues.
    func flush() {
        self.beingUploaded?.removeObject()
        
        self.uploadsBeingPrepared?.removeObject()
        self.uploadsBeingPrepared = (SMUploadQueue.newObject() as! SMUploadQueue)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        if self.committedUploads != nil {
            SMUploadQueue.removeObjectsInOrderedSet(self.committedUploads!)
        }
        
        if self.beingDownloaded != nil {
            SMDownloadOperation.removeObjectsInOrderedSet(self.beingDownloaded!)
        }
    }
    
    enum DownloadChangeType {
        case DownloadStartup
        case DownloadFile
        case DownloadDeletion
    }
    
    // Returns the subset of the self.beingDownloaded objects that represent downloads, or download-deletions. Doesn't modify the .beingDownloaded queue. Returns nil if there were no objects. Give operationStage as nil to ignore the operationStage of the operations. You must give a nil operationStage unless you give .DownloadFile for the changeType.
    func getBeingDownloadedChanges(changeType:DownloadChangeType, operationStage:SMDownloadFile.OperationStage?=nil) -> [SMDownloadOperation]? {
    
        if self.beingDownloaded == nil {
            return nil
        }
        
        Assert.If(changeType != .DownloadFile && operationStage != nil, thenPrintThisString: "Yikes: Non .DownloadFile but not a nil operationStage")
        
        var result = [SMDownloadOperation]()
        
        for elem in self.beingDownloaded! {
            let operation = elem as? SMDownloadFile
            if operationStage == nil || (operation != nil && operation!.operationStage == operationStage) {
                switch (changeType) {
                case .DownloadStartup:
                    if let startup = elem as? SMDownloadStartup {
                        result.append(startup)
                    }
                    
                case .DownloadFile:
                    if let download = elem as? SMDownloadFile {
                        result.append(download)
                    }
                    
                case .DownloadDeletion:
                    if let deletion = elem as? SMDownloadDeletion {
                        result.append(deletion)
                    }
                }
            }
        }
        
        if result.count == 0 {
            return nil
        }
        else {
            return result
        }
    }
    
    func getBeingDownloadedChange(forUUID uuid:String, andChangeType changeType:DownloadChangeType) -> SMDownloadFileOperation? {
        var result = [SMDownloadFileOperation]()

        for elem in self.beingDownloaded! {
            if let operation = elem as? SMDownloadFileOperation {
                var addOperation = false
                switch changeType {
                case .DownloadFile:
                    if elem is SMDownloadFile {
                        addOperation = true
                    }
                    
                case .DownloadDeletion:
                    if elem is SMDownloadDeletion {
                        addOperation = true
                    }
                
                case .DownloadStartup:
                    Assert.badMojo(alwaysPrintThisString: "Should not have this")
                }
            
                if addOperation && operation.localFile!.uuid == uuid {
                    result.append(operation)
                }
            }
        }
        
        if result.count == 0 {
            return nil
        }
        else if result.count == 1 {
            return result[0]
        }
        else {
            Assert.badMojo(alwaysPrintThisString: "More than one download change for UUID \(uuid)")
            return nil
        }
    }
    
    // Removes a particular subset of the self.beingDownloaded objects.
    func removeBeingDownloadedChanges(changeType:DownloadChangeType) {
        if let changes = self.getBeingDownloadedChanges(changeType) {
            for change in changes {
                change.removeObject()
            }
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
}

//
//  SMUploadQueue.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMUploadQueue: NSManagedObject, CoreDataModel {
    
    class func entityName() -> String {
        return "SMUploadQueue"
    }

    class func newObject() -> NSManagedObject {
        let uploadQueue = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMUploadQueue

        uploadQueue.operations = NSOrderedSet()
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return uploadQueue
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
    
    enum ChangeType {
        case UploadFile
        case UploadDeletion
        case UploadWrapup
    }
    
    // Returns the subset of the .operations objects that represent uploads, upload-deletions, or outbound tranfer. Doesn't modify the SMUploadQueue. Returns nil if there were no objects. Give operationStage as nil to ignore the operationStage of the operations. If you give a changeType of UploadWrapup then you must give operationStage as nil.
    func getChanges(changeType:ChangeType, operationStage:SMUploadFileOperation.OperationStage?=nil) -> [SMUploadOperation]? {
    
        Assert.If(changeType == .UploadWrapup && operationStage != nil, thenPrintThisString: "Yikes: Wrapup but not a nil operationStage")
    
        var result = [SMUploadOperation]()
        
        for elem in self.operations! {
            let operation = elem as? SMUploadFileOperation
            if operationStage == nil || (operation != nil && operation!.operationStage == operationStage) {
                switch (changeType) {
                case .UploadFile:
                    if let upload = elem as? SMUploadFile {
                        result.append(upload)
                    }
                    
                case .UploadDeletion:
                    if let deletion = elem as? SMUploadDeletion {
                        result.append(deletion)
                    }
                    
                case .UploadWrapup:
                    if let wrapup = elem as? SMUploadWrapup {
                        result.append(wrapup)
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
    
    func getChange(forUUID uuid:String) -> SMUploadFileOperation? {
        var result = [SMUploadFileOperation]()

        for elem in self.operations! {
            if let operation = elem as? SMUploadFileOperation {
                if operation.localFile!.uuid == uuid {
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
            Assert.badMojo(alwaysPrintThisString: "More than one change for UUID \(uuid)")
            return nil
        }
    }
    
    // Removes the subset of the .operations objects that represent uploads, upload-deletions, or outbound transfer.
    func removeChanges(changeType:ChangeType) {
        if let changes = self.getChanges(changeType) {
            for change in changes {
                change.removeObject()
            }
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    func removeObject() {        
        let operations = NSOrderedSet(orderedSet: self.operations!)
        for elem in operations {
            let uploadOperation = elem as? SMUploadOperation
            Assert.If(nil == uploadOperation, thenPrintThisString: "Didn't get SMUploadOperation object")
            uploadOperation!.removeObject()
        }
        
        CoreData.sessionNamed(SMCoreData.name).removeObject(self)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    // The objects will not be removed directly from the given ordered set, so you can pass a Core Data ordered set relation object.
    class func removeObjectsInOrderedSet(uploadQueues:NSOrderedSet) {
        let queues = NSOrderedSet(orderedSet: uploadQueues)
        for elem in queues {
            let queue = elem as? SMUploadQueue
            Assert.If(nil == queue, thenPrintThisString: "Didn't have SMUploadQueue object")
            queue!.removeObject()
        }
    }
    
    func removeIfNoFileOperations() {
        let uploadFiles = self.getChanges(.UploadFile) as? [SMUploadFile]
        let uploadDeletions = self.getChanges(.UploadDeletion) as? [SMUploadDeletion]
        if uploadFiles == nil && uploadDeletions == nil {
            self.removeObject()
        }
    }
}

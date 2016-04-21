//
//  SMUploadOperation.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMUploadOperation: NSManagedObject {
    func removeObject() {
        CoreData.sessionNamed(SMCoreData.name).removeObject(self)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    // The objects will not be removed directly from the given ordered set, so you can pass a Core Data ordered set relation object.
    class func removeObjectsInOrderedSet(uploadOperationObjects:NSOrderedSet) {
        let uploadOperations = NSOrderedSet(orderedSet: uploadOperationObjects)
        for elem in uploadOperations {
            let uploadOperation = elem as? SMUploadOperation
            Assert.If(nil == uploadOperation, thenPrintThisString: "Didn't have SMUploadOperation object")
            uploadOperation!.removeObject()
        }
    }
}

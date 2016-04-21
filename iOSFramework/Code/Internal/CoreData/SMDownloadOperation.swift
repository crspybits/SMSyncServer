//
//  SMDownloadOperation.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMDownloadOperation: NSManagedObject {
    func removeObject() {
        CoreData.sessionNamed(SMCoreData.name).removeObject(self)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    // The objects will not be removed directly from the given ordered set, so you can pass a Core Data ordered set relation object.
    class func removeObjectsInOrderedSet(downloadOperationObjects:NSOrderedSet) {
        let downloadOperations = NSOrderedSet(orderedSet: downloadOperationObjects)
        for elem in downloadOperations {
            let downloadOperation = elem as? SMDownloadOperation
            Assert.If(nil == downloadOperation, thenPrintThisString: "Didn't have SMDownloadOperation")
            downloadOperation!.removeObject()
        }
    }
}

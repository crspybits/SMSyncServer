//
//  SMDownloadQueue.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMDownloadQueue: NSManagedObject, CoreDataModel {

    class func entityName() -> String {
        return "SMDownloadQueue"
    }

    class func newObject() -> NSManagedObject {
        let downloadQueue = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMDownloadQueue

        downloadQueue.changes = NSOrderedSet()
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return downloadQueue
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
}

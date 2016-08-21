//
//  SMDownloadBlock.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMDownloadBlock: NSManagedObject {
    class func entityName() -> String {
        return "SMDownloadBlock"
    }

    class func newObject() -> NSManagedObject {
        let downloadBlock = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMDownloadBlock

        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return downloadBlock
    }
    
    func removeObject() {
        CoreData.sessionNamed(SMCoreData.name).removeObject(self)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
}

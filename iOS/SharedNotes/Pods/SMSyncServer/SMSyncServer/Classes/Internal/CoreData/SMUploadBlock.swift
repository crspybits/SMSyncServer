//
//  SMUploadBlock.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/3/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMUploadBlock: NSManagedObject {
    class func entityName() -> String {
        return "SMUploadBlock"
    }

    class func newObject() -> NSManagedObject {
        let uploadBlock = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMUploadBlock

        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return uploadBlock
    }
    
    func removeObject() {
        CoreData.sessionNamed(SMCoreData.name).removeObject(self)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
}


//
//  SMUploadDeletion.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMUploadDeletion: SMUploadFileOperation {    
    class func entityName() -> String {
        return "SMUploadDeletion"
    }

    class func newObject() -> NSManagedObject {
        let uploadDeletion = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMUploadDeletion
        
        uploadDeletion.operationStage = .ServerUpload
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return uploadDeletion
    }
}

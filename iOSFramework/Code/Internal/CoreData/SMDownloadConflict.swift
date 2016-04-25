//
//  SMDownloadConflict.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/8/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMDownloadConflict: SMDownloadFileOperation {
    enum ConflictType : String {
        // A download-deletion file has been modified (not deleted) locally
        case DownloadDeletionLocalUpload
        
        // A download file has been upload-deleted locally.
        case DownloadLocalUploadDeletion
        
        // A download file has been modified (not deleted) locally
        case DownloadLocalUpload
    }

    class func entityName() -> String {
        return "SMDownloadConflict"
    }

    class func newObject() -> NSManagedObject {
        let downloadConflict = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMDownloadConflict

        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return downloadConflict
    }
    
    // Don't access internalConflictType directly.
    var conflictType:ConflictType {
        get {
            return ConflictType(rawValue: self.internalConflictType!)!
        }
        
        set {
            self.internalConflictType = newValue.rawValue
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
}

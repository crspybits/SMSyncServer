//
//  SMDownloadDeletion.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMDownloadDeletion: SMDownloadFileOperation, CoreDataModel {

    class func entityName() -> String {
        return "SMDownloadDeletion"
    }

    class func newObject() -> NSManagedObject {
        let fileChange = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMDownloadDeletion
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        return fileChange
    }
    
    class func newObject(withLocalFileMetaData localFileMetaData:SMLocalFile) -> SMDownloadDeletion {
        let downloadFileChange = self.newObject() as! SMDownloadDeletion
        
        downloadFileChange.localFile = localFileMetaData
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return downloadFileChange
    }
}

//
//  SMUploadOutboundTransfer.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMUploadOutboundTransfer: SMUploadOperation {

    class func entityName() -> String {
        return "SMUploadOutboundTransfer"
    }

    class func newObject() -> NSManagedObject {
        let outboundTransfer = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMUploadOutboundTransfer
                
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return outboundTransfer
    }
}

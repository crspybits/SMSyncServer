//
//  SMUploadWrapup.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMUploadWrapup: SMUploadOperation {
    enum WrapupStage : String {
        case OutboundTransfer
        case OutboundTransferWait
        case RemoveOperationId
    }
    
    // Don't access internalWrapupStage directly.
    var wrapupStage : WrapupStage {
        get {
            return WrapupStage(rawValue: self.internalWrapupStage!)!
        }
        set {
            self.internalWrapupStage = newValue.rawValue
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
    
    class func entityName() -> String {
        return "SMUploadWrapup"
    }

    class func newObject() -> NSManagedObject {
        let wrapup = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMUploadWrapup
        wrapup.wrapupStage = .OutboundTransfer
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return wrapup
    }
}

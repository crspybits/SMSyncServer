//
//  SMDownloadStartup.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMDownloadStartup: SMDownloadOperation {
    enum StartupStage : String {
        // SetupInboundTransfer is not a stage here because that is dealt with by detecting the SMDownloadFile's in a CloudStorage operation stage.
        case StartInboundTransfer
        case InboundTransferWait
        case RemoveOperationId
    }
    
    // Don't access internalStartupStage directly.
    var startupStage : StartupStage {
        get {
            return StartupStage(rawValue: self.internalStartupStage!)!
        }
        set {
            self.internalStartupStage = newValue.rawValue
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
    
    class func entityName() -> String {
        return "SMDownloadStartup"
    }

    class func newObject() -> NSManagedObject {
        let startup = CoreData.sessionNamed(
            SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMDownloadStartup
        startup.startupStage = .StartInboundTransfer
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return startup
    }
}

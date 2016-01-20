//
//  SMFileChange.swift
//  
//
//  Created by Christopher Prince on 1/18/16.
//
//

import Foundation
import CoreData
import SMCoreLib

@objc(SMFileChange)
class SMFileChange: NSManagedObject, CoreDataModel {

    class func entityName() -> String {
        return "SMFileChange"
    }

    class func newObject() -> NSManagedObject {
        
        let fileChange = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMFileChange
        
        fileChange.deletion = false
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        return fileChange
    }
}

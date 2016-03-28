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

/* Core Data model notes:
    1) filePathBaseURLType is the raw value of the SMRelativeLocalURL BaseURLType (nil if file change indicates a deletion).
    2) filePath is the relative path of the URL in the case of a local relative url or the path for other urls (nil if file change indicates a deletion).
*/

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
    
    // Returns nil if the file change indicates a deletion. Don't use self.internalRelativeLocalURL directly.
    var fileURL: SMRelativeLocalURL? {
        get {
            if nil == self.internalRelativeLocalURL {
                return nil
            }
            
            let url = NSKeyedUnarchiver.unarchiveObjectWithData(self.internalRelativeLocalURL!) as? SMRelativeLocalURL
            Assert.If(url == nil, thenPrintThisString: "Yikes: No URL!")
            return url
        }
        
        set {
            if newValue == nil {
                self.internalRelativeLocalURL = nil
            }
            else {
                self.internalRelativeLocalURL = NSKeyedArchiver.archivedDataWithRootObject(newValue!)
            }
        }
    }
}

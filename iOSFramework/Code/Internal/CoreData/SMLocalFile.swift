//
//  SMLocalFile.swift
//  
//
//  Created by Christopher Prince on 1/18/16.
//
//

import Foundation
import CoreData
import SMCoreLib

@objc(SMLocalFile)
class SMLocalFile: NSManagedObject, CoreDataModel {
    static let UUID_KEY = "uuid"
    
    class func entityName() -> String {
        return "SMLocalFile"
    }

    class func newObjectAndMakeUUID(makeUUID: Bool) -> NSManagedObject {
        let localFile = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMLocalFile
        
        if makeUUID {
            localFile.uuid = UUID.make()
        }
        
        // First version of a file *must* be 0.
        localFile.localVersion = 0
        
        localFile.pendingUploads = NSOrderedSet()
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return localFile
    }
    
    class func newObject() -> NSManagedObject {
        return self.newObjectAndMakeUUID(false)
    }
    
    class func fetchAllObjects() -> [AnyObject]? {
        var resultObjects:[AnyObject]? = nil
        
        do {
            try resultObjects = CoreData.sessionNamed(SMCoreData.name).fetchAllObjectsWithEntityName(self.entityName())
        } catch (let error) {
            // Somehow, and sometimes, this is throwing an error if there are no result objects. But I'm not returning an error from fetchAllObjectsWithEntityName. Odd.
            // Some ideas from Chris Chares on dealing with this issue if it keeps cropping up: https://gist.github.com/ChrisChares/aab07590ab28ac8da05e
            // See also the link he passed along: https://developer.apple.com/library/ios/documentation/Swift/Conceptual/BuildingCocoaApps/AdoptingCocoaDesignPatterns.html#//apple_ref/doc/uid/TP40014216-CH7-ID6
            Log.msg("Error in fetchAllObjects: \(error)")
        }
        
        return resultObjects
    }
    
    class func fetchObjectWithUUID(uuid:String) -> SMLocalFile? {
        let managedObject = CoreData.fetchObjectWithUUID(uuid, usingUUIDKey: UUID_KEY, fromEntityName: SMLocalFile.entityName(), coreDataSession: CoreData.sessionNamed(SMCoreData.name))
        return managedObject as? SMLocalFile
    }
    
    func locallyChanged() -> Bool {
        return self.pendingUploads!.count > 0;
    }
    
    // Returns true if any of the .pendingUploads are SMUploadFile's
    func pendingUpload() -> Bool {
        var result:Bool = false
        
        if self.pendingUploads != nil {
            for fileChange in self.pendingUploads! {
                if let _ = fileChange as? SMUploadFile {
                    result = true
                    break
                }
            }
        }
        
        return result
    }
    
    // There is a pending upload-deletion if *any* of the SMUploadFileChange's in the .pendingUploads is an SMUploadDeletion.
    func pendingUploadDeletion(excepting excepting:SMUploadDeletion?=nil) -> Bool {
        var result:Bool = false
        
        if self.pendingUploads != nil {
            for fileChange in self.pendingUploads! {
                if let deletion = fileChange as? SMUploadDeletion {
                    if excepting == nil || !excepting!.isEqual(deletion) {
                        result = true
                        break
                    }
                }
            }
        }
        
        return result
    }
}

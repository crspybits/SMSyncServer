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

/* Core Data notes:
I'm including the property internalUserId (from the SMSyncServer) so that when the user signs out of a cloud storage account, or changes to a new cloud storage account, we don't have to flush file meta data-- doing so could incur an expensive download next time that cloud storage account is used.
*/

@objc(SMLocalFile)
class SMLocalFile: NSManagedObject, CoreDataModel {
    static let UUID_KEY = "uuid"
    private static let internalUserIdKey = "internalUserId"
    
    class func entityName() -> String {
        return "SMLocalFile"
    }

    class func newObject(withInternalUserId internalUserId:String, andMakeUUID makeUUID: Bool) -> SMLocalFile {
        let localFile = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMLocalFile
        
        if makeUUID {
            Assert.If(!localFile.respondsToSelector("setUuid:"), thenPrintThisString: "Yikes: No uuid property on managed object")
            localFile.uuid = UUID.make()
        }
        
        localFile.internalUserId = internalUserId
        localFile.pendingLocalChanges = NSOrderedSet()

        // First version of a file *must* be 0. See SMFileChange.swift.
        localFile.localVersion = 0
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return localFile
    }
    
    class func newObject(withInternalUserId internalUserId:String) -> SMLocalFile {
        return self.newObject(withInternalUserId: internalUserId, andMakeUUID: false)
    }
    
    // Returns nil if there are no objects.
    private class func fetchObjects(modifyingRequestWith:(fetchRequest:NSFetchRequest)->()) -> [SMLocalFile]? {
        var resultObjects:[SMLocalFile]?
        
        do {
            try resultObjects = CoreData.sessionNamed(SMCoreData.name).fetchObjectsWithEntityName(self.entityName()) { request in
            
                modifyingRequestWith(fetchRequest: request)

            } as? [SMLocalFile]

        } catch (let error) {
            // try resultObjects = CoreData.sessionNamed(SMCoreData.name).fetchAllObjectsWithEntityName(self.entityName())
            // Somehow, and sometimes, the above was throwing an error if there are no result objects. But I'm not returning an error from fetchAllObjectsWithEntityName. Odd.
            // Some ideas from Chris Chares on dealing with this issue if it keeps cropping up: https://gist.github.com/ChrisChares/aab07590ab28ac8da05e
            // See also the link he passed along: https://developer.apple.com/library/ios/documentation/Swift/Conceptual/BuildingCocoaApps/AdoptingCocoaDesignPatterns.html#//apple_ref/doc/uid/TP40014216-CH7-ID6
            Log.msg("Error in fetchAllObjects: \(error)")
            resultObjects = nil
        }
        
        if resultObjects != nil && resultObjects!.count == 0 {
            resultObjects = nil
        }
        
        return resultObjects
    }
    
    // Returns nil if there are no objects.
    class func fetchObjects(withInternalUserId internalUserId:String) -> [SMLocalFile]? {
        return self.fetchObjects() { request in
            request.predicate = NSPredicate(format: "(%K == %@)", internalUserIdKey, internalUserId)
        }
    }
    
    // Returns nil if there was no object.
    class func fetchObject(withInternalUserId internalUserId:String, andUuid uuid:String) -> SMLocalFile? {
        let result = self.fetchObjects() { request in
            let predicate1 = NSPredicate(format: "(%K == %@)", internalUserIdKey, internalUserId)
            let predicate2 = NSPredicate(format: "(%K == %@)", UUID_KEY, uuid)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate1, predicate2])
        }
        
        if result == nil {
            return nil
        }
        else if result!.count == 1 {
            return result![0]
        }
        else {
            Assert.badMojo(alwaysPrintThisString: "More than one objects in result!")
            return nil
        }
    }
    
    var locallyChanged:Bool {
        return self.pendingLocalChanges!.count > 0;
    }
    
    func getMostRecentChangeAndFlush() -> SMFileChange? {
        var result:SMFileChange?
        
        if self.locallyChanged {
            result = self.pendingLocalChanges!.lastObject as? SMFileChange
            if self.pendingLocalChanges != nil && self.pendingLocalChanges!.count > 1 {
                self.pendingLocalChanges = NSOrderedSet(object: result!)
            }
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        return result
    }
    
    var pendingDeletion:Bool {
        var result:Bool = false
        
        if self.pendingLocalChanges != nil {
            for fileChange in self.pendingLocalChanges! {
                if (fileChange as! SMFileChange).deletion!.boolValue {
                    result = true
                    break
                }
            }
        }
        
        return result
    }

    //Because Apple's built in implementation still doesn't work :(.
    //2015-12-13 23:09:24.836 NetDb[2050:1314449] *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '*** -[NSSet intersectsSet:]: set argument is not an NSSet'
    //See http://stackoverflow.com/questions/7385439/exception-thrown-in-nsorderedset-generated-accessors

    func addPendingLocalChangesObject(value:SMFileChange) {
        let tempSet = NSMutableOrderedSet(orderedSet: self.pendingLocalChanges!)
        tempSet.addObject(value)
        self.pendingLocalChanges = tempSet
    }
    
    func removeOldestChange() -> SMFileChange? {
        var result:SMFileChange?
        
        if self.locallyChanged {
            let changes = NSMutableOrderedSet(orderedSet: self.pendingLocalChanges!)
            result = changes[0] as? SMFileChange
            changes.removeObjectAtIndex(0)
            self.pendingLocalChanges = changes
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
        
        return result
    }
}

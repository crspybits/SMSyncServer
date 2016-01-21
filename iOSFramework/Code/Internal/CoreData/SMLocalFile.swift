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
            Assert.If(!localFile.respondsToSelector("setUuid:"), thenPrintThisString: "Yikes: No uuid property on managed object")
            localFile.uuid = UUID.make()
        }
        
        // First version of a file *must* be 0. See SMFileChange.swift.
        localFile.localVersion = 0
        
        localFile.pendingLocalChanges = NSOrderedSet()
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
            Log.msg("Error in fetchAllObjects: \(error)")
        }
        
        return resultObjects
    }
    
    class func fetchObjectWithUUID(uuid:String) -> SMLocalFile? {
        var localFiles:[SMLocalFile]?
        
        Log.msg("Looking for UUID: \(uuid)");

        do {
            let result = try CoreData.sessionNamed(SMCoreData.name).fetchObjectsWithEntityName(SMLocalFile.entityName()) { (request: NSFetchRequest!) in
                // This doesn't seem to work
                //NSString *predicateFormat = [NSString stringWithFormat:@"(%@ == %%s)", UUID_KEY];
                // See https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/Predicates/Articles/pSyntax.html
                // And http://stackoverflow.com/questions/15505208/creating-nspredicate-dynamically-by-setting-the-key-programmatically
            
                request.predicate = NSPredicate(format: "(%K == %@)", UUID_KEY, uuid)
            }
            
            localFiles = result as? [SMLocalFile]
            
        } catch (let error) {
            Log.msg("\(error)")
        }
        
        var localFile:SMLocalFile?
        
        if nil != localFiles {
            if localFiles!.count > 1 {
                Log.error("There is more than one object with that UUID: \(uuid)");
            }
            else if localFiles!.count == 1 {
                localFile = localFiles![0]
            }
            
            // Could still have 0 localFiles-- returning nil in that case.
        }
        
        return localFile
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

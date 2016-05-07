//
//  Note.swift
//  
//
//  Created by Christopher Prince on 5/4/16.
//
//

import Foundation
import CoreData
import SMCoreLib
import SMSyncServer

class Note: NSManagedObject {
    static let DATE_KEY = "internalDateModified"
    static let UUID_KEY = "uuid"

    // Not based on server info-- just a rough idea of the time when the data changed.
    var dateModified:NSDate? {
        return self.internalDateModified
    }
    
    // Only call this to make user-driven changes to the note.
    var text:String? {
        set {
            self.updateText(newValue)
            
            if let data = newValue?.dataUsingEncoding(NSUTF8StringEncoding) {
                let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: self.uuid!)!, mimeType: "text/plain", andRemoteFileName: self.uuid!)
                SMSyncServer.session.uploadData(data, withDataAttributes: attr)
                SMSyncServer.session.commit()
            }
            else {
                Log.error("Could not convert data: \(newValue)")
            }
        }
        
        get {
            return self.internalText
        }
    }
    
    // Call this based on sync-driven changes to the note. Creates the note if needed.
    // TODO: Need some kind of locking here to deal with the possiblity that the user might be modifying the note at the same time as we receive the download.
    class func createOrUpdate(usingUUID uuid:NSUUID, fromFileAtURL fileURL:NSURL) {
        var note = self.fetch(withUUID: uuid)
        if note == nil {
            Log.special("Couldn't find uuid: \(uuid); creating new Note")
            note = (Note.newObjectAndMakeUUID(false) as! Note)
            note!.uuid = uuid.UUIDString
        }
        
        if let data = NSData(contentsOfURL: fileURL),
            let text = String(data: data, encoding: NSUTF8StringEncoding) {
            note!.updateText(text)
        }
        else {
            Log.error("Problem updating note for: \(uuid)")
        }
        
        CoreData.sessionNamed(CoreDataSession.name).saveContext()
    }
    
    private func updateText(text:String?) {
        self.internalText = text
        self.internalDateModified = NSDate()
        CoreData.sessionNamed(CoreDataSession.name).saveContext()
    }
    
    class func entityName() -> String {
        return "Note"
    }

    class func newObjectAndMakeUUID(makeUUID: Bool) -> NSManagedObject {
        let note = CoreData.sessionNamed(CoreDataSession.name).newObjectWithEntityName(self.entityName()) as! Note
        
        if makeUUID {
            note.uuid = UUID.make()
        }
        
        note.internalDateModified = NSDate()
        
        CoreData.sessionNamed(CoreDataSession.name).saveContext()

        return note
    }
    
    class func newObject() -> NSManagedObject {
        return self.newObjectAndMakeUUID(false)
    }
    
    class func fetchRequestForAllObjects() -> NSFetchRequest? {
        var fetchRequest: NSFetchRequest?
        fetchRequest = CoreData.sessionNamed(CoreDataSession.name).fetchRequestWithEntityName(self.entityName(), modifyingFetchRequestWith: nil)
        
        if fetchRequest != nil {
            let sortDescriptor = NSSortDescriptor(key: DATE_KEY, ascending: false)
            fetchRequest!.sortDescriptors = [sortDescriptor]
        }
        
        return fetchRequest
    }
    
    func removeObject() {
        CoreData.sessionNamed(CoreDataSession.name).removeObject(self)
        CoreData.sessionNamed(CoreDataSession.name).saveContext()
    }
    
    // Returns nil if no Note found.
    class func fetch(withUUID uuid:NSUUID) -> Note? {
        return CoreData.fetchObjectWithUUID(uuid.UUIDString, usingUUIDKey: UUID_KEY, fromEntityName: self.entityName(), coreDataSession: CoreData.sessionNamed(CoreDataSession.name)) as? Note
    }
}

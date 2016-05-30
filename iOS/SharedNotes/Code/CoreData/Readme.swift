//
//  Readme.swift
//  
//
//  Created by Christopher Prince on 5/29/16.
//
//

import Foundation
import CoreData
import SMCoreLib
import SMSyncServer

class Readme: NSManagedObject {
    static let UUID_KEY = "uuid"

   class func entityName() -> String {
        return "Readme"
    }

    class func newObjectAndMakeUUID(makeUUID makeUUID: Bool) -> NSManagedObject {
        let readme = CoreData.sessionNamed(CoreDataExtras.sessionName).newObjectWithEntityName(self.entityName()) as! Readme
        
        if makeUUID {
            readme.uuid = UUID.make()
        }
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
        
        return readme
    }
    
    class func newObject() -> NSManagedObject {
        return self.newObjectAndMakeUUID(makeUUID: false)
    }
    
    // Returns nil if no Readme found.
    class func fetch(withUUID uuid:NSUUID) -> Readme? {
        return CoreData.fetchObjectWithUUID(uuid.UUIDString, usingUUIDKey: UUID_KEY, fromEntityName: self.entityName(), coreDataSession: CoreData.sessionNamed(CoreDataExtras.sessionName)) as? Readme
    }
    
    static let mimeType = "text/plain"
    static let fileName = "README.txt"
    
    class func createAndUploadIfNeeded(downloadedUUID downloadedUUID:String?=nil) throws {
        Log.msg("README upload")
        
        var readmes:[Readme]?
        
        do {
            try readmes = CoreData.sessionNamed(CoreDataExtras.sessionName).fetchAllObjectsWithEntityName(self.entityName()) as? [Readme]
        } catch (let error) {
            Log.msg("Error fetching readme's: \(error)")
            return
        }
        
        Assert.If(readmes != nil && readmes!.count > 1, thenPrintThisString: "More than one readme!")
        
        let existingLocalReadme = readmes != nil && readmes!.count == 1
        let existingServerReadme = downloadedUUID != nil

        if existingLocalReadme {
            if existingServerReadme {
                if readmes![0].uuid! != downloadedUUID! {
                    // Use server readme UUID
                    readmes![0].uuid = downloadedUUID!
                }
                // Else: Our local Readme had the same UUID as the server's. Nothing to do.
            }
        }
        else {
            let newReadme = self.newObjectAndMakeUUID(makeUUID: !existingServerReadme) as! Readme
            if existingServerReadme {
                newReadme.uuid = downloadedUUID!
            }
            
            if !existingServerReadme {
                let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: newReadme.uuid!)!, mimeType: Readme.mimeType, andRemoteFileName: self.fileName)
                attr.appMetaData = SMAppMetaData()
                attr.appMetaData![CoreDataExtras.objectDataTypeKey] = CoreDataExtras.objectDataTypeReadme

                let url = SMRelativeLocalURL(withRelativePath: self.fileName, toBaseURLType: .MainBundle)!
                
                try SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: attr)
                try SMSyncServer.session.commit()
            }
        }
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}

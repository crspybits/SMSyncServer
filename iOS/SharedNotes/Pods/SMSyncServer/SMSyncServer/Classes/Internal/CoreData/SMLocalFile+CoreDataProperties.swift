//
//  SMLocalFile+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 5/24/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMLocalFile {

    @NSManaged var internalAppMetaData: NSData?
    @NSManaged var internalDeletedOnServer: NSNumber?
    @NSManaged var internalSyncState: String?
    @NSManaged var localVersion: NSNumber?
    @NSManaged var mimeType: String?
    @NSManaged var remoteFileName: String?
    @NSManaged var uuid: String?
    @NSManaged var downloadOperations: NSOrderedSet?
    @NSManaged var pendingUploads: NSOrderedSet?

}

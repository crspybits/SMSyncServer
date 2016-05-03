//
//  SMLocalFile+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/30/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMLocalFile {

    @NSManaged var appFileType: String?
    @NSManaged var internalDeletedOnServer: NSNumber?
    @NSManaged var localVersion: NSNumber?
    @NSManaged var mimeType: String?
    @NSManaged var internalSyncState: String?
    @NSManaged var remoteFileName: String?
    @NSManaged var uuid: String?
    @NSManaged var downloadOperations: NSOrderedSet?
    @NSManaged var pendingUploads: NSOrderedSet?

}
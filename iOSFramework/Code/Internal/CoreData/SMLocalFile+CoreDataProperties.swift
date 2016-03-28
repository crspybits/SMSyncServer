//
//  SMLocalFile+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 3/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMLocalFile {

    @NSManaged var appFileType: String?
    @NSManaged var internalUserId: String?
    @NSManaged var deletedOnServer: NSNumber?
    @NSManaged var localVersion: NSNumber?
    @NSManaged var mimeType: String?
    @NSManaged var remoteFileName: String?
    @NSManaged var uuid: String?
    @NSManaged var pendingLocalChanges: NSOrderedSet?

}

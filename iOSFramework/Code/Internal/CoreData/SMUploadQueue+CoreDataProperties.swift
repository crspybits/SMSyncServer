//
//  SMUploadQueue+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMUploadQueue {

    @NSManaged var beingUploaded: SMQueues?
    @NSManaged var operations: NSOrderedSet?
    @NSManaged var committedUploads: SMQueues?
    @NSManaged var uncommittedUploads: SMQueues?

}

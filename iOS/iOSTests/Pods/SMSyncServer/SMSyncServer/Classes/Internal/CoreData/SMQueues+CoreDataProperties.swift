//
//  SMQueues+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/12/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMQueues {

    @NSManaged var internalBeingDownloaded: NSOrderedSet?
    @NSManaged var beingUploaded: SMUploadQueue?
    @NSManaged var internalCommittedUploads: NSOrderedSet?
    @NSManaged var uploadsBeingPrepared: SMUploadQueue?

}

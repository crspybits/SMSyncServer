//
//  SMDownloadQueue+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMDownloadQueue {

    @NSManaged var changes: NSOrderedSet?
    @NSManaged var beingDownloaded: SMQueues?

}

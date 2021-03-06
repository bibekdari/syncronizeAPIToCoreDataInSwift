//
//  Person+CoreDataProperties.swift
//  coreDataSync
//
//  Created by DARI on 1/6/16.
//  Copyright © 2016 DARI. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Person {

    @NSManaged var address: String?
    @NSManaged var createdAt: NSDate?
    @NSManaged var delete: NSNumber?
    @NSManaged var name: String?
    @NSManaged var updatedAt: NSDate?
    @NSManaged var objectIDInAPI: String?

}

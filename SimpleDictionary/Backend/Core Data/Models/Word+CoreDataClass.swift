//
//  Word+CoreDataClass.swift
//  SimpleDictionary
//
//  Created by Oleg Kosenko on 2020-11-13.
//
//

import Foundation
import CoreData

@objc(Word)
public class Word: NSManagedObject {

    convenience init(context: NSManagedObjectContext) {
        self.init(context: context)
        id = UUID()
    }
}

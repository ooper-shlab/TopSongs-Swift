//
//  CategoryCache.swift
//  TopSongs
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/6.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Simple LRU (least recently used) cache for Category objects to reduce fetching.
 */

import Foundation
import UIKit
import CoreData

/*
 About the LRU implementation in this class:

 There are many different ways to implement an LRU cache. This class takes a very minimal approach using an integer "access counter". This counter is incremented each time an item is retrieved from the cache, and the item retrieved has a counter that is set to match the counter for the cache as a whole. This is similar to using a timestamp - the access counter for a given cache node indicates at what point it was last used. The counter does not reflect the number of times the node has been used.

 With the access counter, it is easy to iterate over the items in the cache and find the item with the lowest access value. This item is the "least recently used" item.
 */

@objc(CategoryCache)
class CategoryCache: NSObject {
    
    private var _managedObjectContext: NSManagedObjectContext?
    // Number of objects that can be cached
    var cacheSize: Int = 0
    // A dictionary holds the actual cached items
    var cache: [String: CacheNode] = [:]
    var _categoryEntityDescription: NSEntityDescription?
    var _categoryNamePredicateTemplate: NSPredicate?
    // Counter used to determine the least recently touched item.
    var accessCounter: Int = 0
    // Some basic metrics are tracked to help determine the optimal cache size for the problem.
    var totalCacheHitCost: Double = 0.0
    var totalCacheMissCost: Double = 0.0
    var cacheHitCount: Int = 0
    var cacheMissCount: Int = 0
    
    // CacheNode is a simple object to help with tracking cached items
    //
    typealias CacheNode = (objectID: NSManagedObjectID, accessCounter: Int)
    
    
    //MARK: -
    
    
    //MARK: -
    
    override init() {
        
        cacheSize = 15
        accessCounter = 0
        super.init()
    }
    
    deinit {
        
        NSNotificationCenter.defaultCenter().removeObserver(self)
        if cacheHitCount > 0 {NSLog("average cache hit cost:  %f", totalCacheHitCost/Double(cacheHitCount))}
        if cacheMissCount > 0 {NSLog("average cache miss cost: %f", totalCacheMissCost/Double(cacheMissCount))}
        
    }
    
    // Implement the "set" accessor rather than depending on @synthesize so that we can set up registration
    // for context save notifications.
    var managedObjectContext: NSManagedObjectContext? {
        get {
            return _managedObjectContext
        }
        set(aContext) {
            
            if _managedObjectContext != nil {
                NSNotificationCenter.defaultCenter().removeObserver(self, name: NSManagedObjectContextDidSaveNotification, object: _managedObjectContext!)
            }
            _managedObjectContext = aContext
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "managedObjectContextDidSave:", name: NSManagedObjectContextDidSaveNotification, object: _managedObjectContext)
        }
    }
    
    // When a managed object is first created, it has a temporary managed object ID. When the managed object context in which it was created is saved, the temporary ID is replaced with a permanent ID. The temporary IDs can no longer be used to retrieve valid managed objects. The cache handles the save notification by iterating through its cache nodes and removing any nodes with temporary IDs.
    // While it is possible force Core Data to provide a permanent ID before an object is saved, using the method -[ NSManagedObjectContext obtainPermanentIDsForObjects:error:], this method incurrs a trip to the database, resulting in degraded performance - the very thing we are trying to avoid.
    @objc func managedObjectContextDidSave(notification: NSNotification) {
        
        var keys: [String] = []
        for (key, cacheNode) in cache {
            if cacheNode.objectID.temporaryID {
                keys.append(key)
            }
        }
        keys.forEach{cache.removeValueForKey($0)}
    }
    
    var categoryEntityDescription: NSEntityDescription? {
        get {
            
            if _categoryEntityDescription == nil {
                _categoryEntityDescription = NSEntityDescription.entityForName("Category", inManagedObjectContext: _managedObjectContext!)
            }
            return _categoryEntityDescription
        }
        set {
            _categoryEntityDescription = newValue
        }
    }
    
    private let kCategoryNameSubstitutionVariable = "NAME"
    
    var categoryNamePredicateTemplate: NSPredicate? {
        get {
            
            if _categoryNamePredicateTemplate == nil {
                let leftHand = NSExpression(forKeyPath: "name")
                let rightHand = NSExpression(forVariable: kCategoryNameSubstitutionVariable)
                _categoryNamePredicateTemplate = NSComparisonPredicate(leftExpression: leftHand, rightExpression: rightHand, modifier: .DirectPredicateModifier, type: .LikePredicateOperatorType, options: [])
            }
            return _categoryNamePredicateTemplate
        }
        set {
            _categoryNamePredicateTemplate = newValue
        }
    }
    
    // Undefine this macro to compare performance without caching
    private let USE_CACHING = false//true
    
    func categoryWithName(name: String) -> Category? {
        
        let before = NSDate.timeIntervalSinceReferenceDate()
        if USE_CACHING {
            // check cache
            if var cacheNode = cache[name] {
                // cache hit, update access counter
                cacheNode.accessCounter = accessCounter++
                let category = managedObjectContext?.objectWithID(cacheNode.objectID) as! Category?
                totalCacheHitCost += (NSDate.timeIntervalSinceReferenceDate() - before)
                cacheHitCount++
                return category
            }
        }
        // cache missed, fetch from store - if not found in store there is no category object for the name and we must create one
        let fetchRequest = NSFetchRequest()
        fetchRequest.entity = self.categoryEntityDescription
        let predicate = self.categoryNamePredicateTemplate?.predicateWithSubstitutionVariables([kCategoryNameSubstitutionVariable: name])
        fetchRequest.predicate = predicate
        let fetchResults: [AnyObject]
        do {
            fetchResults = try managedObjectContext!.executeFetchRequest(fetchRequest)
        } catch let error as NSError {
            fatalError("Unhandled error executing fetch request in import thread: \(error.localizedDescription)")
        }
        
        let category: Category
        if !fetchResults.isEmpty {
            // get category from fetch
            category = fetchResults[0] as! Category
        } else {
            // category not in store, must create a new category object
            category = Category(entity: self.categoryEntityDescription!, insertIntoManagedObjectContext:_managedObjectContext!)
            category.name = name
        }
        if USE_CACHING {
            // add to cache
            // first check to see if cache is full
            if cache.count >= cacheSize {
                // evict least recently used (LRU) item from cache
                let (keyOfOldestCacheNode, _) = cache.minElement{$0.1.accessCounter < $1.1.accessCounter}!
                // remove from the cache
                cache.removeValueForKey(keyOfOldestCacheNode)
            }
            let cacheNode = (category.objectID, accessCounter++)
            cache[name] = cacheNode
        }
        totalCacheMissCost += (NSDate.timeIntervalSinceReferenceDate() - before)
        cacheMissCount++
        return category
    }
    
}
//
//  Category.swift
//  TopSongs
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/5.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Managed object subclass for Category entity.
 */

import CoreData

@objc(Category)
class Category: NSManagedObject {

    @NSManaged var name: String?
    @NSManaged var songs: Set<Song>?

}

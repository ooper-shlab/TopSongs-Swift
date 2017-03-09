//
//  Song.swift
//  TopSongs
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/5.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Managed object subclass for Song entity.
 */

import CoreData

@objc(Song)
class Song: NSManagedObject {

    @NSManaged var title: String?
    @NSManaged var category: Category?
    @NSManaged var rank: NSNumber?
    @NSManaged var album: String?
    @NSManaged var releaseDate: Date?
    @NSManaged var artist: String?

}

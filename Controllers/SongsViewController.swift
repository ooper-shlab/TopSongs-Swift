//
//  SongsViewController.swift
//  TopSongs
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/6.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Lists all songs in a table view. Also allows sorting and grouping via bottom segmented control.
 */

import UIKit
import CoreData

@objc(SongsViewController)
class SongsViewController: UITableViewController {
    
    var managedObjectContext: NSManagedObjectContext?
    
    private var detailController: SongDetailsController?
    private var _fetchedResultsController: NSFetchedResultsController?
    @IBOutlet private var fetchSectioningControl: UISegmentedControl!
    
    
    //MARK: -
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        self.fetch()   // start fetching songs from our data store
    }
    
    @IBAction func changeFetchSectioning(_: AnyObject) {
        
        self.fetchedResultsController = nil
        self.fetch()
    }
    
    func fetch() {
        
        do {
            try self.fetchedResultsController?.performFetch()
        } catch let error as NSError {
            NSLog("Unhandled error performing fetch at SongsViewController.m, line %d: %@", Int32(#line), error.localizedDescription)
        }
        self.tableView.reloadData()
    }
    
    private var fetchedResultsController: NSFetchedResultsController? {
        get {
            
            if _fetchedResultsController == nil {
                let fetchRequest = NSFetchRequest()
                fetchRequest.entity = NSEntityDescription.entityForName("Song", inManagedObjectContext: self.managedObjectContext!)
                let sortDescriptors: [NSSortDescriptor]
                var sectionNameKeyPath: String? = nil
                if self.fetchSectioningControl.selectedSegmentIndex == 1 {
                    sortDescriptors = [NSSortDescriptor(key: "category.name", ascending: true), NSSortDescriptor(key: "rank", ascending: true)]
                    sectionNameKeyPath = "category.name"
                } else {
                    sortDescriptors = [NSSortDescriptor(key: "rank", ascending: true)]
                }
                fetchRequest.sortDescriptors = sortDescriptors
                _fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                    managedObjectContext: self.managedObjectContext!,
                    sectionNameKeyPath: sectionNameKeyPath,
                    cacheName: nil)
            }
            return _fetchedResultsController!
        }
        set {
            _fetchedResultsController = newValue
        }
    }
    
    
    //MARK: - UITableViewDataSource
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        
        return self.fetchedResultsController?.sections?.count ?? 0
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        let sectionInfo = self.fetchedResultsController?.sections?[section]
        return sectionInfo?.numberOfObjects ?? 0
    }
    
    override func tableView(tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        
        let sectionInfo = self.fetchedResultsController?.sections?[section]
        if self.fetchSectioningControl.selectedSegmentIndex == 0 {
            return String(format: NSLocalizedString("Top %d songs", comment: "Top %d songs"), sectionInfo?.numberOfObjects ?? 0)
        } else {
            return String(format: NSLocalizedString("%@ - %d songs", comment: "%@ - %d songs"), sectionInfo?.name ?? "", sectionInfo?.numberOfObjects ?? 0)
        }
    }
    
    override func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]? {
        
        // return list of section titles to display in section index view (e.g. "ABCD...Z#")
        return self.fetchedResultsController?.sectionIndexTitles
    }
    
    override func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int {
        
        // tell table which section corresponds to section title/index (e.g. "B",1))
        return self.fetchedResultsController?.sectionForSectionIndexTitle(title, atIndex: index) ?? 0
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let kCellIdentifier = "SongCell"
        
        let cell = self.tableView.dequeueReusableCellWithIdentifier(kCellIdentifier, forIndexPath: indexPath)
        let song = self.fetchedResultsController?.objectAtIndexPath(indexPath) as! Song?
        cell.textLabel!.text = String(format: NSLocalizedString("#%d %@", comment: "#%d %@"), song?.rank?.integerValue ?? 0, song?.title ?? "")
        
        return cell
    }
    
    
    //MARK: - Segue support
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        
        if segue.identifier == "showDetail" {
            
            let detailsController = segue.destinationViewController as! SongDetailsController
            let selectedIndexPath = self.tableView.indexPathForSelectedRow!
            detailsController.song = self.fetchedResultsController?.objectAtIndexPath(selectedIndexPath) as! Song?
        }
    }
    
}
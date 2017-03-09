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
    private var _fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>?
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
        } catch let error {
            NSLog("Unhandled error performing fetch at SongsViewController.m, line %d: %@", Int32(#line), error.localizedDescription)
        }
        self.tableView.reloadData()
    }
    
    private var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>? {
        get {
            
            if _fetchedResultsController == nil {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
                fetchRequest.entity = NSEntityDescription.entity(forEntityName: "Song", in: self.managedObjectContext!)
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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        
        return self.fetchedResultsController?.sections?.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        let sectionInfo = self.fetchedResultsController?.sections?[section]
        return sectionInfo?.numberOfObjects ?? 0
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        
        let sectionInfo = self.fetchedResultsController?.sections?[section]
        if self.fetchSectioningControl.selectedSegmentIndex == 0 {
            return String(format: NSLocalizedString("Top %d songs", comment: "Top %d songs"), sectionInfo?.numberOfObjects ?? 0)
        } else {
            return String(format: NSLocalizedString("%@ - %d songs", comment: "%@ - %d songs"), sectionInfo?.name ?? "", sectionInfo?.numberOfObjects ?? 0)
        }
    }
    
    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        
        // return list of section titles to display in section index view (e.g. "ABCD...Z#")
        return self.fetchedResultsController?.sectionIndexTitles
    }
    
    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        
        // tell table which section corresponds to section title/index (e.g. "B",1))
        return self.fetchedResultsController?.section(forSectionIndexTitle: title, at: index) ?? 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let kCellIdentifier = "SongCell"
        
        let cell = self.tableView.dequeueReusableCell(withIdentifier: kCellIdentifier, for: indexPath)
        let song = self.fetchedResultsController?.object(at: indexPath) as! Song?
        cell.textLabel!.text = String(format: NSLocalizedString("#%d %@", comment: "#%d %@"), song?.rank?.intValue ?? 0, song?.title ?? "")
        
        return cell
    }
    
    
    //MARK: - Segue support
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "showDetail" {
            
            let detailsController = segue.destination as! SongDetailsController
            let selectedIndexPath = self.tableView.indexPathForSelectedRow!
            detailsController.song = self.fetchedResultsController?.object(at: selectedIndexPath) as! Song?
        }
    }
    
}

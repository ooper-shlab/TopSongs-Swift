//
//  SongDetailsController.swift
//  TopSongs
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/5.
//
//
/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Displays details about a song.
 */

import UIKit

@objc(SongDetailsController)
class SongDetailsController: UITableViewController {
    
    var song: Song?
    
    
    //MARK: -
    
    private lazy var dateFormatter: DateFormatter = {
        
        let _dateFormatter = DateFormatter()
        _dateFormatter.dateStyle = .medium
        _dateFormatter.timeStyle = .none
        #if !USE_OLD_RSS
        _dateFormatter.timeZone = TimeZone(identifier: "UTC")
        #endif
        return _dateFormatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self,
            selector: #selector(self.localeChanged(_:)),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self,
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return 4
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let kCellIdentifier = "SongDetailCell"
        
        let cell = self.tableView.dequeueReusableCell(withIdentifier: kCellIdentifier, for: indexPath)
        
        switch indexPath.row {
        case 0:
            cell.textLabel!.text = NSLocalizedString("album", comment: "album label")
            cell.detailTextLabel!.text = self.song?.album ?? "Unknown"
        case 1:
            cell.textLabel!.text = NSLocalizedString("artist", comment: "artist label")
            cell.detailTextLabel!.text = self.song?.artist
        case 2:
            cell.textLabel!.text = NSLocalizedString("category", comment: "category label")
            cell.detailTextLabel!.text = self.song?.category?.name
        case 3:
            cell.textLabel!.text = NSLocalizedString("released", comment: "released label")
            cell.detailTextLabel?.text = self.song?.releaseDate.map{
                self.dateFormatter.string(from: $0)
            } ?? "Unspecified"
        default:
            break
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.song?.title
    }
    
    
    //MARK: - Locale changes
    
    @objc func localeChanged(_ notif: Notification) {
        // The user changed the locale (region format) in Settings, so we are notified here to
        // update the date format in the table view cells.
        //
        self.tableView.reloadData()
    }
    
}

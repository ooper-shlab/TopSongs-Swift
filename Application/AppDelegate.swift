//
//  AppDelegate.swift
//  TopSongs
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/7.
//
//
/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Configures the Core Data persistence stack and starts the RSS importer.
 */

import UIKit
import CoreData

@UIApplicationMain
@objc(AppDelegate)
class AppDelegate: NSObject, UIApplicationDelegate, iTunesRSSImporterDelegate {
    
    
    // String used to identify the update object in the user defaults storage.
    private let kLastStoreUpdateKey = "LastStoreUpdate"
    
    // Get the RSS feed for the first time or if the store is older than kRefreshTimeInterval seconds.
    private let kRefreshTimeInterval: TimeInterval = 3600
    
    // The number of songs to be retrieved from the RSS feed.
    private let kImportSize = 300
    
    private var songsViewController: SongsViewController!
    
    // Properties for the importer and its background processing queue.
    private var importer: iTunesRSSImporter!
    private var _operationQueue: OperationQueue?
    
    // Properties for the Core Data stack.
    private var _managedObjectContext: NSManagedObjectContext?
    private var _persistentStoreCoordinator: NSPersistentStoreCoordinator?
    private var _persistentStoreURL: URL?
    
    
    //MARK: -
    
    // The app delegate must implement the window @property
    // from UIApplicationDelegate @protocol to use a main storyboard file.
    //
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        
        // check the last update, stored in NSUserDefaults
        let lastUpdate = UserDefaults.standard.object(forKey: kLastStoreUpdateKey) as? Date
        if lastUpdate == nil || -lastUpdate!.timeIntervalSinceNow > kRefreshTimeInterval {
            
            // remove the old store; easier than deleting every object
            // first, test for an existing store
            if FileManager.default.fileExists(atPath: self.persistentStoreURL.path) {
                do {
                    try FileManager.default.removeItem(at: self.persistentStoreURL)
                } catch let error {
                    fatalError("Unhandled error adding persistent store in \(#file) at line \(#line): \(error.localizedDescription)")
                }
            }
            
            // create an importer object to retrieve, parse, and import into the CoreData store
            self.importer = iTunesRSSImporter()
            self.importer.delegate = self
            // pass the coordinator so the importer can create its own managed object context
            self.importer.persistentStoreCoordinator = self.persistentStoreCoordinator
            self.importer.iTunesURL = URL(string: "http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wpa/MRSS/newreleases/limit=\(kImportSize)/rss.xml")
            UIApplication.shared.isNetworkActivityIndicatorVisible = true
            
            // add the importer to an operation queue for background processing (works on a separate thread)
            self.operationQueue.addOperation(self.importer)
        }
        
        // obtain our current initial view controller on the nav stack and set it's managed object context
        let navController = self.window!.rootViewController as! UINavigationController
        songsViewController = (navController.visibleViewController as! SongsViewController)
        self.songsViewController.managedObjectContext = self.managedObjectContext
        
        return true
    }
    
    var operationQueue: OperationQueue {
        get {
            
            if _operationQueue == nil {
                _operationQueue = OperationQueue()
            }
            return _operationQueue!
        }
        set {
            _operationQueue = newValue
        }
    }
    
    
    //MARK: - Core Data stack setup
    
    //
    // These methods are very slightly modified from what is provided by the Xcode template
    // An overview of what these methods do can be found in the section "The Core Data Stack"
    // in the following article:
    // http://developer.apple.com/iphone/library/documentation/DataManagement/Conceptual/iPhoneCoreData01/Articles/01_StartingOut.html
    //
    private var persistentStoreCoordinator: NSPersistentStoreCoordinator {
        get {
            
            if _persistentStoreCoordinator == nil {
                let storeUrl = self.persistentStoreURL
                _persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel.mergedModel(from: nil)!)
                do {
                    try _persistentStoreCoordinator!.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeUrl, options: nil)
                } catch let error {
                    fatalError("Unhandled error adding persistent store in \(#file) at line \(#line): \(error.localizedDescription)")
                }
            }
            return _persistentStoreCoordinator!
        }
        set {
            _persistentStoreCoordinator = newValue
        }
    }
    
    private var managedObjectContext: NSManagedObjectContext {
        get {
            
            if _managedObjectContext == nil {
                _managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
                self.managedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
            }
            return _managedObjectContext!
        }
        set {
            _managedObjectContext = newValue
        }
    }
    
    var persistentStoreURL: URL {
        get {
            
            if _persistentStoreURL == nil {
                let URLs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                let documentsURL = URLs.last!
                _persistentStoreURL = documentsURL.appendingPathComponent("TopSongs.sqlite")
            }
            return _persistentStoreURL!
        }
        set {
            _persistentStoreURL = newValue
        }
    }
    
    
    //MARK: - iTunesRSSImporterDelegate
    
    // This method will be called on a secondary thread. Forward to the main thread for safe handling of UIKit objects.
    func importerDidSave(_ saveNotification: Notification) {
        
        if Thread.isMainThread {
            self.managedObjectContext.mergeChanges(fromContextDidSave: saveNotification)
            self.songsViewController.fetch()
        } else {
            DispatchQueue.main.async {
                self.importerDidSave(saveNotification)
            }
        }
    }
    
    // Helper method for main-thread processing of import completion.
    private func handleImportCompletion() {
        
        // Store the current time as the time of the last import.
        // This will be used to determine whether an import is necessary when the application runs.
        UserDefaults.standard.set(Date(), forKey: kLastStoreUpdateKey)
        
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
        self.importer = nil
    }
    
    // This method will be called on a secondary thread. Forward to the main thread for safe handling of UIKit objects.
    func importerDidFinishParsingData(_ importer: iTunesRSSImporter) {
        
        DispatchQueue.main.async {
            self.handleImportCompletion()
        }
    }
    
    // Helper method for main-thread processing of errors received in the delegate callback below.
    private func handleImportError(_ error: Error) {
        
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
        self.importer = nil
        
        // handle errors as appropriate to your application, here we just alert the user
        let errorMessage = error.localizedDescription
        let alertTitle = NSLocalizedString("Error", comment: "Title for alert displayed when download or parse error occurs.")
        let okTitle = NSLocalizedString("OK", comment: "OK")
        
        let alert = UIAlertController(title: alertTitle, message: errorMessage, preferredStyle: .alert)
        
        let action = UIAlertAction(title: okTitle, style: .default) {act in
            self.window!.rootViewController?.dismiss(animated: true, completion: nil)
        }
        
        alert.addAction(action)
        
        self.window!.rootViewController?.present(alert, animated: true, completion: nil)
    }
    
    // This method will be called on a secondary thread. Forward to the main thread for safe handling of UIKit objects.
    func importer(_ importer: iTunesRSSImporter, didFailWithError error: Error) {
        
        DispatchQueue.main.async {
            self.handleImportError(error)
        }
    }
    
}

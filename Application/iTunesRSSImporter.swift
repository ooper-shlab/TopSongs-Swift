//
//  iTunesRSSImporter.swift
//  TopSongs
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/6.
//
//
/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Downloads, parses, and imports the iTunes top songs RSS feed into Core Data.
 */

import UIKit
import CoreData
//#import <libxml/tree.h>
//### See TopSongs-Bridging-Header.h (#import <libxml/tree.h>)

// Protocol for the importer to communicate with its delegate.
@objc(iTunesRSSImporterDelegate)
protocol iTunesRSSImporterDelegate: NSObjectProtocol {
    
    // Notification posted by NSManagedObjectContext when saved.
    @objc optional func importerDidSave(_ saveNotification: Notification)
    // Called by the importer when parsing is finished.
    @objc optional func importerDidFinishParsingData(_ importer: iTunesRSSImporter)
    // Called by the importer in the case of an error.
    @objc optional func importer(_ importer: iTunesRSSImporter, didFailWithError error: Error)
    
}


// Although NSURLConnection is inherently asynchronous, the parsing can be quite CPU intensive on the device, so
// the user interface can be kept responsive by moving that work off the main thread. This does create additional
// complexity, as any code which interacts with the UI must then do so in a thread-safe manner.
//
@objc(iTunesRSSImporter)
class iTunesRSSImporter: Operation, URLSessionDataDelegate {
    
    private var _theCache: CategoryCache?
    
    var iTunesURL: URL?
    weak var delegate: iTunesRSSImporterDelegate?
    var persistentStoreCoordinator: NSPersistentStoreCoordinator?
    
    // Function prototypes for SAX callbacks. This sample implements a minimal subset of SAX callbacks.
    // Depending on your application's needs, you might want to implement more callbacks.
    
    
    //MARK: -
    
    // Class extension for private properties and methods.
    
    // Reference to the libxml parser context
    private var context: xmlParserCtxtPtr? = nil
    
    // The following state variables deal with getting character data from XML elements. This is a potentially expensive
    // operation. The character data in a given element may be delivered over the course of multiple callbacks, so that
    // data must be appended to a buffer. The optimal way of doing this is to use a C string buffer that grows exponentially.
    // When all the characters have been delivered, an NSString is constructed and the buffer is reset.
    fileprivate var storingCharacters: Bool = false
    private var characterBuffer: Data = Data()
    
    // Overall state of the importer, used to exit the run loop.
    private var done: Bool = false
    
    // State variable used to determine whether or not to ignore a given XML element
    fileprivate var parsingASong: Bool = false
    
    // The number of parsed songs is tracked so that the autorelease pool for the parsing thread can be periodically
    // emptied to keep the memory footprint under control.
    private var countForCurrentBatch: Int = 0
    
    // A reference to the current song the importer is working with.
    private var _currentSong: Song?
    
    private var session: URLSession!
    private var sessionTask: URLSessionDataTask?
    
    fileprivate var dateFormatter: DateFormatter!
    
    private var rankOfCurrentSong: Int = 0
    
    
    //MARK: -
    
    static var lookuptime: Double = 0.0
    
    override func main() {
        
        if self.delegate?.responds(to: #selector(iTunesRSSImporterDelegate.importerDidSave(_:))) ?? false {
            NotificationCenter.default.addObserver(self.delegate!,
                selector: #selector(iTunesRSSImporterDelegate.importerDidSave(_:)),
                name: .NSManagedObjectContextDidSave,
                object: self.insertionContext)
        }
        self.done = false
        dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .long
        self.dateFormatter.timeStyle = .none
        // necessary because iTunes RSS feed is not localized, so if the device region has been set to other than US
        // the date formatter must be set to US locale in order to parse the dates
        self.dateFormatter.locale = Locale(identifier: "US")
        characterBuffer = Data()
        
        // create the session with the request and start loading the data
        let request = URLRequest(url: self.iTunesURL!)
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
        sessionTask = self.session.dataTask(with: request)
        if self.sessionTask != nil {
            
            self.sessionTask!.resume()
            
            // This creates a context for "push" parsing in which chunks of data that are not "well balanced" can be passed
            // to the context for streaming parsing. The handler structure defined above will be used for all the parsing.
            // The second argument, self, will be passed as user data to each of the SAX handlers. The last three arguments
            // are left blank to avoid creating a tree in memory.
            //
            context = xmlCreatePushParserCtxt(&simpleSAXHandlerStruct, Unmanaged.passUnretained(self).toOpaque(), nil, 0, nil)
            repeat {
                RunLoop.current.run(mode: .defaultRunLoopMode, before: .distantFuture)
            } while !self.done
            
            // Display the total time spent finding a specific object for a relationship
            NSLog("lookup time %f", iTunesRSSImporter.lookuptime)
            
            // Release resources used only in this thread.
            xmlFreeParserCtxt(self.context)
            characterBuffer = Data()
            self.dateFormatter = nil
            self.currentSong = nil
            theCache = nil
            
            self.insertionContext.performAndWait {
                do {
                    try self.insertionContext.save()
                } catch let saveError {
                    fatalError("Unhandled error saving managed object context in import thread: \(saveError.localizedDescription)")
                }
                
                if self.delegate?.responds(to: #selector(iTunesRSSImporterDelegate.importerDidSave(_:))) ?? false {
                NotificationCenter.default.removeObserver(self.delegate!,
                name:.NSManagedObjectContextDidSave, object: self.insertionContext)
                }
                
                // Call our delegate to signify parse completion.
                self.delegate?.importerDidFinishParsingData?(self)
            }
        }
    }
    
    lazy var insertionContext: NSManagedObjectContext = {
        
        let _insertionContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        _insertionContext.persistentStoreCoordinator = self.persistentStoreCoordinator
        return _insertionContext
    }()
    
    private func forwardError(_ error: Error) {
        
        self.delegate?.importer?(self, didFailWithError: error)
    }
    
    private lazy var songEntityDescription: NSEntityDescription = {
        
        let _songEntityDescription = NSEntityDescription.entity(forEntityName: "Song", in: self.insertionContext)
        return _songEntityDescription!
    }()
    
    private(set) var theCache: CategoryCache! {
        get {
            
            if _theCache == nil {
                _theCache = CategoryCache()
                _theCache!.managedObjectContext = self.insertionContext
            }
            return _theCache
        }
        set {
            _theCache = newValue
        }
    }
    
    fileprivate var currentSong: Song! {
        get {
            
            if _currentSong == nil {
                _currentSong = Song(entity: self.songEntityDescription, insertInto: self.insertionContext)
                rankOfCurrentSong += 1
                _currentSong!.rank = rankOfCurrentSong as NSNumber?
            }
            return _currentSong
        }
        set {
            _currentSong = newValue
        }
    }
    
    
    //MARK: - NSURLSessionDataDelegate methods
    
    // Sent when data is available for the delegate to consume.
    //
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        
        // Process the downloaded chunk of data.
        data.withUnsafeBytes {bytes in
            _ = xmlParseChunk(self.context, bytes, Int32(data.count), 0)
        }
    }
    
    // Sent as the last message related to a specific task.
    // Error may be nil, which implies that no error occurred and this task is complete.
    //
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        if let error = error {
            
            if #available(iOS 9.0, *) {
                if (error as NSError).code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
                    // if you get error NSURLErrorAppTransportSecurityRequiresSecureConnection (-1022),
                    // then your Info.plist has not been properly configured to match the target server.
                    //
                    fatalError("Info.plist has not been properly configured to match the target server.")
                }
            }
            
            DispatchQueue.main.async {
                self.forwardError(error)
            }
        }
        
        // Signal the context that parsing is complete by passing "1" as the last parameter.
        xmlParseChunk(self.context, nil, 0, 1)
        context = nil
        // Set the condition which ends the run loop.
        self.done = true
    }
    
    
    //MARK: - Parsing support methods
    
    private let kImportBatchSize = 20
    
    fileprivate func finishedCurrentSong() {
        
        self.parsingASong = false
        self.currentSong = nil
        self.countForCurrentBatch += 1
        
        if self.countForCurrentBatch == kImportBatchSize {
            
            do {
                try self.insertionContext.save()
            } catch let saveError {
                fatalError("Unhandled error saving managed object context in import thread: \(saveError.localizedDescription)")
            }
            self.countForCurrentBatch = 0
        }
    }
    
    /*
    Character data is appended to a buffer until the current element ends.
    */
    fileprivate func appendCharacters(_ charactersFound: UnsafePointer<xmlChar>, length: Int) {
        
        self.characterBuffer.append(charactersFound, count: length)
    }
    
    fileprivate var currentString: String {
        
        // Create a string with the character data using UTF-8 encoding. UTF-8 is the default XML data encoding.
        let currentString = String(data: self.characterBuffer, encoding: .utf8)
        self.characterBuffer.count = 0
        return currentString!
    }
    
}


//MARK: - SAX Parsing Callbacks

// The following constants are the XML element names and their string lengths for parsing comparison.
// The lengths include the null terminator, to ensure exact matches.
private let kName_Item = "item"
private let kLength_Item = kName_Item.utf8.count + 1
private let kName_Title = "title"
private let kLength_Title = kName_Title.utf8.count + 1
private let kName_Category = "category"
private let kLength_Category = kName_Category.utf8.count + 1
private let kName_Itms = "itms"
private let kLength_Itms = kName_Itms.utf8.count + 1
private let kName_Artist = "artist"
private let kLength_Artist = kName_Artist.utf8.count + 1
private let kName_Album = "album"
private let kLength_Album = kName_Album.utf8.count + 1
private let kName_ReleaseDate = "releasedate"
private let kLength_ReleaseDate = kName_ReleaseDate.utf8.count + 1

/*
This callback is invoked when the importer finds the beginning of a node in the XML. For this application,
out parsing needs are relatively modest - we need only match the node name. An "item" node is a record of
data about a song. In that case we create a new Song object. The other nodes of interest are several of the
child nodes of the Song currently being parsed. For those nodes we want to accumulate the character data
in a buffer. Some of the child nodes use a namespace prefix.
*/
private let startElementSAX: startElementNsSAX2Func = {parsingContext, localname, prefix, URI,
    nb_namespaces, namespaces, nb_attributes, nb_defaulted, attributes in
    
    let importer = Unmanaged<iTunesRSSImporter>.fromOpaque(parsingContext!).takeUnretainedValue()
    // The second parameter to strncmp is the name of the element, which we known from the XML schema of the feed.
    // The third parameter to strncmp is the number of characters in the element name, plus 1 for the null terminator.
    let pLocalname = UnsafeRawPointer(localname!).assumingMemoryBound(to: CChar.self)
    let pPrefix = prefix.map{UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)}
    if prefix == nil && strncmp(pLocalname, kName_Item, kLength_Item) == 0 {
        importer.parsingASong = true
    } else if importer.parsingASong && ( (prefix == nil && (strncmp(pLocalname, kName_Title, kLength_Title) == 0 || strncmp(pLocalname, kName_Category, kLength_Category) == 0)) || ((prefix != nil && strncmp(pPrefix, kName_Itms, kLength_Itms) == 0) && (strncmp(pLocalname, kName_Artist, kLength_Artist) == 0 || strncmp(pLocalname, kName_Album, kLength_Album) == 0 || strncmp(pLocalname, kName_ReleaseDate, kLength_ReleaseDate) == 0)))
    {
        importer.storingCharacters = true
    }
}

/*
This callback is invoked when the parse reaches the end of a node. At that point we finish processing that node,
if it is of interest to us. For "item" nodes, that means we have completed parsing a Song object. We pass the song
to a method in the superclass which will eventually deliver it to the delegate. For the other nodes we
care about, this means we have all the character data. The next step is to create an NSString using the buffer
contents and store that with the current Song object.
*/
private let endElementSAX: endElementNsSAX2Func = {parsingContext, localname, prefix, URI in
    
    let importer = Unmanaged<iTunesRSSImporter>.fromOpaque(parsingContext!).takeUnretainedValue()
    if !importer.parsingASong {return}
    let pLocalname = UnsafeRawPointer(localname!).assumingMemoryBound(to: CChar.self)
    let pPrefix = prefix.map{UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)}
    if prefix == nil {
        if strncmp(pLocalname, kName_Item, kLength_Item) == 0 {
            importer.finishedCurrentSong()
        } else if strncmp(pLocalname, kName_Title, kLength_Title) == 0 {
            importer.currentSong.title = importer.currentString
        } else if strncmp(pLocalname, kName_Category, kLength_Category) == 0 {
            let before = Date.timeIntervalSinceReferenceDate
            let category = importer.theCache.categoryWithName(importer.currentString)
            let delta = Date.timeIntervalSinceReferenceDate - before
            iTunesRSSImporter.lookuptime += delta
            importer.currentSong.category = category
        }
    } else if strncmp(pPrefix, kName_Itms, kLength_Itms) == 0 {
        if strncmp(pLocalname, kName_Artist, kLength_Artist) == 0 {
            importer.currentSong.artist = importer.currentString
        } else if strncmp(pLocalname, kName_Album, kLength_Album) == 0 {
            importer.currentSong.album = importer.currentString
        } else if strncmp(pLocalname, kName_ReleaseDate, kLength_ReleaseDate) == 0 {
            let dateString = importer.currentString
            importer.currentSong.releaseDate = importer.dateFormatter.date(from: dateString)
        }
    }
    importer.storingCharacters = false
}

/*
This callback is invoked when the parser encounters character data inside a node. The importer class determines how to use the character data.
*/
private let charactersFoundSAX: charactersSAXFunc = {parsingContext, characterArray, numberOfCharacters in
    
    let importer = Unmanaged<iTunesRSSImporter>.fromOpaque(parsingContext!).takeUnretainedValue()
    // A state variable, "storingCharacters", is set when nodes of interest begin and end.
    // This determines whether character data is handled or ignored.
    if !importer.storingCharacters {return}
    importer.appendCharacters(UnsafePointer(characterArray!), length: Int(numberOfCharacters))
    
}

/*
A production application should include robust error handling as part of its parsing implementation.
The specifics of how errors are handled depends on the application.
*/
typealias errorSAXFuncDummy = @convention(c) (_ parsingContext: UnsafeMutableRawPointer, _ errorMessage: UnsafePointer<CChar>)->Void
private let errorEncounteredSAX: errorSAXFuncDummy = {parsingContext, errorMessage in
    
    // Handle errors as appropriate for your application.
    fatalError("Unhandled error encountered during SAX parse.")
}

// The handler struct has positions for a large number of callback functions. If NULL is supplied at a given position,
// that callback functionality won't be used. Refer to libxml documentation at http://www.xmlsoft.org for more information
// about the SAX callbacks.
private var simpleSAXHandlerStruct = xmlSAXHandler(
    internalSubset: nil,
    isStandalone: nil,
    hasInternalSubset: nil,
    hasExternalSubset: nil,
    resolveEntity: nil,
    getEntity: nil,
    entityDecl: nil,
    notationDecl: nil,
    attributeDecl: nil,
    elementDecl: nil,
    unparsedEntityDecl: nil,
    setDocumentLocator: nil,
    startDocument: nil,
    endDocument: nil,
    startElement: nil,
    endElement: nil,
    reference: nil,
    characters: charactersFoundSAX,
    ignorableWhitespace: nil,
    processingInstruction: nil,
    comment: nil,
    warning: nil,
    error: unsafeBitCast(errorEncounteredSAX, to: errorSAXFunc.self),
    fatalError: nil,
    getParameterEntity: nil,
    cdataBlock: nil,
    externalSubset: nil,
    initialized: XML_SAX2_MAGIC,
    _private: nil,
    startElementNs: startElementSAX,
    endElementNs: endElementSAX,
    serror: nil
)

//
//  ViewController.swift
//  SharedNotes
//
//  Created by Christopher Prince on 4/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMSyncServer
import SMCoreLib

class ViewController: UIViewController {
    private let spinner = SyncSpinner(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
    @IBOutlet weak var tableView: UITableView!
    private var coreDataSource:CoreDataSource!
    private let cellReuseIdentifier = "NoteCell"
    private var refreshControl:ODRefreshControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SMSyncServer.session.delegate = self
        
        let barButtonSpinner = UIBarButtonItem(customView: spinner)
        self.navigationItem.leftBarButtonItem = barButtonSpinner
        
        self.coreDataSource = CoreDataSource(delegate: self)
        
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.registerClass(NoteTableViewCell.self, forCellReuseIdentifier: self.cellReuseIdentifier)
        
        self.refreshControl = ODRefreshControl(inScrollView: self.tableView)
        
        // A bit of a hack because the refresh control was appearing too high
        self.refreshControl.yOffset = -(self.navigationController!.navigationBar.frameHeight + UIApplication.sharedApplication().statusBarFrame.height)
        
        // I like the "tear drop" pull down, but don't want the activity indicator.
        self.refreshControl.activityIndicatorViewColor = UIColor.clearColor()
        
        self.refreshControl.addTarget(self, action: #selector(refreshTableViewAction), forControlEvents: .ValueChanged)
    }
    
    @objc private func refreshTableViewAction() {
        self.refreshControl.endRefreshing()
        SMSyncServer.session.sync()
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.coreDataSource.fetchData()
        
        // For the case when we're returning from editing the note
        self.tableView.reloadData()
    }

    @IBAction func signInAction(sender: AnyObject) {
        let signInController = SMCloudStorageCredentials.session.makeSignInController()
        self.navigationController!.pushViewController(signInController, animated: true)
    }
    
    @IBAction func createAction(sender: AnyObject) {
        let _ = Note.newObjectAndMakeUUID(true)
    }
}

extension ViewController : SMSyncServerDelegate {
    func syncServerDownloadsComplete(downloadedFiles: [(NSURL, SMSyncAttributes)], acknowledgement: () -> ()) {
        for (url, attr) in downloadedFiles {
            Note.createOrUpdate(usingUUID: attr.uuid, fromFileAtURL: url)
        }
        
        acknowledgement()
    }
    
    func syncServerClientShouldDeleteFiles(uuids: [NSUUID], acknowledgement: () -> ()) {
        for uuid in uuids {
            if let note = Note.fetch(withUUID: uuid) {
                note.removeObject()
            }
            else {
                Log.error("Could not find note: \(uuid)")
            }
        }
        
        acknowledgement()
    }
    
    func syncServerModeChange(newMode: SMSyncServerMode) {        
        switch newMode {
        case .Synchronizing:
            self.spinner.start()
            self.spinner.setNeedsLayout()
            
        case .Idle, .NetworkNotConnected, .ClientAPIError, .NonRecoverableError, .InternalError:
            self.spinner.stop()
            self.spinner.setNeedsLayout()
        }
    }
    
    func syncServerEventOccurred(event: SMSyncServerEvent) {
    }
}

extension ViewController : CoreDataSourceDelegate {
    // This must have sort descriptor(s) because that is required by the NSFetchedResultsController, which is used internally by this class.
    func coreDataSourceFetchRequest(cds: CoreDataSource!) -> NSFetchRequest! {
        return Note.fetchRequestForAllObjects()
    }
    
    func coreDataSourceContext(cds: CoreDataSource!) -> NSManagedObjectContext! {
        return CoreData.sessionNamed(CoreDataSession.name).context
    }
    
    // Should return YES iff the context save was successful.
    func coreDataSourceSaveContext(cds: CoreDataSource!) -> Bool {
        return CoreData.sessionNamed(CoreDataSession.name).saveContext()
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasDeleted indexPathOfDeletedObject: NSIndexPath!) {
        self.tableView.reloadRowsAtIndexPaths([indexPathOfDeletedObject], withRowAnimation: .Automatic)
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasInserted indexPathOfInsertedObject: NSIndexPath!) {
        self.tableView.reloadData()
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasUpdated indexPathOfUpdatedObject: NSIndexPath!) {
        self.tableView.reloadData()
    }
}

extension ViewController : UITableViewDataSource, UITableViewDelegate {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(self.coreDataSource.numberOfRowsInSection(0))
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    
        let cell = self.tableView.dequeueReusableCellWithIdentifier(self.cellReuseIdentifier, forIndexPath: indexPath)
 
        let note = self.coreDataSource.objectAtIndexPath(indexPath) as! Note
        Log.msg("\(note)")
        Log.msg("\(note.uuid)")

        cell.textLabel!.text = note.text
        cell.detailTextLabel!.text = note.dateModified?.description
        
        return cell
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        self.tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        if let editNoteVC = self.storyboard?.instantiateViewControllerWithIdentifier(
            "EditNoteViewController") as? EditNoteViewController {
            
            let note = self.coreDataSource.objectAtIndexPath(indexPath) as! Note
            editNoteVC.note = note
            self.navigationController!.pushViewController(editNoteVC, animated: true)
        }
    }
}


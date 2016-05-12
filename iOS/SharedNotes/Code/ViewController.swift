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
    @IBOutlet weak var signInOrOut: UIBarButtonItem!
    private var coreDataSource:CoreDataSource!
    private let cellReuseIdentifier = "NoteCell"
    
    // To enable pulling down on the table view to do a sync with server.
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
        
        self.changeSignInSignOutButton()
    }

    @IBAction func signInAction(sender: AnyObject) {
        if SMSyncServerUser.session.signedIn {
            // User is signed in; sign them out.
            SMCloudStorageCredentials.session.syncServerSignOutUser()
            self.changeSignInSignOutButton()
        }
        else {
            // User is not signed in; allow them to.
            let signInController = SMCloudStorageCredentials.session.makeSignInController()
            self.navigationController!.pushViewController(signInController, animated: true)
        }
    }
    
    private func changeSignInSignOutButton() {
        if SMSyncServerUser.session.signedIn {
            self.signInOrOut.title = "Signout"
            self.signInOrOut.tintColor = nil // use the default
        }
        else {
            self.signInOrOut.title = "Signin"
            self.signInOrOut.tintColor = UIColor(red: 0.0, green: 154.0/255.0, blue: 43.0/255.0, alpha: 1.0)
        }
    }
    
    @IBAction func createAction(sender: AnyObject) {
        let _ = Note.newObjectAndMakeUUID(true)
    }
}

extension ViewController : SMSyncServerDelegate {
    func syncServerDownloadsComplete(downloadedFiles: [(NSURL, SMSyncAttributes, SMSyncServerFileDownloadConflict?)], acknowledgement: () -> ()) {
        for (url, attr, conflict) in downloadedFiles {
            // TODO: Need to deal with conflict
            Note.createOrUpdate(usingUUID: attr.uuid, fromFileAtURL: url)
        }
        
        acknowledgement()
    }
    /*
        let dmp = DiffMatchPatch()
        let firstString = "Hello friend, there is my world"
        let secondString = "Hello friend, is my world\nWhat's going on"
        let resultPatchArray = dmp.patch_makeFromOldString(firstString, andNewString: secondString) as [AnyObject]
        print("\(resultPatchArray)")
        let patchedResult = dmp.patch_apply(resultPatchArray, toString: firstString)
        print("\(patchedResult[0])")
    */
    
    private func handleFileDownloadConflicts(downloadedFiles:[(NSUUID, SMSyncServerDownloadDeletionConflict?)], acknowledgement:()->()) {
        if deletions.count > 0 {
            let remainingDeletions = Array(deletions[1..<deletions.count])
            
            let (uuid, _) = deletions[0]
            let note = Note.fetch(withUUID: uuid)
            Assert.If(note == nil, thenPrintThisString: "Could not find the note!")
            
            // If we had useful remote names for files, we could show it to them...
            // let fileAttr = SMSyncServer.session.localFileStatus(uuid)
            
            let alert = UIAlertController(title: "Someone else has deleted a note.", message: nil, preferredStyle: .Alert)
            
            alert.addAction(UIAlertAction(title: "Accept the deletion.", style: .Default) {[unowned self] action in
                note?.removeObject()
                self.handleDeletionConflicts(remainingDeletions, acknowledgement: acknowledgement)
            })
            
            alert.addAction(UIAlertAction(title: "Don't delete it.", style: .Destructive) { action in
                note?.upload()
                self.handleDeletionConflicts(remainingDeletions, acknowledgement: acknowledgement)
            })
        }
        else {
            acknowledgement()
        }
    }
    
    func syncServerClientShouldDeleteFiles(deletions:[(NSUUID, SMSyncServerDownloadDeletionConflict?)], acknowledgement:()->()) {
        self.handleDeletionConflicts(deletions, acknowledgement: acknowledgement)
    }
    
    private func handleDeletionConflicts(deletions:[(NSUUID, SMSyncServerDownloadDeletionConflict?)], acknowledgement:()->()) {
        if deletions.count > 0 {
            let remainingDeletions = Array(deletions[1..<deletions.count])
            let (uuid, conflict) = deletions[0]
            
            let note = Note.fetch(withUUID: uuid)
            Assert.If(note == nil, thenPrintThisString: "Could not find the note!")
            
            if conflict == nil {
                // No conflict. Silently delete the note.
                // TODO: Need to deal with modification locks.
                note?.removeObject()
                self.handleDeletionConflicts(remainingDeletions, acknowledgement: acknowledgement)
                return
            }
            
            // If we had useful remote names for files, we could show it to them...
            // let fileAttr = SMSyncServer.session.localFileStatus(uuid)
            
            let alert = UIAlertController(title: "Someone else has deleted a note.", message: "But you just updated it!", preferredStyle: .Alert)
            
            alert.addAction(UIAlertAction(title: "Accept the deletion.", style: .Default) {[unowned self] action in
                note?.removeObject()
                self.handleDeletionConflicts(remainingDeletions, acknowledgement: acknowledgement)
            })
            
            alert.addAction(UIAlertAction(title: "Keep your update.", style: .Destructive) { action in
                note?.upload()
                self.handleDeletionConflicts(remainingDeletions, acknowledgement: acknowledgement)
            })
        }
        else {
            acknowledgement()
        }
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


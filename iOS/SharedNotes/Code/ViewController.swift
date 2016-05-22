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
    private var barButtonSpinner:UIBarButtonItem!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var signInOrOut: UIBarButtonItem!
    private var coreDataSource:CoreDataSource!
    private let cellReuseIdentifier = "NoteCell"
    
    // To enable pulling down on the table view to do a sync with server.
    private var refreshControl:ODRefreshControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SMSyncServer.session.delegate = self
        
        self.barButtonSpinner = UIBarButtonItem(customView: spinner)
        self.navigationItem.leftBarButtonItem = self.barButtonSpinner
        
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
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(spinnerTapGestureAction))
        self.spinner.addGestureRecognizer(tapGesture)
    }
    
    // Enable a reset from error when needed.
    @objc private func spinnerTapGestureAction() {
        Log.msg("spinner tapped")
       
        switch  SMSyncServer.session.mode {
        case .Idle, .NetworkNotConnected, .Synchronizing, .ResettingFromError:
            break
        
        case .ClientAPIError, .NonRecoverableError, .InternalError:
            let alert = UIAlertController(title: "Reset error?", message: nil, preferredStyle: .ActionSheet)
            alert.addAction(UIAlertAction(title: "Reset", style: .Destructive) { action in
                SMSyncServer.session.resetFromError()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .Default) { action in
            })
            alert.popoverPresentationController!.barButtonItem = self.barButtonSpinner
            self.presentViewController(alert, animated: true, completion: nil)
        }
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
        let _ = Note.newObjectAndMakeUUID(makeUUIDAndUpload: true)
    }
}

extension ViewController : SMSyncServerDelegate {
    func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement: () -> ()) {
        for (url, attr) in downloads {
            Note.createOrUpdate(usingUUID: attr.uuid, fromFileAtURL: url)
        }
        
        acknowledgement()
    }
    
    func syncServerShouldResolveDownloadConflicts(conflicts: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
        self.resolveDownloadConflicts(conflicts)
    }
    
    private func resolveDownloadConflicts(conflicts:[(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
    
        if conflicts.count > 0 {
            let remainingConflicts = Array(conflicts[1..<conflicts.count])
            
            let (url, attr, conflict) = conflicts[0]
            let note = Note.fetch(withUUID: attr.uuid)
            Assert.If(note == nil, thenPrintThisString: "Could not find the note!")
            
            // If we had useful remote names for files, we could show it to them...
            // let fileAttr = SMSyncServer.session.localFileStatus(uuid)
            
            var message:String
            switch conflict.conflictType! {
            case .UploadDeletion:
                message = "deletion"
                
            case .FileUpload:
                message = "upload"
            }
            
            let alert = UIAlertController(title: "Your \(message) is conflicting with a download!", message: nil, preferredStyle: .Alert)
            
            alert.addAction(UIAlertAction(title: "Accept the download", style: .Default) {[unowned self] action in
                conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
                Note.createOrUpdate(usingUUID: attr.uuid, fromFileAtURL: url)
                self.resolveDownloadConflicts(remainingConflicts)
            })
            
            alert.addAction(UIAlertAction(title: "Keep your \(message)", style: .Default) { action in
                conflict.resolveConflict(resolution: .KeepConflictingClientOperations)
                self.resolveDownloadConflicts(remainingConflicts)
            })
            
            // If the conflict is between a file-download and a file-upload, ask them if they want to merge. The two conflicting pieces of info that can be merged are: (a) the contents of the local Note, and (b) the update from the download.
            if conflict.conflictType == .FileUpload {
                alert.addAction(UIAlertAction(title: "Merge your update with the download?", style: .Default) { action in
                
                    // Delete the conflicting operations because we don't want our prior upload. We want to create a merged upload.
                    conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
                    
                    note!.merge(withDownloadedNoteContents: url)
                    
                    self.resolveDownloadConflicts(remainingConflicts)
                })
            }
            
            self.presentViewController(alert, animated: true, completion: nil)
        }
    }
    
    func syncServerShouldDoDeletions(downloadDeletions deletions:[NSUUID], acknowledgement:()->()) {
        for uuid in deletions {
            let note = Note.fetch(withUUID: uuid)
            Assert.If(note == nil, thenPrintThisString: "Could not find the note!")
            note!.removeObject()
        }
        
        acknowledgement()
    }

    func syncServerShouldResolveDeletionConflicts(conflicts:[(downloadDeletion: NSUUID, uploadConflict: SMSyncServerConflict)]) {
        self.resolveDeletionConflicts(conflicts)
    }
    
    private func resolveDeletionConflicts(conflicts:[(downloadDeletion: NSUUID, uploadConflict: SMSyncServerConflict)]) {
        if conflicts.count > 0 {
            let remainingConflicts = Array(conflicts[1..<conflicts.count])
            let (uuid, conflict) = conflicts[0]
            
            Assert.If(conflict.conflictType != .FileUpload, thenPrintThisString: "Didn't get upload conflict")
            
            let note = Note.fetch(withUUID: uuid)
            Assert.If(note == nil, thenPrintThisString: "Could not find the note!")
            
            // If we had useful remote names for files, we could show it to them...
            // let fileAttr = SMSyncServer.session.localFileStatus(uuid)
            
            let alert = UIAlertController(title: "Someone else has deleted a note.", message: "But you just updated it!", preferredStyle: .Alert)
            
            alert.addAction(UIAlertAction(title: "Accept the deletion.", style: .Default) {[unowned self] action in
                note?.removeObject()
                conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
                self.resolveDeletionConflicts(remainingConflicts)
            })
            
            alert.addAction(UIAlertAction(title: "Keep your update.", style: .Destructive) { action in
                conflict.resolveConflict(resolution: .KeepConflictingClientOperations)
                self.resolveDeletionConflicts(remainingConflicts)
            })
            
            self.presentViewController(alert, animated: true, completion: nil)
        }
    }
    
    func syncServerModeChange(newMode: SMSyncServerMode) {
        switch newMode {
        case .Synchronizing, .ResettingFromError:
            self.spinner.start()
        
        case .ClientAPIError:
            self.spinner.stop(withBackgroundColor: .Yellow)
            
        case .NonRecoverableError, .InternalError:
            self.spinner.stop(withBackgroundColor: .Red)
            
        case .Idle, .NetworkNotConnected:
            self.spinner.stop()
        }
        
        self.spinner.setNeedsLayout()
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
        self.tableView.deleteRowsAtIndexPaths([indexPathOfDeletedObject], withRowAnimation: .Automatic)
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasInserted indexPathOfInsertedObject: NSIndexPath!) {
        self.tableView.reloadData()
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasUpdated indexPathOfUpdatedObject: NSIndexPath!) {
        self.tableView.reloadData()
    }
    
    // 5/20/6; Odd. This gets called when an object is updated, sometimes. It may be because the sorting key I'm using in the fetched results controller changed.
    func coreDataSource(cds: CoreDataSource!, objectWasMovedFrom oldIndexPath: NSIndexPath!, to newIndexPath: NSIndexPath!) {
        self.tableView.reloadData()
    }
}

extension ViewController : UITableViewDataSource, UITableViewDelegate {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(self.coreDataSource.numberOfRowsInSection(0))
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    
        let cell = self.tableView.dequeueReusableCellWithIdentifier(self.cellReuseIdentifier, forIndexPath: indexPath) as! NoteTableViewCell
 
        let note = self.coreDataSource.objectAtIndexPath(indexPath) as! Note
        Log.msg("\(note)")
        Log.msg("\(note.uuid)")

        cell.configure(withNote: note)
        
        return cell
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        self.tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        Log.msg("Editing object at row: \(indexPath.row)")

        if let editNoteVC = self.storyboard?.instantiateViewControllerWithIdentifier(
            "EditNoteViewController") as? EditNoteViewController {
            
            let note = self.coreDataSource.objectAtIndexPath(indexPath) as! Note
            editNoteVC.note = note
            self.navigationController!.pushViewController(editNoteVC, animated: true)
        }
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }

    func tableView(tableView: UITableView, estimatedHeightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
    
    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        
        let note = self.coreDataSource.objectAtIndexPath(indexPath) as! Note
        
        switch editingStyle {
        case .Delete:
            Log.msg("Deleting object from row: \(indexPath.row)")
            //self.coreDataSource.deleteObjectAtIndexPath(indexPath)
            note.removeObject()
            
        case .Insert, .None:
            Assert.badMojo(alwaysPrintThisString: "Should not get this")
        }
    }
}


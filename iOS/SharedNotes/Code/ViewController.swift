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
    @IBOutlet weak var share: UIBarButtonItem!
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
        
        case .NonRecoverableError, .InternalError:
            let alert = UIAlertController(title: "Reset error?", message: nil, preferredStyle: .ActionSheet)
            alert.addAction(UIAlertAction(title: "Partial reset", style: .Destructive) { action in
                SMSyncServer.session.resetFromError(resetType: .Server)
            })
            alert.addAction(UIAlertAction(title: "Full reset", style: .Destructive) { action in
                SMSyncServer.session.resetFromError(resetType: [.Local, .Server])
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .Default) { action in
            })
            if alert.popoverPresentationController != nil {
                alert.popoverPresentationController!.barButtonItem = self.barButtonSpinner
            }
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
            SMSyncServerUser.session.signOut()
            self.changeSignInSignOutButton()
        }
        else {
            // TODO: Need to give them a warning if there is data in the app, i.e., notes. If they sign out and sign into a different account, this is going to mess things up-- will need to reset the data.
            
            // User is not signed in; allow them to.
            let signInController = SignInViewController()
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
        if SMSyncServerUser.session.signedIn {
            do {
                let _ = try Note.newObjectAndMakeUUID(makeUUIDAndUpload: true)
                try SMSyncServer.session.commit()
            } catch (let error) {
                Misc.showAlert(fromParentViewController: self, title: "Error uploading new  note!", message: "\(error)")
            }
        }
    }
    
    @IBAction func shareAction(sender: AnyObject) {
        var alert:UIAlertController
        
        if SMSyncServerUser.session.signedIn {
            alert = UIAlertController(title: "Share your data with Facebook user?", message: nil, preferredStyle: .ActionSheet)
            alert.addAction(UIAlertAction(title: "Read-only", style: .Default){alert in
                self.completeSharing(.Downloader)
            })
            alert.addAction(UIAlertAction(title: "Read & Change", style: .Default){alert in
                self.completeSharing(.Uploader)
            })
            alert.addAction(UIAlertAction(title: "Read, Change, & Invite", style: .Default){alert in
                self.completeSharing(.Admin)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel){alert in
            })
        }
        else {
            alert = UIAlertController(title: "Please sign in first!", message: "There is no signed in user.", preferredStyle: .Alert)
            alert.addAction(UIAlertAction(title: "OK", style: .Cancel){alert in
            })
        }
        
        alert.popoverPresentationController?.barButtonItem = self.share
        self.presentViewController(alert, animated: true, completion: nil)
    }
    
    private func completeSharing(sharingType:SMSharingType) {
        SMSyncServerUser.session.createSharingInvitation(sharingType) { invitationCode, error in
            if error == nil {
                let sharingURLString = SMSharingInvitations.createSharingURL(invitationCode: invitationCode!, username: nil)
                let email = SMEmail(parentViewController: self)
                
                let message = "I'd like to share my data with you through the SharedNotes app and your Facebook account. To share my data, you need to:\n1) download the SharedNotes iOS app onto your iPhone or iPad,\n2) tap the link below in the Apple Mail app, and\n3) follow the instructions within the app to sign in to your Facebook account to access my data.\n\n" + sharingURLString
                
                email.setMessageBody(message, isHTML: false)
                email.show()
            }
            else {
                Misc.showAlert(fromParentViewController: self, title: "Error creating sharing invitation!", message: "\(error)")
            }
        }
    }
}

extension ViewController : SMSyncServerDelegate {
    func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement: () -> ()) {
    
        var imagesOwners = [(image: NoteImage, noteOwnerUUID:String)]()
    
        for (url, attr) in downloads {
            let objectDataType = attr.appMetaData![CoreDataExtras.objectDataTypeKey] as! String
            
            switch objectDataType {                
            case CoreDataExtras.objectDataTypeNote:
                Note.createOrUpdate(usingUUID: attr.uuid, fromFileAtURL: url)
            
            case CoreDataExtras.objectDataTypeNoteImage:
                let ownedByNoteUUID = attr.appMetaData![CoreDataExtras.ownedByNoteUUIDKey] as! String
                // Since we don't know if the owning note has been downloaded yet, lets save this and we'll assign the owning notes after this loop.
                
                let finalImageURL = FileExtras().newURLForImage()
                let fileMgr = NSFileManager.defaultManager()
                do {
                    try fileMgr.moveItemAtURL(url, toURL: finalImageURL)
                } catch (let error) {
                    Assert.badMojo(alwaysPrintThisString: "Error moving file to URL: \(error)")
                }
                
                let noteImage = try! NoteImage.newObjectAndMakeUUID(withURL: finalImageURL, makeUUIDAndUpload: false) as! NoteImage
                noteImage.uuid = attr.uuid!.UUIDString

                imagesOwners.append((image: noteImage, noteOwnerUUID:ownedByNoteUUID))
            
            default:
                Assert.badMojo(alwaysPrintThisString: "Unexpected mimeType: \(attr.mimeType!)")
            }
        }
        
        for imageOwner in imagesOwners {
            let (image: noteImage, noteOwnerUUID:ownedByNoteUUID) = imageOwner
            let note = Note.fetch(withUUID: NSUUID(UUIDString: ownedByNoteUUID)!)
            Assert.If(note == nil, thenPrintThisString: "Couldn't find owning note!")
            noteImage.note = note
        }
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()

        acknowledgement()
    }
    
    func syncServerShouldResolveDownloadConflicts(conflicts: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
        self.resolveDownloadConflicts(conflicts)
    }
    
    private func resolveDownloadConflicts(conflicts:[(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
    
        if conflicts.count > 0 {
            let remainingConflicts = conflicts.tail()
            
            let (url, attr, conflict) = conflicts[0]
            let note = Note.fetch(withUUID: attr.uuid)
            Assert.If(note == nil, thenPrintThisString: "Could not find the note!")
            
            // If we had useful remote names for files, we could show it to them...
            // let fileAttr = SMSyncServer.session.localFileStatus(uuid)
            // TODO: Could use appMetaData now.
            
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
                    
                    let localJSONData = note!.jsonData!
                    let localContents = SMImageTextView.contents(fromJSONData: localJSONData)
                    let remoteJSONData = NSData(contentsOfURL: url)
                    Assert.If(remoteJSONData == nil, thenPrintThisString: "Yikes: Bad remote JSON data!")
                    let remoteContents = SMImageTextView.contents(fromJSONData: remoteJSONData)
                    
                    let mergedContents = Misc.mergeImageViewContents(localContents!, c2: remoteContents!)
                    
                    // mergedContents may reference some newly downloaded images. OR images that have just been downloaded. How do we add those newly referenced images into the note? Or is that dealt with properly by syncServerShouldSaveDownloads? With new images, syncServerShouldSaveDownloads will be called prior to resolveDownloadConflicts, so we should be fine.
                    
                    // setJSONData will do an upload with the change, but it doesn't do a commit.
                    do {
                        try note!.setJSONData(SMImageTextView.contentsToData(mergedContents)!)
                        try SMSyncServer.session.commit()
                    } catch (let error) {
                        Misc.showAlert(fromParentViewController: self, title: "Error updating note!", message: "\(error)")
                    }
                    
                    // Deal with any remaining conflicts.
                    self.resolveDownloadConflicts(remainingConflicts)
                })
            }
            
            self.presentViewController(alert, animated: true, completion: nil)
        }
    }
    
    func syncServerShouldDoDeletions(downloadDeletions deletions:[SMSyncAttributes], acknowledgement:()->()) {
        for attr in deletions {
            let objectDataType = attr.appMetaData![CoreDataExtras.objectDataTypeKey] as! String
            
            switch objectDataType {
            case CoreDataExtras.objectDataTypeNote:
                // Note deletion should remove associated images. We don't know the order that they'll arrive in though.
                if let note = Note.fetch(withUUID: attr.uuid) {
                    // No need to update server here because the server already knows about this deletion.
                    try! note.removeObject(andUpdateServer: false)
                }
                else {
                    Log.warning("Could not find Note to delete: \(attr.uuid); was it deleted already?")
                }
            
            case CoreDataExtras.objectDataTypeNoteImage:
                if let noteImage = NoteImage.fetch(withUUID: attr.uuid) {
                    // As above. Server already knows about the deletion.
                    try! noteImage.removeObject(andUpdateServer: false)
                }
                else {
                    Log.warning("Could not find NoteImage to delete: \(attr.uuid); was it deleted already?")
                }

            default:
                Assert.badMojo(alwaysPrintThisString: "Yikes: Unknown object type: \(objectDataType)")
            }
        }
        
        acknowledgement()
    }

    func syncServerShouldResolveDeletionConflicts(conflicts:[(downloadDeletion: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
        self.resolveDeletionConflicts(conflicts)
    }
    
    private func resolveDeletionConflicts(conflicts:[(downloadDeletion: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
        if conflicts.count > 0 {
            let remainingConflicts = Array(conflicts[1..<conflicts.count])
            let (attr, conflict) = conflicts[0]
            
            Assert.If(conflict.conflictType != .FileUpload, thenPrintThisString: "Didn't get upload conflict")
            
            let note = Note.fetch(withUUID: attr.uuid)
            Assert.If(note == nil, thenPrintThisString: "Could not find the note!")
            
            // If we had useful remote names for files, we could show it to them...
            // let fileAttr = SMSyncServer.session.localFileStatus(uuid)
            // TODO: Could use appMetaData now.
            
            let alert = UIAlertController(title: "Someone else has deleted a note.", message: "But you just updated it!", preferredStyle: .Alert)
            
            alert.addAction(UIAlertAction(title: "Accept the deletion.", style: .Default) {[unowned self] action in
                try! note?.removeObject(andUpdateServer: false)
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
        return CoreData.sessionNamed(CoreDataExtras.sessionName).context
    }
    
    // Should return YES iff the context save was successful.
    func coreDataSourceSaveContext(cds: CoreDataSource!) -> Bool {
        return CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
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
            // Call the note removeObject method and not the coreDataSource method so that (a) associated images get removed too, and updates get pushed to server.
            //self.coreDataSource.deleteObjectAtIndexPath(indexPath)
            // This is a user request for a deletion. Update the server.
            do {
                try note.removeObject(andUpdateServer: true)
            } catch (let error) {
                Misc.showAlert(fromParentViewController: self, title: "Error removing note!", message: "\(error)")
            }
            
        case .Insert, .None:
            Assert.badMojo(alwaysPrintThisString: "Should not get this")
        }
    }
}


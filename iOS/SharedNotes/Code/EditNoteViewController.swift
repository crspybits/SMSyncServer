//
//  EditNoteViewController.swift
//  SharedNotes
//
//  Created by Christopher Prince on 5/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit
import SMCoreLib
import SMSyncServer

public class EditNoteImageTextView : SMImageTextView {
    var didChange = false
    var note:Note?
    var acquireImage:SMAcquireImage?
    
    func commitChanges() {
        self.note!.jsonData = self.contentsToData()
        SMSyncServer.session.commit()
        self.didChange = false
    }
    
    // MARK: UITextView delegate methods; SMImageTextView declares delegate conformance and assigns delegate property.
    
    // Using this for updates based on text-only changes (not for images). 
    func textViewDidEndEditing(textView: UITextView) {
        // Only update if the text has changed, because the update will generate an upload.
        // ALSO: We get a call to textViewDidEndEditing when we insert an image into the text view, i.e., when we navigate away to the image picker. Don't want the body of this if executed then.
        if self.didChange && !self.acquireImage!.acquiringImage {
            self.commitChanges()
        }
    }
    
    func textViewDidChange(textView: UITextView) {
        self.didChange = true
    }
}

class EditNoteViewController : UIViewController {
    // Set this before pushing to view controller-- gives the note being edited.
    var note:Note?
    private var acquireImage:SMAcquireImage!
    @IBOutlet weak var imageTextView: EditNoteImageTextView!
    private var initialLoadOfJSONData = false
    private var addImageBarButton:UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.addImageBarButton = UIBarButtonItem(title: "Add Image", style: .Plain, target: self, action: #selector(addImageAction))
        
        // I want to set the font size of the text view in relation to the size of the screen real-estate we have.
        let baselineMinSize:CGFloat = 500.0
        let baselineFontSize:CGFloat = 30.0
        let minSize = min(self.view.frameWidth, self.view.frameHeight)
        let fontSize = (minSize/baselineMinSize)*baselineFontSize
        self.imageTextView.font = UIFont.systemFontOfSize(fontSize)
        
        let toolbar = UIToolbar(frame: CGRectMake(0, 0, self.view.frameWidth, 50))
        toolbar.barStyle = UIBarStyle.Default
        toolbar.items = [
            UIBarButtonItem(title: "Close", style: UIBarButtonItemStyle.Plain, target: self, action: #selector(dismissKeyboardAction)),
            UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil),
            self.addImageBarButton
            ]
        toolbar.sizeToFit()
        self.imageTextView.inputAccessoryView = toolbar
        
        Log.msg("self.imageTextView: \(self.imageTextView)")
        
        self.imageTextView.imageDelegate = self
        
        self.acquireImage = SMAcquireImage(withParentViewController: self)
        self.acquireImage.delegate = self
        
        self.imageTextView.acquireImage = self.acquireImage
    }
    
    @objc private func dismissKeyboardAction() {
        self.imageTextView.resignFirstResponder()
    }
    
    @objc private func addImageAction() {
        self.acquireImage.showAlert(fromBarButton: self.addImageBarButton)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.imageTextView.note = self.note
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        // Pushing to the image picker causes viewDidAppear to be called. Don't want to load contents again when popping back from that.
        if !self.initialLoadOfJSONData {
            self.initialLoadOfJSONData = true
            
            // Putting this in viewDidAppear because having problems getting images to resize if I put it in viewWillAppear.
            self.imageTextView.loadContents(fromJSONData: self.note!.jsonData)
        }
    }
}

extension EditNoteViewController : SMImageTextViewDelegate {
    // Delete an image.
    func smImageTextView(imageTextView:SMImageTextView, imageDeleted uuid:NSUUID?) {
        Log.msg("UUID of image: \(uuid)")
        
        if let noteImage = NoteImage.fetch(withUUID: uuid!) {
            noteImage.removeObject()
            // TODO: Does this, as a side effect, cause textViewDidEndEditing to be called. I.e., does the updated note text get uploaded?
        }
        
        Log.error("Could not fetch image for uuid: \(uuid)")
    }
    
    // Fetch an image from a file given a UUID
    func smImageTextView(imageTextView: SMImageTextView, imageForUUID uuid: NSUUID) -> UIImage? {
        if let noteImage = NoteImage.fetch(withUUID: uuid),
            let image = UIImage(contentsOfFile: noteImage.fileURL!.path!) {
            return image
        }
        
        Log.error("Could not fetch image for uuid: \(uuid)")
        return nil
    }
}

extension EditNoteViewController : SMAcquireImageDelegate {
    func smAcquireImageURLForNewImage(acquireImage:SMAcquireImage) -> SMRelativeLocalURL {
        return FileExtras().newURLForImage()
    }
    
    func smAcquireImage(acquireImage:SMAcquireImage, newImageURL: SMRelativeLocalURL) {
        Log.msg("newImageURL \(newImageURL); \(newImageURL.path!)")
        
        if let image = UIImage(contentsOfFile: newImageURL.path!) {
            let newNoteImage = NoteImage.newObjectAndMakeUUID(withURL: newImageURL, makeUUIDAndUpload: true) as! NoteImage
            self.note!.addImage(newNoteImage)
            self.imageTextView.insertImageAtCursorLocation(image, imageId: NSUUID(UUIDString: newNoteImage.uuid!))
            self.imageTextView.commitChanges()
        }
        else {
            Log.error("Error creating image from file: \(newImageURL)")
        }
    }
}

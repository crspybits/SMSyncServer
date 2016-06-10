//
//  LargeImageViewController.swift
//  SharedNotes
//
//  Created by Christopher Prince on 6/7/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation

class LargeImageViewController : UIViewController {
    // Assign this before pushing to this view controller
    var imageId:NSUUID?
    
    @IBOutlet weak var imageView: UIImageView!
 
    override func viewWillAppear(animated:Bool) {
        super.viewWillAppear(animated)
        
        if let noteImage = NoteImage.fetch(withUUID: imageId!),
            let image = UIImage(contentsOfFile: noteImage.fileURL!.path!) {
            self.imageView.image = image
        }
    }
}

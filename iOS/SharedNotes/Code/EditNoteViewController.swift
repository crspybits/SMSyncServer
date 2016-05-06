//
//  EditNoteViewController.swift
//  SharedNotes
//
//  Created by Christopher Prince on 5/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit

class EditNoteViewController : UIViewController {
    // Set this before pushing to view controller-- gives the note being edited.
    var note:Note?
    @IBOutlet weak var textView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.textView.delegate = self
        
        let toolbar = UIToolbar(frame: CGRectMake(0, 0, self.view.frame.size.width, 50))
        toolbar.barStyle = UIBarStyle.Default
        toolbar.items = [
            UIBarButtonItem(title: "Close", style: UIBarButtonItemStyle.Plain, target: self, action: #selector(dismissKeyboardAction))]
        toolbar.sizeToFit()
        self.textView.inputAccessoryView = toolbar
    }
    
    @objc private func dismissKeyboardAction() {
        self.textView.resignFirstResponder()
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.textView.text = self.note!.text
    }
}

extension EditNoteViewController : UITextViewDelegate {
    func textViewDidEndEditing(textView: UITextView) {
        self.note!.text = textView.text
    }
}

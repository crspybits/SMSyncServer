//
//  ViewController.swift
//  SharedNotes
//
//  Created by Christopher Prince on 4/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let spinner = SyncSpinner(frame: CGRect(x: 100, y: 5, width: 15, height: 15))
        self.view.addSubview(spinner)
        spinner.start()
    }
}


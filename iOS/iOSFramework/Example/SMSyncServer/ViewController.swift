//
//  ViewController.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 07/05/2016.
//  Copyright (c) 2016 Christopher Prince. All rights reserved.
//

import UIKit
import SMCoreLib

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let bundle = NSBundle(forClass: ViewController.self)
        Log.msg("bundle: \(bundle)")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}


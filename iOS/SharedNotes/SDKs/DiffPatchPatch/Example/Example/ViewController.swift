//
//  ViewController.swift
//  Example
//
//  Created by Christopher Prince on 5/12/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        let dmp = DiffMatchPatch()
        dmp.Match_Threshold = 0.5
        let firstString = "Hello friend, there is my world"
        let secondString = "Hello friend, is my world\nWhat's going on"
        let diffs = dmp.diff_mainOfOldString(firstString, andNewString: secondString)
        print("diff objects: \(diffs)")
        
        var allDiffs:String = ""
        for obj in diffs {
            let diff = obj as! Diff
            allDiffs += diff.text
        }
        
        print("allDiffs: \(allDiffs)")
        
        let resultPatchArray = dmp.patch_makeFromOldString(firstString, andNewString: secondString) as [AnyObject]
        print("\(resultPatchArray)")
        let patchedResult = dmp.patch_apply(resultPatchArray, toString: firstString)
        print("\(patchedResult[0])")
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}


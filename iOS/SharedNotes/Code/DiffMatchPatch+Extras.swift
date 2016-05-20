//
//  DiffMatchPatch+Extras.swift
//  SharedNotes
//
//  Created by Christopher Prince on 5/20/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation

extension DiffMatchPatch {
    /* Example of the result of calling diff_mainOfOldString:
    diff objects: (
        "Diff(DIFF_EQUAL,\"Hello friend, \")",
        "Diff(DIFF_DELETE,\"there \")",
        "Diff(DIFF_EQUAL,\"is my world\")",
        "Diff(DIFF_INSERT,\"\U00b6What's going on\")"
    )
    
    This method just concatenates all of the diff results, equal, delete, insert etc. together, which creates a simple merge of the two strings.
    */
    func diff_simpleMerge(firstString firstString:String, secondString: String) -> String {
        let diffs = self.diff_mainOfOldString(firstString, andNewString: secondString)
        print("diff objects: \(diffs)")
        
        var concatenatedDiffText:String = ""
        for obj in diffs {
            let diff = obj as! Diff
            concatenatedDiffText += diff.text
        }
        
        return concatenatedDiffText
    }
}
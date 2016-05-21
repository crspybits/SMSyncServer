//
//  NoteTableViewCell.swift
//  SharedNotes
//
//  Created by Christopher Prince on 5/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit
import SMCoreLib

class NoteTableViewCell : UITableViewCell {
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: .Subtitle, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(withNote note:Note) {
        self.textLabel!.numberOfLines = 0
        self.detailTextLabel!.numberOfLines = 0
        
        if note.text != nil && note.text!.characters.count > 0 {
        
            // Using Dynamic Type
            
            var fontStyleForTitle:String
            if #available(iOS 9.0, *) {
                fontStyleForTitle = UIFontTextStyleTitle1
            } else {
                fontStyleForTitle = UIFontTextStyleHeadline
            }
            
            let titleAttributes = [NSFontAttributeName: UIFont.preferredFontForTextStyle(fontStyleForTitle), NSForegroundColorAttributeName: UIColor.purpleColor()]
            let remainingLinesAttributes = [NSFontAttributeName: UIFont.preferredFontForTextStyle(UIFontTextStyleBody)]

            let (firstLine, remainingLines) = self.splitIntoFirstAndRemainingLines(note.text!)

            let titleString = NSMutableAttributedString(string: "\(firstLine)", attributes: titleAttributes)
            
            if remainingLines != nil {
                let subtitleString = NSAttributedString(string: "\n" + remainingLines!, attributes: remainingLinesAttributes)
                titleString.appendAttributedString(subtitleString)
            }
            
            self.textLabel!.attributedText = titleString
        }
        else {
            self.textLabel!.text = nil
        }
        
        self.detailTextLabel!.text = note.dateModified?.description
    }
    
    private func splitIntoFirstAndRemainingLines(text:String) -> (firstLine: String, remainingLines:String?) {
        // This is kind of gnarly
        // http://stackoverflow.com/questions/25678373/swift-split-a-string-into-an-array
        let noteTextLines = text.characters.split("\n").map(String.init)
        var tailText:String?
        var count = 0
        let maxRemainingLines = 4
        for line in noteTextLines.tail() {
            if tailText == nil {
                tailText = ""
            }
            
            if count >= maxRemainingLines {
                tailText! += "\n..."
                break
            }
            if count > 0 {
                tailText! += "\n"
            }
            tailText! += line
            count += 1
        }
        
        return (firstLine: noteTextLines[0], remainingLines: tailText)
    }
}

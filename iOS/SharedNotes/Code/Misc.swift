//
//  Misc.swift
//  US
//
//  Created by Christopher Prince on 5/30/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

class Misc {
    class func showAlert(fromParentViewController parentViewController:UIViewController, title:String, message:String?=nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        alert.popoverPresentationController?.sourceView = parentViewController.view
        alert.addAction(UIAlertAction(title: SMUIMessages.session().OkMsg(), style: .Default) {alert in
        })
        parentViewController.presentViewController(alert, animated: true, completion: nil)
    }
    
    // I'll call whichever of c1 and c2 have more elements as `primary`-- maintaining, with priority, the position of the primary's elements. This prioritizes additions to contents over deletions to contents.
    class func mergeImageViewContents(c1:[SMImageTextView.ImageTextViewElement], c2:[SMImageTextView.ImageTextViewElement]) -> [SMImageTextView.ImageTextViewElement] {
        typealias element = SMImageTextView.ImageTextViewElement
        var result = [element]()
        
        var primary:[PrimaryElement]
        var secondary:[SecondaryElement]
        
        class SecondaryElement {
            var element:SMImageTextView.ImageTextViewElement
            var removed = false
           
            // Identical elements across primary and secondary.
            var linked:PrimaryElement?
            
            init(element:SMImageTextView.ImageTextViewElement) {
                self.element = element
            }
        }
        
        class PrimaryElement {
            var element:SMImageTextView.ImageTextViewElement
            var linked:SecondaryElement?
            
            init(element:SMImageTextView.ImageTextViewElement) {
                self.element = element
            }
        }
 
        func createPrimary(elements:[SMImageTextView.ImageTextViewElement]) -> [PrimaryElement] {
            var result = [PrimaryElement]()
            
            for elem in elements {
                result.append(PrimaryElement(element: elem))
            }
            
            return result
        }
        
        func createSecondaryLinked(elements:[SMImageTextView.ImageTextViewElement]) -> [SecondaryElement] {
            var result = [SecondaryElement]()
            
            for elem in elements {
                result.append(SecondaryElement(element: elem))
            }
            
            return result
        }
        
        func secondaryElementsRemaining(elements:[SecondaryElement]) -> Int {
            var result = 0
            
            for elem in elements {
                if !elem.removed {
                    result += 1
                }
            }
            
            return result
        }
        
        let newlyInsertedLocation = -1
        
        func insertElementInPrimary(secondaryElement:SecondaryElement, withRange range:NSRange?=nil, secondaryIndex:Int?=nil, afterPrimary:PrimaryElement?=nil) {

            Assert.If(secondaryIndex != nil && afterPrimary != nil, thenPrintThisString: "You gave both a secondaryIndex and an afterPrimary")
            
            var primaryIndex = 0
            var insertionIndex:Int?
            
            // Is there an identical element immediately above in the secondary that we can use for orientation?
            var after:PrimaryElement? = afterPrimary
            if secondaryIndex != nil && secondaryIndex! > 0 {
                after = secondary[secondaryIndex! - 1].linked
            }
            
            // Similarly, for immediately below
            var before:PrimaryElement?
            if secondaryIndex != nil && secondaryIndex! < secondary.count - 1 {
                before = secondary[secondaryIndex! + 1].linked
            }
            
            while primaryIndex < primary.count {
                // Giving priority to element reference positioning
                if after != nil && after! === primary[primaryIndex] {
                    insertionIndex = primaryIndex + 1
                }
                else if before != nil && before! === primary[primaryIndex] {
                    insertionIndex = primaryIndex
                }
                else {
                    // Just using the range.
                    var primaryRange:NSRange
                    switch primary[primaryIndex].element {
                    case .Image(_, _, let range):
                        primaryRange = range
                        
                    case .Text(_, let range):
                        primaryRange = range
                    }
                    
                    if primaryRange.location != newlyInsertedLocation
                        && range!.location <= primaryRange.location {
                        insertionIndex = primaryIndex
                    } else if primaryIndex == primary.count - 1 {
                        insertionIndex = primaryIndex + 1
                    }
                }
                
                if insertionIndex != nil {
                    break
                }
                
                primaryIndex += 1
            }
            
            var newElement:SMImageTextView.ImageTextViewElement
            
            switch secondaryElement.element {
            case .Image(let image, let uuid, let range):
                newElement = .Image(image, uuid, NSMakeRange(newlyInsertedLocation, range.length))
                
            case .Text(let string, let range):
                newElement = .Text(string, NSMakeRange(newlyInsertedLocation, range.length))
            }
            
            let newPrimaryElement = PrimaryElement(element: newElement)
            secondaryElement.linked = newPrimaryElement
            newPrimaryElement.linked = secondaryElement
            primary.insert(newPrimaryElement, atIndex: insertionIndex!)
        }
        
        func findBestMatchingTextInPrimary(secondaryText:String) -> (PrimaryElement?, Float?) {
            var currPrimaryElement:PrimaryElement?
            var currBestSimilarity:Float?
            let dmp = DiffMatchPatch()
            
            for elemP in primary {
                let text = elemP.element.text
                if elemP.linked == nil && text != nil {
                    let similarity = dmp.similarity(firstString: secondaryText, secondString: text!)
                    if currBestSimilarity == nil || similarity < currBestSimilarity! {
                        currPrimaryElement = elemP
                        currBestSimilarity = similarity
                    }
                }
            }
            
            return (currPrimaryElement, currBestSimilarity)
        }
        
        // Incorporates any new elements into primary by adjusting locations.
        func adjustedPrimary() -> [SMImageTextView.ImageTextViewElement] {
            var result = [element]()
            var currLocation = 0
            
            for elemP in primary {
                switch elemP.element {
                case .Image(let image, let uuid, let range):
                    result.append(.Image(image, uuid, NSMakeRange(currLocation, range.length)))
                    currLocation += range.length
                    
                case .Text(let string, let range):
                    result.append(.Text(string, NSMakeRange(currLocation, range.length)))
                    currLocation += range.length
                }
            }
            
            //#if DEBUG
                Log.special("adjustedPrimary")

                for elem in result {
                    Log.msg("\(elem)")
                }
            //#endif
            
            return result
        }
        
        if c1.count >= c2.count {
            primary = createPrimary(c1)
            secondary = createSecondaryLinked(c2)
        } else {
            primary = createPrimary(c2)
            secondary = createSecondaryLinked(c1)
        }

        // 1) let's see if any elements of primary are identical to those in secondary.
        for elemP in primary {
            for elemS in secondary {
                if !elemS.removed && elemP.element == elemS.element {
                    elemS.removed = true
                    elemS.linked = elemP
                    // It's possible there are multiple identical matches. Just pick the first, top to bottom
                    break
                }
            }
        }
        
        if secondaryElementsRemaining(secondary) == 0 {
            return adjustedPrimary()
        }
        
        // 2) See if there are any image elements in the secondary not in the primary. If so, put them into the primary at a reasonable location.
        var secondaryIndex = 0
        while secondaryIndex < secondary.count {
            let elemS = secondary[secondaryIndex]
            
            if !elemS.removed && elemS.linked == nil {
                switch elemS.element {
                case .Image(_, _, let range):
                    insertElementInPrimary(elemS, withRange: range, secondaryIndex: secondaryIndex)
                    elemS.removed = true
                    
                case .Text(_, _):
                    break
                }
            }
            
            secondaryIndex += 1
        }
        
        if secondaryElementsRemaining(secondary) == 0 {
            return adjustedPrimary()
        }
        
        let shortTextElementLength = 40
        let similarityThreshold:Float = 0.2
        
        // We have only non-identical text elements remaining.
        
        // 3) We may be talking about either (a) newly inserted text elements or (b) text elements that were modified. (We are *not* talking about image elements). I'm going to handle this in two ways. (i) if the text element is short, just add it in, and (ii) if the text element is long, see if I can find a matching element in the primary, to do a diff.
        secondaryIndex = 0
        let dmp = DiffMatchPatch()

        while secondaryIndex < secondary.count {
            let elemS = secondary[secondaryIndex]
            if !elemS.removed {
                switch elemS.element {
                case .Image:
                    Assert.badMojo(alwaysPrintThisString: "Should not get here")
                    
                case .Text(let string, let textRange):
                    // Find best matching text within unaccounted for primary .Text elements
                    let (primaryElement, similarity) = findBestMatchingTextInPrimary(string)
                    Log.special("similarity: \(similarity)")

                    if string.characters.count <= shortTextElementLength {
                        // Shorter text elements: add them in.
                        if similarity != nil && similarity! <= similarityThreshold {
                            let newRange = NSMakeRange(newlyInsertedLocation, textRange.length + 3)
                            let secondaryElement = SecondaryElement(element: .Text(">> " + string, newRange))
                            insertElementInPrimary(secondaryElement, withRange:newRange, afterPrimary:primaryElement)
                        }
                        else {
                            insertElementInPrimary(elemS, withRange: textRange, secondaryIndex: secondaryIndex)
                        }
                    }
                    else {
                        // Longer text element: Replace with merged or add if sufficiently different.
                        
                        if similarity != nil && similarity! <= similarityThreshold {
                            // Replace with merged
                            let mergedResult = dmp.diff_simpleMerge(firstString: primaryElement!.element.text!, secondString: string)
                            primaryElement!.element = .Text(mergedResult, NSMakeRange(newlyInsertedLocation, mergedResult.characters.count))
                        }
                        else {
                            insertElementInPrimary(elemS, withRange: textRange, secondaryIndex: secondaryIndex)
                        }
                    }
                    
                    elemS.removed = true
                }
            }
            
            secondaryIndex += 1
        }
        
        Assert.If(secondaryElementsRemaining(secondary) != 0, thenPrintThisString: "Remaining elements!")
        return adjustedPrimary()
    }
}


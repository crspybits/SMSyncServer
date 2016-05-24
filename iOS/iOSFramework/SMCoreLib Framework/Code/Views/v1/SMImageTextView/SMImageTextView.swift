//
//  SMImageTextView.swift
//  SMCoreLib
//
//  Created by Christopher Prince on 5/21/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// A text view with images.

import Foundation

public protocol SMImageTextViewDelegate : class {
    func smImageTextView(imageTextView:SMImageTextView, imageDeleted:NSUUID?)
    
    // Only in an error should this return nil.
    func smImageTextView(imageTextView: SMImageTextView, imageForUUID: NSUUID) -> UIImage?
}

private class ImageTextAttachment : NSTextAttachment {
    var imageId:NSUUID?
}

public class SMImageTextView : UITextView, UITextViewDelegate {
    public weak var imageDelegate:SMImageTextViewDelegate?
    public var scalingFactor:CGFloat = 0.5
    
    override public var delegate: UITextViewDelegate? {
        set {
            if newValue == nil {
                super.delegate = nil
                return
            }
            
            Assert.badMojo(alwaysPrintThisString: "Delegate is setup by SMImageTextView, but you can subclass and declare-- all but shouldChangeTextInRange.")
        }
        
        get {
            return super.delegate
        }
    }
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        self.setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }
    
    private func setup() {
        super.delegate = self
    }
    
    public func insertImageAtCursorLocation(image:UIImage, imageId:NSUUID?) {
        let attrStringWithImage = self.makeImageAttachment(image, imageId: imageId)
        self.textStorage.insertAttributedString(attrStringWithImage, atIndex: self.selectedRange.location)
    }
    
    private func makeImageAttachment(image:UIImage, imageId:NSUUID?) -> NSAttributedString {
        // Modified from http://stackoverflow.com/questions/24010035/how-to-add-image-and-text-in-uitextview-in-ios

        let textAttachment = ImageTextAttachment()
        textAttachment.imageId = imageId
        
        let oldWidth = image.size.width
        
        //I'm subtracting 10px to make the image display nicely, accounting
        //for the padding inside the textView
        let scaleFactor = oldWidth / (self.frameWidth - 10)
        textAttachment.image = UIImage(CGImage: image.CGImage!, scale: scaleFactor/self.scalingFactor, orientation: image.imageOrientation)
        
        let attrStringWithImage = NSAttributedString(attachment: textAttachment)
        
        return attrStringWithImage
    }
    
    private static let ElementType = "ElementType"
    private static let ElementTypeText = "Text"
    private static let ElementTypeImage = "Image"
    private static let RangeLocation = "RangeLocation"
    private static let RangeLength = "RangeLength"
    private static let Contents = "Contents"

    public enum ImageTextViewElement {
        case Text(String, NSRange)
        case Image(UIImage?, NSUUID?, NSRange)
        
        public func toDictionary() -> [String:AnyObject] {
            switch self {
            case .Text(let string, let range):
                return [ElementType: ElementTypeText, RangeLocation: range.location, RangeLength: range.length, Contents: string]
            
            case .Image(_, let uuid, let range):
                var uuidString = ""
                if uuid != nil {
                    uuidString = uuid!.UUIDString
                }
                return [ElementType: ElementTypeImage, RangeLocation: range.location, RangeLength: range.length, Contents: uuidString]
            }
        }
        
        // UIImages in .Image elements will be nil.
        public static func fromDictionary(dict:[String:AnyObject]) -> ImageTextViewElement? {
            guard let elementType = dict[ElementType] as? String else {
                Log.error("Couldn't get element type")
                return nil
            }
            
            switch elementType {
            case ElementTypeText:
                guard let rangeLocation = dict[RangeLocation] as? Int,
                    let rangeLength = dict[RangeLength] as? Int,
                    let contents = dict[Contents] as? String
                else {
                    return nil
                }
                
                return .Text(contents, NSMakeRange(rangeLocation, rangeLength))
                
            case ElementTypeImage:
                guard let rangeLocation = dict[RangeLocation] as? Int,
                    let rangeLength = dict[RangeLength] as? Int,
                    let uuidString = dict[Contents] as? String
                else {
                    return nil
                }
                
                return .Image(nil, NSUUID(UUIDString: uuidString), NSMakeRange(rangeLocation, rangeLength))
            
            default:
                return nil
            }
        }
    }
    
    public var contents:[ImageTextViewElement]? {
        get {
            var result = [ImageTextViewElement]()
            
            // See https://stackoverflow.com/questions/37370556/ranges-of-strings-from-nsattributedstring
            
            self.attributedText.enumerateAttributesInRange(NSMakeRange(0, self.attributedText.length), options: NSAttributedStringEnumerationOptions(rawValue: 0)) { (dict, range, stop) in
                Log.msg("dict: \(dict); range: \(range)")
                if dict[NSAttachmentAttributeName] == nil {
                    let string = (self.attributedText.string as NSString).substringWithRange(range)
                    Log.msg("string in range: \(range): \(string)")
                    result.append(.Text(string, range))
                }
                else {
                    let imageAttachment = dict[NSAttachmentAttributeName] as! ImageTextAttachment
                    Log.msg("image at range: \(range)")
                    result.append(.Image(imageAttachment.image!, imageAttachment.imageId, range))
                }
            }
            
            Log.msg("overall string: \(self.attributedText.string)")
            
            // TODO: Need to sort each of the elements in the result array by range.location. Not sure if the enumerateAttributesInRange does this for us.
            
            if result.count > 0 {
                return result
            } else {
                return nil
            }
        } // end get
        
        // Any .Image elements must have non-nil images.
        set {
            let mutableAttrString = NSMutableAttributedString()
            
            let currFont = self.font
            
            if newValue != nil {
                for elem in newValue! {
                    switch elem {
                    case .Text(let string, let range):
                        let attrString = NSAttributedString(string: string)
                        mutableAttrString.insertAttributedString(attrString, atIndex: range.location)
                    
                    case .Image(let image, let uuid, let range):
                        let attrImageString = self.makeImageAttachment(image!, imageId: uuid)
                        mutableAttrString.insertAttributedString(attrImageString, atIndex: range.location)
                    }
                }
            }
            
            self.attributedText = mutableAttrString
            
            // Without this, we reset back to a default font size after the insertAttributedString above.
            self.font = currFont
        }
    }
    
    public func contentsToData() -> NSData? {
        guard let currentContents = self.contents
        else {
            return nil
        }
        
        // First create array of dictionaries.
        var array = [[String:AnyObject]]()
        for elem in currentContents {
            array.append(elem.toDictionary())
        }
        
        var jsonData:NSData?
        
        do {
            try jsonData = NSJSONSerialization.dataWithJSONObject(array, options: NSJSONWritingOptions(rawValue: 0))
        } catch (let error) {
            Log.error("Error serializing array to JSON data: \(error)")
            return nil
        }

        let jsonString = NSString(data: jsonData!, encoding: NSUTF8StringEncoding) as? String

        Log.msg("json results: \(jsonString)")
        
        return jsonData
    }
    
    public func saveContents(toFileURL fileURL:NSURL) -> Bool {
        guard let jsonData = self.contentsToData()
        else {
            return false
        }
        
        do {
            try jsonData.writeToURL(fileURL, options: .AtomicWrite)
        } catch (let error) {
            Log.error("Error writing JSON data to file: \(error)")
            return false
        }
        
        return true
    }

    // Give populateImagesUsing as non-nil to populate the images.
    private class func contents(fromJSONData jsonData:NSData?, populateImagesUsing smImageTextView:SMImageTextView?) -> [ImageTextViewElement]? {
        var array:[[String:AnyObject]]?
        
        if jsonData == nil {
            return nil
        }

        do {
            try array = NSJSONSerialization.JSONObjectWithData(jsonData!, options: NSJSONReadingOptions(rawValue: 0)) as? [[String : AnyObject]]
        } catch (let error) {
            Log.error("Error converting JSON data to array: \(error)")
            return nil
        }

        if array == nil {
            return nil
        }
        
        var results = [ImageTextViewElement]()
        
        for dict in array! {
            if let elem = ImageTextViewElement.fromDictionary(dict) {
                var elemToAdd = elem
                
                switch elem {
                case .Image(_, let uuid, let range):
                    if smImageTextView == nil {
                        elemToAdd = .Image(nil, uuid, range)
                    }
                    else {
                        if let image = smImageTextView!.imageDelegate?.smImageTextView(smImageTextView!, imageForUUID: uuid!) {
                            elemToAdd = .Image(image, uuid, range)
                        }
                        else {
                            return nil
                        }
                    }
                    
                default:
                    break
                }
                
                results.append(elemToAdd)
            }
            else {
                return nil
            }
        }
        
        return results
    }
    
    // Concatenates all of the string components. Ignores the images.
    public class func contentsAsConcatenatedString(fromJSONData jsonData:NSData?) -> String? {
        if let contents = SMImageTextView.contents(fromJSONData: jsonData, populateImagesUsing:nil) {
            var result = ""
    
            for elem in contents {
                switch elem {
                case .Text(let string, _):
                    result += string
                    
                default:
                    break
                }
            }
            
            return result
        }
        
        return nil
    }
    
    public func loadContents(fromJSONData jsonData:NSData?) -> Bool {
        self.contents = SMImageTextView.contents(fromJSONData: jsonData, populateImagesUsing: self)
        return self.contents == nil ? false : true
    }
    
    public func loadContents(fromJSONFileURL fileURL:NSURL) -> Bool {
        guard let jsonData = NSData(contentsOfURL: fileURL)
        else {
            return false
        }
        
        return self.loadContents(fromJSONData: jsonData)
    }
}

// MARK: UITextViewDelegate
extension SMImageTextView {
    // Modified from http://stackoverflow.com/questions/29571682/how-to-detect-deletion-of-image-in-uitextview
    
    public func textView(textView: UITextView, shouldChangeTextInRange range: NSRange, replacementText text: String) -> Bool {

        // empty text means backspace
        if text.isEmpty {
            textView.attributedText.enumerateAttribute(NSAttachmentAttributeName, inRange: NSMakeRange(0, textView.attributedText.length), options: NSAttributedStringEnumerationOptions(rawValue: 0)) { (object, imageRange, stop) in
            
                if let textAttachment = object as? ImageTextAttachment {
                    if NSLocationInRange(imageRange.location, range) {
                        Log.msg("Deletion of image: \(object); range: \(range)")
                        self.imageDelegate?.smImageTextView(self, imageDeleted: textAttachment.imageId)
                    }
                }
            }
        }

        return true
    }
}

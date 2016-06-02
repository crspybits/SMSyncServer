//
//  SharedNotesTests.swift
//  SharedNotesTests
//
//  Created by Christopher Prince on 4/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import US
import SMCoreLib

class SharedNotesTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // Merge tests
    
    func contentsEqual(c1:[SMImageTextView.ImageTextViewElement], c2:[SMImageTextView.ImageTextViewElement]) -> Bool {
    
        if c1.count != c2.count {
            return false
        }
        
        var cIndex = 0
        while cIndex < c1.count {
            if !(c1[cIndex] === c2[cIndex]) {
                return false
            }
            
            cIndex += 1
        }
        
        return true
    }
    
    func testThatMergeSameWithOneTextWorks() {
        let e1 = SMImageTextView.ImageTextViewElement.Text("Hello", NSMakeRange(0, 5))
        let c1 = [e1]
        let c2 = [e1]
        
        let result = Misc.mergeImageViewContents(c1, c2: c2)
        XCTAssert(contentsEqual(result, c2:[e1]))
    }
    
    func testThatMergeWithSimilarTextWorks() {
        let e1 = SMImageTextView.ImageTextViewElement.Text("Hello", NSMakeRange(0, 5))
        let e2 = SMImageTextView.ImageTextViewElement.Text("Hello1", NSMakeRange(0, 6))
        let e3 = SMImageTextView.ImageTextViewElement.Text(">> Hello1", NSMakeRange(5, 9))

        let c1 = [e1]
        let c2 = [e2]
        
        let result = Misc.mergeImageViewContents(c1, c2: c2)
        XCTAssert(contentsEqual(result, c2:[e1, e3]))
    }
    
    func testThatMergeWithSimilarLargeTextWorks() {
        let t1 = "0123456789abcdefghijklmnopqrstuvwxyz 0123456789abcdefghijklmnopqrstuvwxyz barg"
        let t2 = "flig 0123456789abcdefghijklmnopqrstuvwxyz 0123456789abcdefghijklmnopqrstuvwxyz"
        let t3 = "flig 0123456789abcdefghijklmnopqrstuvwxyz 0123456789abcdefghijklmnopqrstuvwxyz barg"

        let e1 = SMImageTextView.ImageTextViewElement.Text(t1, NSMakeRange(0, t1.characters.count))
        let e2 = SMImageTextView.ImageTextViewElement.Text(t2, NSMakeRange(0, t2.characters.count))
        let e3 = SMImageTextView.ImageTextViewElement.Text(t3, NSMakeRange(0, t3.characters.count))
        
        let result = Misc.mergeImageViewContents([e1], c2: [e2])
        XCTAssert(contentsEqual(result, c2:[e3]))
    }
    
    func testThatMergeWithDiffTextsWorks() {
        let e1 = SMImageTextView.ImageTextViewElement.Text("Hello", NSMakeRange(0, 5))
        let e2 = SMImageTextView.ImageTextViewElement.Text("Hello12", NSMakeRange(0, 7))
        let e3 = SMImageTextView.ImageTextViewElement.Text("Hello12", NSMakeRange(0, 7))
        let e4 = SMImageTextView.ImageTextViewElement.Text("Hello", NSMakeRange(7, 5))
      
        let c1 = [e1]
        let c2 = [e2]
        
        let result = Misc.mergeImageViewContents(c1, c2: c2)
        XCTAssert(contentsEqual(result, c2: [e3, e4]))
    }
    
    func testThatMergeSameWithOneImageWorks() {
        let uuid = NSUUID()
        
        let c1 = [SMImageTextView.ImageTextViewElement.Image(nil, uuid,  NSMakeRange(0, 1))]
        let c2 = [SMImageTextView.ImageTextViewElement.Image(nil, uuid,  NSMakeRange(0, 1))]
        
        let result = Misc.mergeImageViewContents(c1, c2: c2)
        XCTAssert(contentsEqual(result, c2:
            [SMImageTextView.ImageTextViewElement.Image(nil, uuid,  NSMakeRange(0, 1))]))
    }
    
    func testThatMergeWithTwoDiffImagesWorks() {
        let uuid1 = NSUUID()
        let uuid2 = NSUUID()
       
        let e1 = SMImageTextView.ImageTextViewElement.Image(nil, uuid1,  NSMakeRange(0, 1))
        let e2 = SMImageTextView.ImageTextViewElement.Image(nil, uuid2,  NSMakeRange(0, 1))
        let e3 = SMImageTextView.ImageTextViewElement.Image(nil, uuid2,  NSMakeRange(0, 1))
        let e4 = SMImageTextView.ImageTextViewElement.Image(nil, uuid1,  NSMakeRange(1, 1))
      
        let result = Misc.mergeImageViewContents([e1], c2: [e2])
        XCTAssert(contentsEqual(result, c2: [e3, e4]))
    }
    
    func testThatMergeWithFourImagesWorks() {
        let uuid1 = NSUUID()
        let uuid2 = NSUUID()
        let uuid3 = NSUUID()
        let uuid4 = NSUUID()
       
        let e1 = SMImageTextView.ImageTextViewElement.Image(nil, uuid1,  NSMakeRange(0, 1))
        let e2 = SMImageTextView.ImageTextViewElement.Image(nil, uuid2,  NSMakeRange(1, 1))
        let e3 = SMImageTextView.ImageTextViewElement.Image(nil, uuid3,  NSMakeRange(2, 1))
        
        let e2b = SMImageTextView.ImageTextViewElement.Image(nil, uuid2,  NSMakeRange(0, 1))
        let e4 = SMImageTextView.ImageTextViewElement.Image(nil, uuid4,  NSMakeRange(1, 1))

        let e1c = SMImageTextView.ImageTextViewElement.Image(nil, uuid1,  NSMakeRange(0, 1))
        let e2c = SMImageTextView.ImageTextViewElement.Image(nil, uuid2,  NSMakeRange(1, 1))
        let e4c = SMImageTextView.ImageTextViewElement.Image(nil, uuid4,  NSMakeRange(2, 1))
        let e3c = SMImageTextView.ImageTextViewElement.Image(nil, uuid3,  NSMakeRange(3, 1))
      
        let result = Misc.mergeImageViewContents([e1, e2, e3], c2: [e2b, e4])
        XCTAssert(contentsEqual(result, c2: [e1c, e2c, e4c, e3c]))
    }
    
    func testThatMergeOneTextAndOneImageWorks() {
        let uuid1 = NSUUID()
       
        let e1 = SMImageTextView.ImageTextViewElement.Image(nil, uuid1,  NSMakeRange(0, 1))
        let e2 = SMImageTextView.ImageTextViewElement.Text("Hello", NSMakeRange(0, 5))
        let e3 = SMImageTextView.ImageTextViewElement.Text("Hello", NSMakeRange(0, 5))
        let e4 = SMImageTextView.ImageTextViewElement.Image(nil, uuid1,  NSMakeRange(5, 1))

        let result = Misc.mergeImageViewContents([e1], c2: [e2])
        XCTAssert(contentsEqual(result, c2: [e3, e4]))
    }
}

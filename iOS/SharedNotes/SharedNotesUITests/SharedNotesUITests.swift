//
//  SharedNotesUITests.swift
//  SharedNotesUITests
//
//  Created by Christopher Prince on 5/8/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest

class SharedNotesUITests: XCTestCase {
        
    override func setUp() {
        super.setUp()
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        XCUIApplication().launch()

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        XCUIDevice.sharedDevice().orientation = .Portrait
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // User signs-in to their cloud storage account
    func testSignInToCloudStorageAccountWorks() {
        let app = XCUIApplication()
        app.navigationBars["SharedNotes.View"].buttons["Signin"].tap()
        app.buttons["GIDSignInButton"].tap()
        
        // How do we make an assertion that the sign-in process has been successful? What about having some UI state difference that indicates that the user is signed-in versus not signed in?
    }
    
}

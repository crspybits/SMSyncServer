//
//  Settings.swift
//  NetDb
//
//  Created by Christopher Prince on 11/22/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import UIKit
import SMSyncServer
import SMCoreLib

class Settings: UIViewController {
    let signInButton = UIButton(type: .System)
    //let silentlySignIn = UIButton(type: .System)
    let uploadFileButton = UIButton(type: .System)
    let getFileIndex = UIButton(type: .System)
    let showLocalMetaData = UIButton(type: .System)
    
    // Must not be private
    func signInCompletionAction() {
        if SMSyncServerUser.session.signedIn {
            print("SUCCESS signing in!")
        }
        else {
            let alert = UIAlertView(title: "There was an error signing in. Please try again.", message: nil, delegate: nil, cancelButtonTitle: "OK")
            alert.show()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.whiteColor()
    
        SMSyncServerUser.session.signInProcessCompleted.addTarget!(self, withSelector: "signInCompletionAction")

        self.signInButton.setTitle("Sign In", forState: .Normal)
        self.signInButton.sizeToFit()
        self.signInButton.frameOrigin = CGPoint(x: 50, y: 100)
        self.signInButton.addTarget(self, action: "signInButtonAction", forControlEvents: .TouchUpInside)
        self.view.addSubview(self.signInButton)
        
        let verticalDistanceBetweenButtons:CGFloat = 30
        
        self.uploadFileButton.setTitle("Upload Changed Files", forState: .Normal)
        self.uploadFileButton.sizeToFit()
        self.uploadFileButton.frameX = self.signInButton.frameX
        self.uploadFileButton.frameY = self.signInButton.frameMaxY + verticalDistanceBetweenButtons
        self.uploadFileButton.addTarget(self, action: "uploadChangedFilesButtonAction", forControlEvents: .TouchUpInside)
        self.view.addSubview(self.uploadFileButton)
        
        self.getFileIndex.setTitle("Get File Index", forState: .Normal)
        self.getFileIndex.sizeToFit()
        self.getFileIndex.frameX = self.uploadFileButton.frameX
        self.getFileIndex.frameY = self.uploadFileButton.frameMaxY + verticalDistanceBetweenButtons
        self.getFileIndex.addTarget(self, action: "getFileIndexAction", forControlEvents: .TouchUpInside)
        self.view.addSubview(self.getFileIndex)
        
        self.showLocalMetaData.setTitle("Show local meta data", forState: .Normal)
        self.showLocalMetaData.sizeToFit()
        self.showLocalMetaData.frameX = self.getFileIndex.frameX
        self.showLocalMetaData.frameY = self.getFileIndex.frameMaxY + verticalDistanceBetweenButtons
        self.showLocalMetaData.addTarget(self, action: "showLocalMetaDataAction", forControlEvents: .TouchUpInside)
        self.view.addSubview(self.showLocalMetaData)
    }
    
    func getFileIndexAction() {
        // Available for debug builds only.
        SMSyncServer.session.getFileIndex()
    }
    
    func showLocalMetaDataAction() {
        // Available for debug builds only.
        SMSyncServer.session.showLocalFiles()
    }
    
    func signInButtonAction() {
        let signInController = SMCloudStorageCredentials.session.makeSignInController()
        self.navigationController!.pushViewController(signInController, animated: true)
    }
    
    func uploadChangedFilesButtonAction() {
        SMSyncServer.session.commit()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
    }
}


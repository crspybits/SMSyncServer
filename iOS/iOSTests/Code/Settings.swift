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

class Settings: SMGoogleUserSignInViewController {
    let uploadFileButton = UIButton(type: .System)
    let getFileIndex = UIButton(type: .System)
    let showLocalMetaData = UIButton(type: .System)
    
    @objc private func signInCompletionAction(error:NSError?) {
        if SMSyncServerUser.session.signedIn && error == nil {
            print("SUCCESS signing in!")
        }
        else {
            var message:String?
            if error != nil {
                message = "Error: \(error!)"
            }
            let alert = UIAlertView(title: "There was an error signing in. Please try again.", message: message, delegate: nil, cancelButtonTitle: "OK")
            alert.show()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.whiteColor()
    
        SMSyncServerUser.session.signInProcessCompleted.addTarget!(self, withSelector: #selector(signInCompletionAction))
        
        let googleSignIn = SMUserSignInManager.session.possibleAccounts[SMGoogleUserSignIn.displayNameS!] as! SMGoogleUserSignIn
        let googleSignInButton = googleSignIn.signInButton(delegate: self)
        googleSignInButton.frameOrigin = CGPoint(x: 50, y: 100)
        self.view.addSubview(googleSignInButton)
        
        let verticalDistanceBetweenButtons:CGFloat = 30
        
        self.uploadFileButton.setTitle("Upload Changed Files", forState: .Normal)
        self.uploadFileButton.sizeToFit()
        self.uploadFileButton.frameX = googleSignInButton.frameX
        self.uploadFileButton.frameY = googleSignInButton.frameMaxY + verticalDistanceBetweenButtons
        self.uploadFileButton.addTarget(self, action: #selector(uploadChangedFilesButtonAction), forControlEvents: .TouchUpInside)
        self.view.addSubview(self.uploadFileButton)
        
        self.getFileIndex.setTitle("Get File Index", forState: .Normal)
        self.getFileIndex.sizeToFit()
        self.getFileIndex.frameX = self.uploadFileButton.frameX
        self.getFileIndex.frameY = self.uploadFileButton.frameMaxY + verticalDistanceBetweenButtons
        self.getFileIndex.addTarget(self, action: #selector(getFileIndexAction), forControlEvents: .TouchUpInside)
        self.view.addSubview(self.getFileIndex)
        
        self.showLocalMetaData.setTitle("Show local meta data", forState: .Normal)
        self.showLocalMetaData.sizeToFit()
        self.showLocalMetaData.frameX = self.getFileIndex.frameX
        self.showLocalMetaData.frameY = self.getFileIndex.frameMaxY + verticalDistanceBetweenButtons
        self.showLocalMetaData.addTarget(self, action: #selector(showLocalMetaDataAction), forControlEvents: .TouchUpInside)
        self.view.addSubview(self.showLocalMetaData)
        
        let facebookSignIn = SMUserSignInManager.session.possibleAccounts[SMFacebookUserSignIn.displayNameS!] as! SMFacebookUserSignIn
        let fbLoginButton = facebookSignIn.signInButton()
        fbLoginButton.frameX = self.showLocalMetaData.frameX
        fbLoginButton.frameY = self.showLocalMetaData.frameMaxY + verticalDistanceBetweenButtons
        self.view.addSubview(fbLoginButton)
    }
    
    func getFileIndexAction() {
        // Available for debug builds only.
        SMSyncServer.session.getFileIndex()
    }
    
    func showLocalMetaDataAction() {
        // Available for debug builds only.
        SMSyncServer.session.showLocalFiles()
    }
    
    func uploadChangedFilesButtonAction() {
        try! SMSyncServer.session.commit()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
    }
}

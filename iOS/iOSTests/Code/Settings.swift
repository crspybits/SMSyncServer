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
import FBSDKLoginKit

class Settings: UIViewController {
    let signInButton = UIButton(type: .System)
    //let silentlySignIn = UIButton(type: .System)
    let uploadFileButton = UIButton(type: .System)
    let getFileIndex = UIButton(type: .System)
    let showLocalMetaData = UIButton(type: .System)
    
    // Must not be private
    func signInCompletionAction(error:NSError?) {
        if SMSyncServerUser.session.signedIn && error == nil {
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
    
        SMSyncServerUser.session.signInProcessCompleted.addTarget!(self, withSelector: #selector(Settings.signInCompletionAction))

        self.signInButton.setTitle("Sign In", forState: .Normal)
        self.signInButton.sizeToFit()
        self.signInButton.frameOrigin = CGPoint(x: 50, y: 100)
        self.signInButton.addTarget(self, action: #selector(Settings.signInButtonAction), forControlEvents: .TouchUpInside)
        self.view.addSubview(self.signInButton)
        
        let verticalDistanceBetweenButtons:CGFloat = 30
        
        self.uploadFileButton.setTitle("Upload Changed Files", forState: .Normal)
        self.uploadFileButton.sizeToFit()
        self.uploadFileButton.frameX = self.signInButton.frameX
        self.uploadFileButton.frameY = self.signInButton.frameMaxY + verticalDistanceBetweenButtons
        self.uploadFileButton.addTarget(self, action: #selector(Settings.uploadChangedFilesButtonAction), forControlEvents: .TouchUpInside)
        self.view.addSubview(self.uploadFileButton)
        
        self.getFileIndex.setTitle("Get File Index", forState: .Normal)
        self.getFileIndex.sizeToFit()
        self.getFileIndex.frameX = self.uploadFileButton.frameX
        self.getFileIndex.frameY = self.uploadFileButton.frameMaxY + verticalDistanceBetweenButtons
        self.getFileIndex.addTarget(self, action: #selector(Settings.getFileIndexAction), forControlEvents: .TouchUpInside)
        self.view.addSubview(self.getFileIndex)
        
        self.showLocalMetaData.setTitle("Show local meta data", forState: .Normal)
        self.showLocalMetaData.sizeToFit()
        self.showLocalMetaData.frameX = self.getFileIndex.frameX
        self.showLocalMetaData.frameY = self.getFileIndex.frameMaxY + verticalDistanceBetweenButtons
        self.showLocalMetaData.addTarget(self, action: #selector(Settings.showLocalMetaDataAction), forControlEvents: .TouchUpInside)
        self.view.addSubview(self.showLocalMetaData)
        
        let fbLoginButton = FBSDKLoginButton()
        fbLoginButton.frameX = self.showLocalMetaData.frameX
        fbLoginButton.frameY = self.showLocalMetaData.frameMaxY + verticalDistanceBetweenButtons
        fbLoginButton.readPermissions =  ["public_profile", "email", "user_friends"]
        fbLoginButton.delegate = self
        self.view.addSubview(fbLoginButton)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction))
        fbLoginButton.addGestureRecognizer(longPress)
    }
    
    @objc private func longPressAction() {
        if FBSDKAccessToken.currentAccessToken() != nil {
            self.reallyLogOut()
        }
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
        try! SMSyncServer.session.commit()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
    }
}

extension Settings : FBSDKLoginButtonDelegate {
    func loginButton(loginButton: FBSDKLoginButton!, didCompleteWithResult result: FBSDKLoginManagerLoginResult!, error: NSError!) {
        if !result.isCancelled {
            Log.msg("result: \(result); error: \(error)")
            Log.msg("FBSDKAccessToken.currentAccessToken().userID: \(FBSDKAccessToken.currentAccessToken().userID)")
            
            // Adapted from http://stackoverflow.com/questions/29323244/facebook-ios-sdk-4-0how-to-get-user-email-address-from-fbsdkprofile
            let parameters = ["fields" : "email, id, name"]
            FBSDKGraphRequest(graphPath: "me", parameters: parameters).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
                Log.msg("result: \(result); error: \(error)")
            }
            
            // See https://developers.facebook.com/docs/graph-api/reference/user/friends/
            FBSDKGraphRequest(graphPath: "me/friends", parameters: ["fields" : "data"]).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
                Log.msg("result: \(result); error: \(error)")
            }
        }
    }

    func loginButtonDidLogOut(loginButton: FBSDKLoginButton!) {
        
    }
    
    // It seems really hard to fully logout!!! The following helps.
    private func reallyLogOut() {
        let deletepermission = FBSDKGraphRequest(graphPath: "me/permissions/", parameters: nil, HTTPMethod: "DELETE")
        deletepermission.startWithCompletionHandler({ (connection, result, error) in
            print("the delete permission is \(result)")
            FBSDKLoginManager().logOut()
        })
    }
}


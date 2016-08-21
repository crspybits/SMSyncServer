//
//  SignInViewController.swift
//  SharedNotes
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import Foundation
import SMSyncServer
import UIKit

public class SignInViewController: SMGoogleUserSignInViewController {
    let verticalDistanceBetweenButtons:CGFloat = 30

    override public func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.purpleColor()
        
        SMSyncServerUser.session.signInProcessCompleted.addTarget!(self, withSelector: #selector(signInCompletionAction))
        
        let googleSignIn = SMUserSignInManager.session.possibleAccounts[SMGoogleUserSignIn.displayNameS!] as! SMGoogleUserSignIn
        let googleSignInButton = googleSignIn.signInButton(delegate: self)
        googleSignInButton.frameOrigin = CGPoint(x: 50, y: 100)
        self.view.addSubview(googleSignInButton)

        let facebookSignIn = SMUserSignInManager.session.possibleAccounts[SMFacebookUserSignIn.displayNameS!] as! SMFacebookUserSignIn
        let fbLoginButton = facebookSignIn.signInButton()
        fbLoginButton.frameX = googleSignInButton.frameX
        fbLoginButton.frameY = googleSignInButton.frameMaxY + verticalDistanceBetweenButtons
        self.view.addSubview(fbLoginButton)
    }

    @objc private func signInCompletionAction(error:NSError?) {
        if SMSyncServerUser.session.signedIn && error == nil {
            print("SUCCESS signing in!")
            self.navigationController?.popViewControllerAnimated(true)
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
}
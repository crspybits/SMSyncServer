//
//  SMGoogleSignInController.swift
//  NetDb
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import Foundation

// 1/16/16; This is needed when building SMSyncServer as a framework. It wasn't needed when building as a project.
import Google

public class SMGoogleSignInController: UIViewController, GIDSignInUIDelegate {
    var signInButton: GIDSignInButton!
    var signOutButton: UIButton!
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.purpleColor()
        
        self.signInButton = GIDSignInButton(frame: CGRect(x: 50, y: 200, width: 200, height: 100))
        self.view.addSubview(self.signInButton)
        
        self.signOutButton = UIButton(type: .Custom)
        self.signOutButton.setTitle("Sign Out", forState: .Normal)
        self.signOutButton.frame = signInButton.frame
        
        var frame = self.signOutButton.frame
        frame.origin.y += 100
        self.signOutButton.frame = frame

        self.view.addSubview(self.signOutButton)
        
        self.signOutButton.addTarget(self, action: #selector(SMGoogleSignInController.signOutButtonAction), forControlEvents: .TouchUpInside)
        
        GIDSignIn.sharedInstance().uiDelegate = self
        
        //GIDSignIn.sharedInstance().signInSilently()
    }
    
    // Must not be private
    func signOutButtonAction() {
        GIDSignIn.sharedInstance().signOut()
    }
}
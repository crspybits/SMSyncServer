//
//  SMGoogleSignInController.swift
//  NetDb
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import Foundation
import SMSyncServer
import Google

public class SMGoogleSignInController: UIViewController, GIDSignInUIDelegate {
    var signInButton: GIDSignInButton!
    var signOutButton: UIButton!
    var sync:UIButton!
    
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
        self.signOutButton.addTarget(self, action: #selector(signOutButtonAction), forControlEvents: .TouchUpInside)
        
        /*
        self.sync = UIButton(type: .Custom)
        self.sync.setTitle("Sync", forState: .Normal)
        frame.origin.y += 100
        self.sync.frame = frame
        self.view.addSubview(self.sync)
        self.sync.addTarget(self, action: #selector(syncButtonAction), forControlEvents: .TouchUpInside)
        */
        
        GIDSignIn.sharedInstance().uiDelegate = self
        
        SMSyncServerUser.session.signInProcessCompleted.addTarget!(self, withSelector: #selector(signInCompletedAction))
    }
    
    @objc private func signOutButtonAction() {
        GIDSignIn.sharedInstance().signOut()
    }

    @objc private func syncButtonAction() {
        SMSyncServer.session.sync()
    }
    
    @objc private func signInCompletedAction() {
        self.navigationController?.popViewControllerAnimated(true)
    }
}
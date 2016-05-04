//
//  ViewController.swift
//  SharedNotes
//
//  Created by Christopher Prince on 4/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMSyncServer

class ViewController: UIViewController {
    let spinner = SyncSpinner(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SMSyncServer.session.delegate = self
        
        let barButtonSpinner = UIBarButtonItem(customView: spinner)
        self.navigationItem.leftBarButtonItem = barButtonSpinner
    }

    @IBAction func signInAction(sender: AnyObject) {
        let signInController = SMCloudStorageCredentials.session.makeSignInController()
        self.navigationController!.pushViewController(signInController, animated: true)
    }
}

extension ViewController : SMSyncServerDelegate {
    func syncServerDownloadsComplete(downloadedFiles: [(NSURL, SMSyncAttributes)], acknowledgement: () -> ()) {
    }
    
    func syncServerClientShouldDeleteFiles(uuids: [NSUUID], acknowledgement: () -> ()) {
    }
    
    func syncServerModeChange(newMode: SMSyncServerMode) {
        switch newMode {
        case .Synchronizing:
            self.spinner.start()
            self.spinner.setNeedsLayout()
            
        case .Idle, .NetworkNotConnected, .ClientAPIError, .NonRecoverableError, .InternalError:
            self.spinner.stop()
            self.spinner.setNeedsLayout()
        }
    }
    
    func syncServerEventOccurred(event: SMSyncServerEvent) {
    }
}


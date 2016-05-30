//
//  Misc.swift
//  US
//
//  Created by Christopher Prince on 5/30/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

class Misc {
    class func showAlert(fromParentViewController parentViewController:UIViewController, title:String, message:String?=nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        alert.popoverPresentationController?.sourceView = parentViewController.view
        alert.addAction(UIAlertAction(title: SMUIMessages.session().OkMsg(), style: .Default) {alert in
        })
        parentViewController.presentViewController(alert, animated: true, completion: nil)
    }
}


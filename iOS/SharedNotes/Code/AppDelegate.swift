//
//  AppDelegate.swift
//  SharedNotes
//
//  Created by Christopher Prince on 4/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import CoreData
import SMSyncServer
import SMCoreLib
import FFGlobalAlertController

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    private static let _sharingInvitationCode = SMPersistItemString(name: "AppDelegate.sharingInvitationCode", initialStringValue: "", persistType: .UserDefaults)
    
    static var sharingInvitationCode:String? {
        get {
            return self._sharingInvitationCode.stringValue == "" ? nil : self._sharingInvitationCode.stringValue
        }
        set {
            self._sharingInvitationCode.stringValue = newValue == nil ? "" : newValue!
        }
    }
    
    private static let userSignInDisplayName = SMPersistItemString(name: "AppDelegate.userSignInDisplayName", initialStringValue: "", persistType: .UserDefaults)
    
    var window: UIWindow?

    // MARK: Developers making use of SharedNotes demo app need to change the contents of this plist file.
    private let smSyncServerClientPlist = "SMSyncServer-client.plist"
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    
        Log.redirectConsoleLogToDocumentFolder(clearRedirectLog: false)
    
        let coreDataSession = CoreData(namesDictionary: [
            CoreDataBundleModelName: "SharedNotes",
            CoreDataSqlliteBackupFileName: "~SharedNotes.sqlite",
            CoreDataSqlliteFileName: "SharedNotes.sqlite"
        ]);
        
        CoreData.registerSession(coreDataSession, forName: CoreDataExtras.sessionName)

        let (serverURLString, cloudFolderPath, googleServerClientId) = SMSyncServer.getDataFromPlist(syncServerClientPlistFileName: smSyncServerClientPlist)
        
        // This is the path on the cloud storage service (Google Drive for now) where the app's data will be synced
        SMSyncServerUser.session.cloudFolderPath = cloudFolderPath
        
        // Starting to establish account credentials-- user will also have to sign in to their specific account.
        let googleSignIn = SMGoogleUserSignIn(serverClientID: googleServerClientId)
        googleSignIn.delegate = self
        SMUserSignInManager.session.addSignInAccount(googleSignIn, launchOptions:launchOptions)
        
        let facebookSignIn = SMFacebookUserSignIn()
        facebookSignIn.delegate = self
        SMUserSignInManager.session.addSignInAccount(facebookSignIn, launchOptions:launchOptions)
        
        // Setup the SMSyncServer (Node.js) server URL.
        let serverURL = NSURL(string: serverURLString)
        SMSyncServer.session.appLaunchSetup(withServerURL: serverURL!, andUserSignInLazyDelegate: SMUserSignInManager.session.lazyCurrentUser)
        
        SMUserSignInManager.session.delegate = self
        
        return true
    }
    
    func application(application: UIApplication,
        openURL url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
        
        if SMUserSignInManager.session.application(application, openURL: url, sourceApplication: sourceApplication, annotation: annotation) {
            return true
        }

        return false
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}

extension AppDelegate : SMUserSignInAccountDelegate {
    func smUserSignIn(userJustSignedIn userSignIn:SMUserSignInAccount) {
        guard AppDelegate.userSignInDisplayName.stringValue == "" || AppDelegate.userSignInDisplayName.stringValue == userSignIn.displayNameI!
        else {
            Assert.badMojo(alwaysPrintThisString: "Yikes: Need to sign out of other sign-in (\(AppDelegate.userSignInDisplayName.stringValue))!")
            return
        }
        
        AppDelegate.userSignInDisplayName.stringValue = userSignIn.displayNameI!
    }
    
    func smUserSignIn(userJustSignedOut userSignIn:SMUserSignInAccount) {
        // In some non-fatal error cases, we can have userJustSignedOut called and we we'ren't officially signed in. E.g., when trying to sign in, but the sign in fails. SO, don't make this a fatal issue, just log a message.
        if AppDelegate.userSignInDisplayName.stringValue != userSignIn.displayNameI! {
            Log.error("Not currently signed into userSignIn.displayName!: \(userSignIn.displayNameI)")
        }
        
        AppDelegate.userSignInDisplayName.stringValue = ""
    }
    
    func smUserSignIn(activelySignedIn userSignIn:SMUserSignInAccount) -> Bool {
        return AppDelegate.userSignInDisplayName.stringValue == userSignIn.displayNameI!
    }
    
    func smUserSignIn(getSharingInvitationCodeForUserSignIn userSignIn:SMUserSignInAccount) -> String? {
        return AppDelegate.sharingInvitationCode
    }
    
    func smUserSignIn(resetSharingInvitationCodeForUserSignIn userSignIn:SMUserSignInAccount) {
        AppDelegate.sharingInvitationCode = nil
    }
    
    func smUserSignIn(userSignIn userSignIn:SMUserSignInAccount, linkedAccountsForSharingUser:[SMLinkedAccount], selectLinkedAccount:(internalUserId:SMInternalUserId)->()) {
        // TODO: What we really need to do here is to put up a UI and ask the user which linked account they want to use. That is, if there is more than one linked account. For now, just choose the first.
        selectLinkedAccount(internalUserId: linkedAccountsForSharingUser[0].internalUserId)
    }
}

extension AppDelegate : SMUserSignInManagerDelegate {
    // This gets called when the user clicks on a sharing invitation URL in an email, or pastes that URL into a browser
    func didReceiveSharingInvitation(manager:SMUserSignInManager, invitationCode: String, userName: String?) {
        AppDelegate.sharingInvitationCode = invitationCode
        // TODO: We should really just put up a UI here to ask them if they want to sign into their FB account. This will redeem the sharing invitation.
        var alert:UIAlertController
        var okAction:()->()
        
        let navController = self.window?.rootViewController as? UINavigationController
        if navController == nil {
            Log.error("Could not get the root view controller!")
        }
        
        var message:String
        // TODO: Need to make sure the signed in account is a sharing account.
        if SMSyncServerUser.session.signedIn {
            // This is really a bigger picture issue: If there is data, then this amounts to sharing other data, and we're not setup to deal with that.
            message = "Redeem it with your current account?"
            okAction = {
            }
        }
        else {
            message = "Sign into your Facebook account and redeem it?"
            okAction = {
                let signInController = SignInViewController()
                navController?.popToRootViewControllerAnimated(true)
                navController?.pushViewController(signInController, animated: true)
            }
        }
        
        alert = UIAlertController(title: "You got a sharing invite!", message: message, preferredStyle: .Alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel){alert in
        })
        alert.addAction(UIAlertAction(title: "OK", style: .Default){alert in
            okAction()
        })
        alert.show()
    }
}

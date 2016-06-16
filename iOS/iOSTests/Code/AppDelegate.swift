//
//  AppDelegate.swift
//  NetDb
//
//  Created by Christopher Prince on 11/22/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMCoreLib
import SMSyncServer

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
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
    
    // MARK: Users of SMSyncServer iOSTests client need to change the contents of this file.
    private let smSyncServerClientPlist = "SMSyncServer-client.plist"

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    
        let coreDataSession = CoreData(namesDictionary: [
            CoreDataBundleModelName: "ClientAppModel",
            CoreDataSqlliteBackupFileName: "~ClientAppModel.sqlite",
            CoreDataSqlliteFileName: "ClientAppModel.sqlite"
        ]);
        
        CoreData.registerSession(coreDataSession, forName: CoreDataTests.name)
        
        let (serverURLString, cloudFolderPath, googleServerClientId) = SMSyncServer.getDataFromPlist(syncServerClientPlistFileName: smSyncServerClientPlist)
        
        // This is the path on the cloud storage service (Google Drive for now) where the app's data will be synced
        SMSyncServerUser.session.cloudFolderPath = cloudFolderPath
        
        // Starting to establish account credentials-- user will also have to sign in to their specific account.
        let googleSignIn = SMGoogleUserSignIn(serverClientID: googleServerClientId)
        googleSignIn.activeSignInDelegate = self
        SMUserSignInManager.session.addSignInAccount(googleSignIn, launchOptions:launchOptions)
        
        let facebookSignIn = SMFacebookUserSignIn()
        facebookSignIn.activeSignInDelegate = self
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

extension AppDelegate : SMActivelySignedInUserDelegate {
    func smUserSignIn(userJustSignedIn userSignIn:SMUserSignInAccountDelegate) {
        guard AppDelegate.userSignInDisplayName.stringValue == "" || AppDelegate.userSignInDisplayName.stringValue == userSignIn.displayNameI!
        else {
            Assert.badMojo(alwaysPrintThisString: "Yikes: Need to sign out of other sign-in (\(AppDelegate.userSignInDisplayName.stringValue))!")
            return
        }
        
        AppDelegate.userSignInDisplayName.stringValue = userSignIn.displayNameI!
    }
    
    func smUserSignIn(userJustSignedOut userSignIn:SMUserSignInAccountDelegate) {
        guard AppDelegate.userSignInDisplayName.stringValue == userSignIn.displayNameI!
        else {
        Assert.badMojo(alwaysPrintThisString: "Yikes: Not currently signed into userSignIn.displayName!")
            return
        }
        
        AppDelegate.userSignInDisplayName.stringValue = ""
    }
    
    func smUserSignIn(activelySignedIn userSignIn:SMUserSignInAccountDelegate) -> Bool {
        return AppDelegate.userSignInDisplayName.stringValue == userSignIn.displayNameI!
    }
}

extension AppDelegate : SMUserSignInManagerDelegate {
    func didReceiveSharingInvitation(manager:SMUserSignInManager, invitationCode: String, userName: String?) {
        AppDelegate.sharingInvitationCode = invitationCode
    }
}

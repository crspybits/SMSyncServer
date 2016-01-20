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
    
    // My testing so far has been with the Node.js server running on my development Mac on my local network.
    // TODO: Need to make use of https
    // MARK: CHANGE THIS IN YOUR CODE
    let serverURL = NSURL(string: "http://192.168.0.7:8081")
    // MARK: CHANGE THIS IN YOUR CODE

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        
        let coreDataSession = CoreData(namesDictionary: [
            CoreDataBundleModelName: "ClientAppModel",
            CoreDataSqlliteBackupFileName: "~ClientAppModel.sqlite",
            CoreDataSqlliteFileName: "ClientAppModel.sqlite"
        ]);
        
        CoreData.registerSession(coreDataSession, forName: CoreDataTests.name)
        
        // TODO: Eventually give the user a way to change the cloud folder path. BUT: It's a big change. i.e., the user shouldn't change this lightly because it will mean all of their data has to be moved or re-synced. (Plus, the SMSyncServer currently has no means to do such a move or re-sync-- it would have to be handled at a layer above the SMSyncServer).
        SMSyncServerUser.session.cloudFolderPath = "Petunia.SyncServer"
        
        // MARK: CHANGE THIS IN YOUR CODE
        // When trying this example app, you need to replace serverClientID with the client id, you create on the Google Developers site, for your own server.
        // You also need to replace the file GoogleService-Info.plist with your own, plus change the URL Scheme's, that are specific to the example credentials, with your own.
        SMCloudStorageCredentials.session = SMGoogleCredentials(serverClientID: "973140004732-bbgbqh5l8pmcr6lhmoh2cgggdkelh9gf.apps.googleusercontent.com")
        // MARK: CHANGE THIS IN YOUR CODE
        
        SMSyncServer.session.appLaunchSetup(withServerURL: self.serverURL!, andCloudStorageUserDelegate: SMCloudStorageCredentials.session)

        return true
    }
    
    func application(application: UIApplication,
        openURL url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
        
        return SMCloudStorageCredentials.session.handleURL(url, sourceApplication: sourceApplication, annotation: annotation)
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


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
    
    // MARK: Users of SMSyncServer iOSTests client need to change the contents of this file.
    private let smSyncServerClientPlist = "SMSyncServer-client.plist"

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        
        // Extract parameters out of smSyncServerClientPlist
        let bundlePath = NSBundle.mainBundle().bundlePath as NSString
        let syncServerClientPlistPath = bundlePath.stringByAppendingPathComponent(smSyncServerClientPlist)
        let syncServerClientPlistData = NSDictionary(contentsOfFile: syncServerClientPlistPath)
        
        Assert.If(syncServerClientPlistData == nil, thenPrintThisString: "Could not access your \(smSyncServerClientPlist) file at: \(syncServerClientPlistPath)")
        
        var serverURLString:String?
        var cloudFolderPath:String?
        var googleServerClientId:String?
        
        func getDictVar(varName:String, inout result:String?) {
            result = syncServerClientPlistData![varName] as? String
            Assert.If(result == nil, thenPrintThisString: "Could not access \(varName) in \(smSyncServerClientPlist)")
            Log.msg("Using: \(varName): \(result)")
        }
        
        getDictVar("ServerURL", result: &serverURLString)
        getDictVar("CloudFolderPath", result: &cloudFolderPath)
        getDictVar("GoogleServerClientID", result: &googleServerClientId)
    
        let coreDataSession = CoreData(namesDictionary: [
            CoreDataBundleModelName: "ClientAppModel",
            CoreDataSqlliteBackupFileName: "~ClientAppModel.sqlite",
            CoreDataSqlliteFileName: "ClientAppModel.sqlite"
        ]);
        
        CoreData.registerSession(coreDataSession, forName: CoreDataTests.name)
        
        // TODO: Eventually give the user a way to change the cloud folder path. BUT: It's a big change. i.e., the user shouldn't change this lightly because it will mean all of their data has to be moved or re-synced. (Plus, the SMSyncServer currently has no means to do such a move or re-sync-- it would have to be handled at a layer above the SMSyncServer).
        SMSyncServerUser.session.cloudFolderPath = cloudFolderPath
        
        SMCloudStorageCredentials.session = SMGoogleCredentials(serverClientID: googleServerClientId!)
        
        let serverURL = NSURL(string: serverURLString!)
        SMSyncServer.session.appLaunchSetup(withServerURL: serverURL!, andCloudStorageUserDelegate: SMCloudStorageCredentials.session)

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


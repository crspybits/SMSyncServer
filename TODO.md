Contents:  
[Introduction](#markdown-header-introduction)  
[Development Status](#markdown-header-development-status)  
[Installation](#markdown-header-installation)  
[Usage examples](#markdown-header-usage-examples)  

# Introduction

SMSyncServer has the following general goals:  

1. Giving end-users permanent access to their mobile app data,  
1. Synchronizing mobile app data across end-user devices,  
1. Reducing data storage costs for app developers/publishers, and  
1. Allowing sharing of data with other users. 

SMSyncServer has an iOS client and a server written in Javascript/Node.js.

More detailed characteristics of the SMSyncServer:

1. The large majority of file information (i.e., all of the file content information) is stored in end-user cloud storage accounts. Only meta data for files, locking information, and some user credentials information is stored in the MongoDb database on the server.
1. Client apps can operate offline. The client API queues operations (e.g., uploads) until network access is available.
1. Interrupted operations are retried. For example, if network access is lost during a series of file uploads, then those uploads are retried when network access is available.
1. Uploads (and downloads) are performed in a locked (a.k.a., transactional) manner. For example, if you queue a series uploads using `uploadImmutableFile` followed by a `commit`, those upload operations are carried out in an atomic manner, and are only available for download by other SMSyncServer client apps (using the same cloud storage credentials) when the entire set of files has been uploaded.

See the blog articles:  

* [The SyncServer: Permanent Access to Your App Data](http://www.spasticmuffin.biz/blog/2015/12/29/the-syncserver-permanent-access-to-your-app-data/)  
* [Blitz to get SMSyncServer Ready for Open-Source](http://www.spasticmuffin.biz/blog/2016/01/21/blitz-to-get-smsyncserver-ready-for-open-source/)
* [Design Issue: Changing Cloud Storage Accounts With The SMSyncServer](http://www.spasticmuffin.biz/blog/2016/04/02/design-issue-changing-cloud-storage-accounts-with-the-smsyncserver/)
* [The Many Senses of Recovery in SMSyncServer](http://www.spasticmuffin.biz/blog/2016/04/26/the-many-senses-of-recovery-in-smsyncserver/)

Contact: <chris@SpasticMuffin.biz> (primary developer)

# Development Status

* The SMSyncServer project is in "alpha" and supports uploading, upload-deletion, downloading, and download-deletion. Conflict management for downloaded files is pending.
* Currently only Google Drive is supported in terms of cloud storage systems.
* Sharing with other users currently amounts to complete read/write access to all files with other users accessing with the same cloud storage credentials. There are plans for more sophisticated access control.

# Installation
## 1) Create Google Developer Credentials

* Create Google Developer credentials for your iOS app using the SMSyncServer Framework and the SMSyncServer Node.js server. These credentials need to be installed in either the iOSTests app or in your app making use of the iOSFramework. See
<https://developers.google.com/identity/sign-in/ios/>

## 2) MongoDb installation

* SMSyncServer makes use of MongoDb to store file meta data and locks. Current tests are using MongoDb locally on a Mac OS X system (version v3.0.7), and on [mLab](https://www.mlab.com) as an add-on service through [Heroku](https://heroku.com). You can [find MongoDb here](https://www.mongodb.org).

## 3) Server installation

* Create your own `serverSecrets.json` file (i.e., `Server/Code/serverSecrets.json`). This file is not in the public repo because it has private info -- it is in the SMSyncServer .gitignore file. You must create your own. This file contains keys for cloud storage access and for MongoDb access. Its structure is as follows:

### `serverSecrets.json`

	{
		"MongoDbURL": "mongodb://<snip>",
		"CloudStorageServices": {
			"GoogleDrive": {
				"client_id": "<snip>",
				"client_secret": "<snip>",
				"redirect_uris": [
					"<snip>"
				],
				"auth_uri": "https://accounts.google.com/o/oauth2/auth",
				"token_uri": "https://accounts.google.com/o/oauth2/token"
			}
		}
	}
	
Each entry in the `CloudStorageServices` dictionary must abide by the structure required for the particular cloud storage service. For Google Drive, see [Google Sign In](https://developers.google.com/identity/sign-in/ios/).

* The SMSyncServer server is written in Node.js. Current tests are using Node.js v5.1.0 on Mac OS X and on [Heroku](https://heroku.com). You can find [Node.js here](https://nodejs.org/).

* A startup script to run the SMSyncServer Node.js on your local Mac OS X system is `Server/Code/Scripts/startServer.sh`.

* A startup script to run the SMSyncServer Node.js server on [Heroku](https://heroku.com) is `Server/Code/startOnHeroku.sh`. This script assumes you already have created an account on Heroku and installed the Heroku Toolbelt. This script also assumes you have have initialized a Git project within `Server/Code/` and created the Heroku server/app. You need to initially do something like:

		git init
		git add .
		git commit -a -m "Initial commit"
		heroku create
		mv .ignored.git .git
		# The last line is needed because I don't have the server code setup as a Git submodule.

## 4) Using the iOSTests Example App with the iOSFramework iOS Framework

* A useful way to get familiar with the client (iOS app) side of the SMSyncServer system is to use the provided sample app. This is contained in the iOSTests folder.

* Next, you need to replace the `GoogleService-Info.plist` symbolic link with your actual .plist file and edit the URL Scheme's in this Xcode project to match your Google credentials. See:
<https://developers.google.com/identity/sign-in/ios/>

* You need to replace the `SMSyncServer-client.plist` symbolic link with your actual .plist file. The value of the GoogleServerClientID key is from your Google credentials. The CloudFolderPath key should be the name of the directory (no slashes-- we're not supporting subdirectories yet) where your SMSyncServer files will be stored in Google Drive. ServerURL is the URL of your SMSyncServer Node.js server. Here's it's format:

### `SMSyncServer-client.plist`

            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>ServerURL</key>
                <string>http://URL-OF-YOUR-SMSyncServerNode.js.Server</string>
                <key>CloudFolderPath</key>
                <string>YourCustomPathFromGoogleDriveRoot</string>
                <key>GoogleServerClientID</key>
                <string>YourGoogleServerClientID</string>
            </dict>
            </plist>

* You should now be ready to build the Tests.workspace onto your device.

## 5) Adding the iOSFramework into your own Xcode project 

* Drag the file `iOSFramework/Code/Signin/SMGoogleCredentials.swift` into your Xcode project. This .swift file depends on the Google Sign In Framework (see next step), which is not linked into the SMSyncServer framework, and so isn't explicitly part of the SMSyncServer framework.

* You need most of the code in your App Delegate from the example AppDelegate.swift file-- all of it except for that using Core Data. See the method `didFinishLaunchingWithOptions` and the method:

		func application(application: UIApplication,
			openURL url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
		}

* You need to create your own `SMSyncServer-client.plist` file. See above.

* Link the [Google SignIn Framework](https://developers.google.com/identity/sign-in/ios/) into your app. It seems easiest to do this [using the Cocoapod](https://developers.google.com/identity/sign-in/ios/start-integrating). As indicated in these directions, you will need to create or use a configuration file (`GoogleService-Info.plist`). Your `client_id` and `client_secret` will need to be placed into your `serverSecrets.json` server file. See above.

* With your own Xcode project open in Xcode and with a Mac OS Finder folder open so you can see iOSFramework files, you need to drag `SMSyncServer.xcodeproj` from the iOSFramework folder into your Xcode project.

* Then, entirely within your Xcode project, drag SMSyncServer.framework to Embedded Binaries in the General tab.

* Also entirely within your Xcode project, locate SMCoreLib.framework and drag this to Embedded Binaries in the General tab (while you don't have to explicitly make use of SMCoreLib in your code, it is used by the SMSyncServer Framework, and this step seems necessary to build).

* You might get the error "App Transport Security has blocked a cleartext HTTP (http://) resource load since it is insecure. Temporary exceptions can be configured via your app's Info.plist file." when you try run your app. For testing, you may want to use HTTP instead of HTTPS to access your SMSyncServer server. To do this, you can add the following to your app's Info.plist:

		<key>NSAppTransportSecurity</key>
		<dict>
			<key>NSAllowsArbitraryLoads</key>
			<true/>
		</dict>

* When you get to the point you see "Error signing in: Error Domain=com.google.GIDSignIn Code=-4" on the console log, you know you are making progress! Your next steps should include allowing the user to sign-in to their cloud storage account, and making sure you have the [URL Schemes required by Google SignIn](https://developers.google.com/identity/sign-in/ios/start-integrating#add-config).

* You will also need to setup a delegate for the SMSyncServer session shared instance.

# Demo App: Shared Notes

In `iOS/Shared Notes` there is a demo app, which enables multiple devices to access the same collection of notes across iOS devices. Open the project `Shared Notes.workspace` in Xcode.

# Usage Examples
* The most comprehensive set of usage examples are in the XCTests in the sample iOSTests app (though some of these make use of internal methods using `@testable`). The following examples are extracted from those XCTests.

* In the following an `immutable` file is one assumed to not change while upload is occurring. A `temporary` file is one that will be deleted after upload.

* The `SMSyncServer.session.delegate` provides information about the completion of server operations, errors etc.

* Files are referenced by UUID's. Typically this occurs via `SMSyncAttributes` objects. Example:

	`SMSyncAttributes(withUUID: NSUUID(UUIDString: fileUUID)!, mimeType: "text/plain", andRemoteFileName: cloudStorageFileName)`

## 1) Uploading: Immutable Files

	let testFile1 = TestBasics.session.createTestFile("TwoFileUpload1")
	
	SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
	
	let testFile2 = TestBasics.session.createTestFile("TwoFileUpload2")
	
	SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
	
	SMSyncServer.session.commit()
    
## 2) Uploading: Temporary Files

	let testFile = TestBasics.session.createTestFile("SingleTemporaryFileUpload")
	
	SMSyncServer.session.uploadTemporaryFile(testFile.url, withFileAttributes: testFile.attr)
	
	SMSyncServer.session.commit()

## 3) Uploading: NSData

	let cloudStorageFileName = "SingleDataUpload"
	let fileUUID = UUID.make()
	let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: fileUUID)!, mimeType: "text/plain", andRemoteFileName: cloudStorageFileName)
	
	let strData: NSString = "SingleDataUpload file contents"
	let data = strData.dataUsingEncoding(NSUTF8StringEncoding)
	
	SMSyncServer.session.uploadData(data!, withDataAttributes: fileAttributes)
	
	SMSyncServer.session.commit()

## 4) Deletion

This allows you to mark a file as deleted locally, and also mark it as deleted on the server. Other devices, on a download, will have the delegate method `syncServerClientShouldDeleteFiles` triggered (see below).

	// File referenced by uuid is assumed to exist in cloud storage
	let uuid = ...
	
	SMSyncServer.session.deleteFile(uuid)
	
	SMSyncServer.session.commit()
        
## 5) Download

Downloads are caused by other devices uploading files, and these are initiated by the SMSyncServer and reported by the delegate method `syncServerDownloadsComplete` (see below). If needed, you can programmatically make a sync request which will do any currently needed downloads:

	SMSyncServer.session.sync()
    
## 6) SMSyncServer.session.delegate

	public protocol SMSyncServerDelegate : class {
		// Called at the end of all downloads, on non-error conditions. Only called when there was at least one download.
		// The callee owns the files referenced by the NSURL's after this call completes. These files are temporary in the sense that they will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location. See [1] for a design note about this delegate method. This is received/called in an atomic manner: This reflects the current state of files on the server.
		// The callee must call the acknowledgement callback when it has finished dealing with (e.g., persisting) the list of downloaded files.
		func syncServerDownloadsComplete(downloadedFiles:[(NSURL, SMSyncAttributes)], acknowledgement:()->())
		
		// Called when deletion indications have been received from the server. I.e., these files have been deleted on the server. This is received/called in an atomic manner: This reflects the current state of files on the server. The recommended action is for the client to delete the files represented by the UUID's.
		// The callee must call the acknowledgement callback when it has finished dealing with (e.g., carrying out deletions for) the list of deleted files.
		func syncServerClientShouldDeleteFiles(uuids:[NSUUID], acknowledgement:()->())
	
		// Reports mode changes including errors. Can be useful for presenting a graphical user-interface which indicates ongoing server/networking operations. E.g., so that the user doesn't close or otherwise the dismiss the app until server operations have completed.
		func syncServerModeChange(newMode:SMSyncServerMode)
	
		// Reports events. Useful for testing and debugging.
		func syncServerEventOccurred(event:SMSyncServerEvent)
	}


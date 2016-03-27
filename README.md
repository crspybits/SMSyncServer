Contents:  
[Introduction](#markdown-header-introduction)  
[Development Status](#markdown-header-development-status)  
[Installation](#markdown-header-installation)  
[Usage examples](#markdown-header-usage-examples)  

# Introduction

SMSyncServer has the following goals:  

1. Giving end-users permanent access to their mobile app data,  
1. Synchronizing mobile app data across end-user devices,  
1. Reducing data storage costs for app developers/publishers, and  
1. Allowing sharing of data with other users. 

SMSyncServer has an iOS client and a server written in Javascript/Node.js.

See the blog articles:  

* [The SyncServer: Permanent Access to Your App Data](http://www.spasticmuffin.biz/blog/2015/12/29/the-syncserver-permanent-access-to-your-app-data/)  
* [Blitz to get SMSyncServer Ready for Open-Source](http://www.spasticmuffin.biz/blog/2016/01/21/blitz-to-get-smsyncserver-ready-for-open-source/)

Contact: <chris@SpasticMuffin.biz> (primary developer)

# Development Status

* The SMSyncServer project is in "alpha" and supports uploading, upload-deletion, and downloading. Download-deletion and conflict management for downloaded files is pending.

# Installation
## 1) Create Google Developer Credentials

* Create Google Developer credentials for your iOS app using the SMSyncServer Framework and the SMSyncServer Node.js server. These credentials need to be installed in either the iOSTests app or in your app making use of the iOSFramework. See
<https://developers.google.com/identity/sign-in/ios/>

## 2) MongoDb installation

* SMSyncServer makes use of Mongo. Current tests are using v3.0.7 running on Mac OS X. You can [find Mongo here](https://www.mongodb.org). After installation a script to start Mongo is at `Server/Code/Scripts/startMongoDb.sh`

## 3) Server installation

* The SMSyncServer server makes use of Node.js. Current tests are using v5.1.0 on Mac OS X. You can find [Node.js here](https://nodejs.org/).

* Create your own `client_secret.json` file (See `Server/Code/client_secret.json`). It’s currently a symbolic link and must be replaced. The info in this file is from [Google Sign In](https://developers.google.com/identity/sign-in/ios/). Its structure as follows:

### `client_secret.json`

            {
              "installed": {
                "client_id": "<snip>",
                "client_secret": "<snip>",
                "redirect_uris": ["<snip>"],
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://accounts.google.com/o/oauth2/token"
              }
            }

* A startup script for the SMSyncServer Node.js server is `Server/Code/Scripts/startServer.sh`. (When using this startServer script and you have the server running remotely-- specifically, when the iOSFramework folder is not available, you'll need to comment out the line `./Scripts/makeServerConstants.sh` in the startup script). 


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

* You can also install the SMSyncServer iOS Framework into your own Xcode project.  

* A useful way to get started with this is to look at the AppDelegate of the sample app, and to look at the "Cloud Storage User Credentials" Xcode group/folder in that sample app. 

* Link the [Google Sign Framework](https://developers.google.com/identity/sign-in/ios/) into your app. It seems easiest to do this using the Cocoapod. 

* With your own Xcode project open in Xcode and with a Mac OS Finder folder open so you can see iOSFramework files, you need to drag `SMSyncServer.xcodeproj` from the iOSFramework folder into your Xcode project.

* Then, entirely within your Xcode project, drag SMSyncServer.framework to Embedded Binaries in the General tab.

* Also entirely within your Xcode project, locate SMCoreLib.framework and drag this to Embedded Binaries in the General tab (while you don't have to explicitly make use of SMCoreLib in your code, it is used by the SMSyncServer Framework, and this step seems necessary to build).

# Usage Examples
* The most comprehensive set of usage examples are in the XCTests in the sample iOSTests app (though some of these make use of internal methods using @testable). The following examples are extracted from those XCTests.

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

	// File referenced by uuid is assumed to exist in cloud storage
	let uuid = ...
	
	SMSyncServer.session.deleteFile(uuid)
	
	SMSyncServer.session.commit()
        
## 5) Download

Since downloads are caused by other devices uploading files, these are initiated by the SMSyncServer and reported by the delegate method syncServerDownloadsComplete (see below).
    
## 5) SMSyncServer.session.delegate

	public protocol SMSyncServerDelegate : class {

		// Called at the end of all downloads, on non-error conditions. Only called when there was at least one download.
		// The callee owns the files referenced by the NSURL's after this call completes. These files are temporary in the sense that they will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location. See [1] for a design note about this delegate method. This is received/called in an atomic manner: This reflects the current state of files on the server.
		func syncServerDownloadsComplete(downloadedFiles:[(NSURL, SMSyncAttributes)])
	
		// Reports mode changes including errors. Can be useful for presenting a graphical user-interface which indicates ongoing server/networking operations. E.g., so that the user doesn't close or otherwise the dismiss the app until server operations have completed.
		func syncServerModeChange(newMode:SMClientMode)
	
		// Reports events. Useful for testing and debugging.
		func syncServerEventOccurred(event:SMClientEvent)
	}



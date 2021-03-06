This version of SyncServer is deprecated and not supported. See [SyncServerII](https://github.com/crspybits/SyncServerII).

Contents:  
[Introduction](#introduction)  
[Development Status](#development-status)  
[Installation](#installation)  
[SharedNotes Demo App](#shared-notes-demo-app)  
[Usage examples](#usage-examples)  

# Introduction

SMSyncServer has the following general goals:  

1. Giving end-users permanent access to their mobile app data,  
1. Synchronizing mobile app data across end-user devices,  
1. Reducing data storage costs for app developers/publishers,  
1. Allowing sharing of data with other users,  
1. Cross-platform synchronization (e.g., iOS, Android), and  
1. Synchronized devices need only be [Occasionally Connected](https://msdn.microsoft.com/en-us/library/ff650163.aspx) to a network.

More detailed characteristics of the SMSyncServer:

1. The large majority of file information (i.e., all of the file content information) is stored in end-user cloud storage accounts. Only meta data for files, locking information, and some user credentials information is stored in the MongoDb database on the server.
1. Client apps can operate offline. The client API queues operations (e.g., uploads) until network access is available.
1. Interrupted operations are retried. For example, if network access is lost during a series of file uploads, then those uploads are retried when network access is available.
1. Uploads (and downloads) are performed in a locked (a.k.a., transactional) manner. For example, if you queue a group of uploads using `uploadImmutableFile` followed by a `commit`, those upload operations are carried out in an atomic manner, and are only available for download by other SMSyncServer client apps (using the same cloud storage credentials) when the entire group of files has been uploaded.
1. Conflict resolution is carried out at the client-level using delegate callbacks provided by the client API. E.g., if the client is dealing with text files, it can do app-specific merge operations on those text files when there is a conflict.

See the blog articles:

* [The SyncServer: Permanent Access to Your App Data](http://www.spasticmuffin.biz/blog/2015/12/29/the-syncserver-permanent-access-to-your-app-data/)  
* [Blitz to get SMSyncServer Ready for Open-Source](http://www.spasticmuffin.biz/blog/2016/01/21/blitz-to-get-smsyncserver-ready-for-open-source/)
* [Design Issue: Changing Cloud Storage Accounts With The SMSyncServer](http://www.spasticmuffin.biz/blog/2016/04/02/design-issue-changing-cloud-storage-accounts-with-the-smsyncserver/)
* [The Many Senses of Recovery in SMSyncServer](http://www.spasticmuffin.biz/blog/2016/04/26/the-many-senses-of-recovery-in-smsyncserver/)
* [Re-Architecting the SMSyncServer File System](http://www.spasticmuffin.biz/blog/2016/05/09/re-architecting-the-smsyncserver-file-system/)
* [Conflict Management in the SMSyncServer](http://www.spasticmuffin.biz/blog/2016/05/11/conflict-management-in-the-smsyncserver/)
* [To Lock or not to Lock in the SMSyncServer](http://www.spasticmuffin.biz/blog/2016/09/03/to-lock-or-not-to-lock-in-the-smsyncserver/)

Contact: <chris@SpasticMuffin.biz> (primary developer)

# Development Status

* The SMSyncServer project is in "beta" and supports uploading, upload-deletion, downloading, download-deletion, and conflict management.
* An iOS client has been implemented (written in Swift; [requires iOS7 or later](https://developer.apple.com/swift/blog/?id=2); [see also this SO post](http://stackoverflow.com/questions/24001778/do-swift-based-applications-work-on-os-x-10-9-ios-7-and-lower)).
* Google Drive is supported in terms of cloud storage systems.
* Facebook credentials are supported in terms of sharing data with other users. Access to your data can be partial (e.g., read-only).
* No server side support yet for multiple concurrent server instances ([due to file system assumptions](http://www.spasticmuffin.biz/blog/2016/05/09/re-architecting-the-smsyncserver-file-system/)).
* 26,582 lines of program code and documentation, across client interface, client examples, tests, and server.
* 147 XCTests-- single device tests.
* 7 custom two device tests
* [TODO development list](./TODO.md)

# Installation
## 1) Create Google Developer Credentials

* To enable access to user Google Drive accounts, you must create Google Developer credentials for your iOS app using the SMSyncServer Framework and the SMSyncServer Node.js server. These credentials need to be installed in either the iOSTests or SharedNotes app or in your app making use of the iOSFramework. See
<https://developers.google.com/identity/sign-in/ios/>. Make sure you enable the Google Drive API for your Google project.

## 2) MongoDb installation

* SMSyncServer makes use of MongoDb to store file meta data and locks. Current tests are using MongoDb locally on a Mac OS X system (version v3.0.7), and on [mLab](https://www.mlab.com). You can [find MongoDb here](https://www.mongodb.org).

## 3) Server installation

* Create your own `serverSecrets.json` file (i.e., `Server/Code/serverSecrets.json`). This file is not in the public repo because it has private info -- it is in the SMSyncServer .gitignore file. You must create your own. This file contains keys for cloud storage access and for MongoDb access. The field for `SharingServices` is optional but necessary if you want to share access to SMSyncServer using Facebook.
Its structure is as follows:

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
		},
		"SharingServices": {
			"Facebook": {
				"app_id": "<snip>",
				"application": "<snip>",
				"app_secret": "<snip>",
				"client_token": "<snip>"
			}
		}
	}
	
* Each entry in the `CloudStorageServices` dictionary must abide by the structure required for the particular cloud storage service. For Google Drive, see [Google Sign In](https://developers.google.com/identity/sign-in/ios/).

* Each entry in the `SharingServices` dictionary must abide by the structure required for the particular sharing service. For Facebook, you must enable an app with [https://developers.facebook.com](https://developers.facebook.com/docs/ios/getting-started). Note that you don't need to follow all of these steps, just (a) create a Facbook app corresponding to your iOS app, and (b) modify parts (if you are using the example iOSTests or SharedNotes app) or add parts (if you are making a new app) indicated to the `.plist` of the Xcode project. When creating the Facebook app, you must make sure to add your app as a Platform ([see this link](http://stackoverflow.com/questions/16345777/given-url-is-not-allowed-by-the-application-configuration)).

* If you are using Facebooks sharing, in order for your app to receive sharing invitations, you need to add the following URL Scheme to your apps .plist file:

	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>{Your-Apps-BundleId}.invitation</string>
			</array>
		</dict>
	</array>
	
* The SMSyncServer server is written in Node.js. Current tests are running using Node.js v6.1.0 on Mac OS X and on [IBM Bluemix](https://bluemix.net). You can find [Node.js here](https://nodejs.org/).

* A startup script to run the SMSyncServer Node.js on your local Mac OS X system is `Server/Code/Scripts/startServer.sh`.

* A startup script to run the SMSyncServer Node.js server on [IBM Bluemix](https://bluemix.net) is `Server/Code/startOnBluemix.sh`. This script assumes you already have created an account on Bluemix and installed the SMSyncServer git repo on Bluemix. For some tips on this, see [https://hub.jazz.net/tutorials/jazzeditor/](https://hub.jazz.net/tutorials/jazzeditor/) and [https://www.raymondcamden.com/2015/03/02/hosting-node-js-apps-on-bluemix/](https://www.raymondcamden.com/2015/03/02/hosting-node-js-apps-on-bluemix/).

## 4) Using the iOSTests Example App with the iOSFramework iOS Framework

* One way to get familiar with the client (iOS app) side of the SMSyncServer system is to use the provided sample app. This is contained in the iOSTests folder. See also the [SharedNotes app](#shared-notes-demo-app). 

* Next, you need to replace the `GoogleService-Info.plist` symbolic link with your actual .plist file and edit the URL Scheme's in this Xcode project to match your Google credentials. See:
<https://developers.google.com/identity/sign-in/ios/>.

* You need to replace the `SMSyncServer-client.plist` symbolic link with your actual .plist file. The value of the GoogleServerClientID key is from your Google credentials. The CloudFolderPath key should be the name of the directory (no slashes-- we're not supporting subdirectories yet) where your SMSyncServer files will be stored in Google Drive. ServerURL is the URL of your SMSyncServer Node.js server, without a trailing "/". Here's it's format:

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

SMSyncServer uses [Cocoapods](https://cocoapods.org) to manage libraries for iOS. You must install [Cocoapods](https://cocoapods.org), and then run `pod install`. Once you do that, you should be ready to 

* You should now be ready to build the `Tests.xcworkspace` project and install to your device.

## 5) Adding the iOSFramework into your own Xcode project 

* You must call the iOS client (`SMSyncServer.iOSFramework` Cocoapod) from Swift, not Objective-C, because the iOS client API uses some Swift features that are not compatible with Objective-C (e.g., tuples, enums with associated values, and String enum's).
 
* As indicated above, SMSyncServer uses [Cocoapods](https://cocoapods.org) to manage libraries for iOS. You will need a `Podfile` in your project. For examples, see the Podfile in the iOSTests or the SharedNotes app.
 
* You need most of the code in your App Delegate from the example AppDelegate.swift file (see iOSTests and SharedNotes app) -- all of it except for that using Core Data. See the method `didFinishLaunchingWithOptions` and the method:

		func application(application: UIApplication,
			openURL url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
		}

* You need to create your own `SMSyncServer-client.plist` file. See above.

* Since you are already using Cocoapods for SMSyncServer, use it also to link the [Google SignIn Framework](https://developers.google.com/identity/sign-in/ios/) into your app. As indicated in these directions, you will need to create or use a configuration file (`GoogleService-Info.plist`). Your `client_id` and `client_secret` will need to be placed into your `serverSecrets.json` server file. See above.

* You might get the error "App Transport Security has blocked a cleartext HTTP (http://) resource load since it is insecure. Temporary exceptions can be configured via your app's Info.plist file." when you try run your app. For testing, you may want to use HTTP instead of HTTPS to access your SMSyncServer server. To do this, you can add the following to your app's Info.plist:

		<key>NSAppTransportSecurity</key>
		<dict>
			<key>NSAllowsArbitraryLoads</key>
			<true/>
		</dict>

* When you get to the point you see "Error signing in: Error Domain=com.google.GIDSignIn Code=-4" on the console log, you know you are making progress! Your next steps should include allowing the user to sign-in to their cloud storage account, and making sure you have the [URL Schemes required by Google SignIn](https://developers.google.com/identity/sign-in/ios/start-integrating#add-config).

* You will also need to setup a delegate for the SMSyncServer session shared instance.

# SharedNotes Demo App

In `iOS/SharedNotes` there is a demo app, which enables multiple devices to access the same collection of text notes and images across iOS devices. Again, you'll need to use Cocoapods, doing: `pod install`. Open the project `SharedNotes.xcworkspace` in Xcode.

[YouTube Demo of SharedNotes app](https://www.youtube.com/watch?v=9AVZa_pNvdo).

# Usage Examples
* The most comprehensive set of usage examples are in the XCTests in the sample iOSTests app (though some of these make use of internal methods using `@testable`).  See also the [SharedNotes demo app](#shared-notes-demo-app). 

* In the following an `immutable` file is one assumed to not change while upload is occurring. A `temporary` file is one that will be deleted by the SMSyncServer framework after upload. Some of these examples are extracted from README_Examples.swift in the XCTests for the Tests app.

* The `SMSyncServer.session.delegate` provides information about the completion of server operations, errors etc.

* Files are referenced by NSUUID's. Typically this occurs via `SMSyncAttributes` objects. Example:

	`SMSyncAttributes(withUUID: NSUUID(UUIDString: fileUUID)!, mimeType: "text/plain", andRemoteFileName: cloudStorageFileName)`

## 1) Uploading: Immutable Files

	let url = SMRelativeLocalURL(withRelativePath: "READMEUploadImmutableFile", toBaseURLType: .DocumentsDirectory)!
	
	// Just to put some content in the file. This content would, of course, depend on your app.
	let exampleFileContents = "Hello World!"
	try! exampleFileContents.writeToURL(url, atomically: true, encoding: NSUTF8StringEncoding)
	
	 // you would normally store this persistently, e.g., in CoreData. The UUID lets you reference the particular file, later, to the SMSyncServer framework.
	let uuid = NSUUID()
	
	let attr = SMSyncAttributes(withUUID: uuid, mimeType: "text/plain", andRemoteFileName: uuid.UUIDString)
	
	do {
		try SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: attr)
	} catch (let error) {
		print("Yikes: There was an error with uploadImmutableFile: \(error)")
	}
	
	// You could call uploadImmutableFile (or the other upload or deletion methods) any number of times, to queue up a group of files for upload.
	
	// The commit call actually starts the upload process.
	do {
		try SMSyncServer.session.commit()
	} catch (let error) {
		print("Yikes: There was an error with commit: \(error)")
	}

## 2) Uploading: Temporary Files

	let url = SMRelativeLocalURL(withRelativePath: "READMEUploadTemporaryFile", toBaseURLType: .DocumentsDirectory)!
	
	// Just to put some content in the file. This content would, of course, depend on your app.
	let exampleFileContents = "Hello World!"
	try! exampleFileContents.writeToURL(url, atomically: true, encoding: NSUTF8StringEncoding)
	
	 // you would normally store this persistently, e.g., in CoreData. The UUID lets you reference the particular file, later, to the SMSyncServer framework.
	let uuid = NSUUID()
	
	let attr = SMSyncAttributes(withUUID: uuid, mimeType: "text/plain", andRemoteFileName: uuid.UUIDString)
	
	do {
		try SMSyncServer.session.uploadTemporaryFile(url, withFileAttributes: attr)
	} catch (let error) {
		print("Yikes: There was an error with uploadTemporaryFile: \(error)")
	}
	
	// You could call uploadTemporaryFile (or the other upload or deletion methods) any number of times, to queue up a group of files for upload.
	
	// The commit call actually starts the upload process.
	do {
		try SMSyncServer.session.commit()
	} catch (let error) {
		print("Yikes: There was an error with commit: \(error)")
	}

## 3) Uploading: NSData

	// Just example content. This content would, of course, depend on your app.
	let exampleContents = "Hello World!"
	let data = exampleContents.dataUsingEncoding(NSUTF8StringEncoding)!
	
	 // you would normally store this persistently, e.g., in CoreData. The UUID lets you reference the particular data object, later, to the SMSyncServer framework.
	let uuid = NSUUID()
	
	let attr = SMSyncAttributes(withUUID: uuid, mimeType: "text/plain", andRemoteFileName: uuid.UUIDString)
	
	do {
		try SMSyncServer.session.uploadData(data, withDataAttributes: attr)
	} catch (let error) {
		print("Yikes: There was an error with uploadData: \(error)")
	}
	
	// You could call uploadData (or the other upload or deletion methods) any number of times, to queue up a group of files/data for upload.
	
	// The commit call actually starts the upload process.
	do {
		try SMSyncServer.session.commit()
	} catch (let error) {
		print("Yikes: There was an error with commit: \(error)")
	}
	
## 4) App specific metadata

	// SMSyncAttributes has an app-dependent meta data property that is a dictionary:
	public typealias SMAppMetaData = [String:AnyObject]
    public var appMetaData:SMAppMetaData?
    
    // Any time you upload a file/data object you can change this meta data, and when when synced with other devices, those other devices will receive this meta data for the file/data object.

## 5) Deletion

// This allows you to mark a file as deleted locally, and also mark it as deleted on the server. Other devices, on a download, will have the delegate method `syncServerClientShouldDeleteFiles` triggered (see below).

	// File referenced by uuid is assumed to exist in cloud storage
	let uuid = ...
	
	do {
		try SMSyncServer.session.deleteFile(uuid)
	} catch (let error) {
		print("Yikes: There was an error with deleteFile: \(error)")
	}

	do {
		try SMSyncServer.session.commit()
	} catch (let error) {
		print("Yikes: There was an error with commit: \(error)")
	}	
        
## 6) Download

// Downloads are caused by other devices uploading files, and these are initiated by the SMSyncServer and reported by the delegate method `syncServerShouldSaveDownloads` (see below). If needed, you can programmatically make a sync request which will do any currently needed downloads:

	SMSyncServer.session.sync()
	
## 7) Sharing data with Facebook users

// If you want to share your data stored using SMSyncServer with others, you either give them your Google Drive credentials (not recommended), or invite them to share using their Facebook account. To do this, you must create a sharing invitation.

## 8) SMSyncServer.session.delegate

	// These delegate methods are called on the main thread.
	public protocol SMSyncServerDelegate : class {
		// "class" to make the delegate weak.

		// For all four of the following delegate callbacks, it is up to the callee to check to determine if any modification conflict is occuring for a particular deleted file. i.e., if the client is modifying any of the files referenced.
	
		// Called at the end of all downloads, on non-error conditions. Only called when there was at least one download.
		// The callee owns the files referenced by the NSURL's after this call completes. These files are temporary in the sense that they will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location. See [1] for a design note about this delegate method. This is received/called in an atomic manner: This reflects the current state of files on the server.
		// The recommended action is for the client to replace their existing data with that from the files.
		// The callee must call the acknowledgement callback when it has finished dealing with (e.g., persisting) the list of downloaded files.
		// For any given download only one of the following two delegate methods will be called. I.e., either there is a conflict or is not a conflict for a given download.
		func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement: () -> ())
	
		// The client has to decide how to resolve the file-download conflicts. The resolveConflict method of each SMSyncServerConflict must be called. The above statements apply for the NSURL's.
		func syncServerShouldResolveDownloadConflicts(conflicts: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)])
	
		// Called when deletion indications have been received from the server. I.e., these files have been deleted on the server. This is received/called in an atomic manner: This reflects a snapshot state of files on the server. The recommended action is for the client to delete the files reference by the SMSyncAttributes's (i.e., the UUID's).
		// The callee must call the acknowledgement callback when it has finished dealing with (e.g., carrying out deletions for) the list of deleted files.
		func syncServerShouldDoDeletions(downloadDeletions downloadDeletions:[SMSyncAttributes], acknowledgement:()->())

		// The client has to decide how to resolve the download-deletion conflicts. The resolveConflict method of each SMSyncServerConflict must be called.
		// Conflicts will not include UploadDeletion.
		func syncServerShouldResolveDeletionConflicts(conflicts:[(downloadDeletion: SMSyncAttributes, uploadConflict: SMSyncServerConflict)])
	
		// Reports mode changes including errors. Can be useful for presenting a graphical user-interface which indicates ongoing server/networking operations. E.g., so that the user doesn't close or otherwise the dismiss a client app until server operations have completed.
		func syncServerModeChange(newMode:SMSyncServerMode)
	
		// Reports events. Useful for testing and debugging.
		func syncServerEventOccurred(event:SMSyncServerEvent)
	}



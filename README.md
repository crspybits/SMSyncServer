Contents:  
[Introduction](#markdown-header-introduction)  
[Development Status](#markdown-header-development-status)  
[Installation](#markdown-header-installation)  
[Usage examples](#markdown-header-usage-examples)  

# Introduction
SMSyncServer has the following goals:  
(1) giving end-users permanent access to their mobile app data,  
(2) synchronizing mobile app data across end-user devices,  
(3) reducing data storage costs for app developers/publishers, and  
(4) allowing sharing of data with other users. 

See [The SyncServer: Permanent Access to Your App Data](http://www.spasticmuffin.biz/blog/2015/12/29/the-syncserver-permanent-access-to-your-app-data/)

# Development Status

* The SMSyncServer project is in "alpha" and supports uploading and deletion only. Support for downloading support is in progress.

# Installation
## 1) Create Google Developer Credentials

* Create Google Developer credentials for your iOS app using the SMSyncServer Framework and the SMSyncServer Node.js server. These credentials need to be installed in either the iOSTets app or in your app making use of the iOSFramework. See
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

* Before running the iOSTests example app, you need to make a few changes to the app to make use of your Google Developer credentials. To do make these changes, first launch the iOSTests app by opening Tests.workspace in Xcode. 

* Next, you need to replace the GoogleService-Info.plist file and editing the URL Scheme's in in this Xcode project. See:
<https://developers.google.com/identity/sign-in/ios/>

* Make sure to change the Google **serverClientID** in the AppDelegate of the Xcode project. You can also search the code for the string: 

    CHANGE THIS IN YOUR CODE
    
* Additionally, you need to change the **serverURL**, also in the AppDelegate. This is the URL for your Node.js server (see below). Again, you can search for

    CHANGE THIS IN YOUR CODE

* You should now be ready to build the Tests.workspace onto your device.

## 5) Adding the iOSFramework into your own Xcode project

* You can also install the SMSyncServer iOS Framework into your own Xcode project.  

* A useful way to get started with this is to look at the AppDelegate of the sample app, and to look at the "Cloud Storage User Credentials" Xcode group/folder in that sample app. 

* Link the [Google Sign Framework](https://developers.google.com/identity/sign-in/ios/) into your app. It seems easiest to do this using the Cocoapod. 

* With your own Xcode project open in Xcode and with a Mac OS Finder folder open so you can see iOSFramework files, you need to drag `SMSyncServer.xcodeproj` from the iOSFramework folder into your Xcode project.

* Then, entirely within your Xcode project, drag SMSyncServer.framework to Embedded Binaries in the General tab.

* Also entirely within your Xcode project, locate SMCoreLib.framework and drag this to Embedded Binaries in the General tab (while you don't have to explicitly make use of SMCoreLib in your code, it is used by the SMSyncServer Framework, and this step seems  necessary to build).

# Usage Examples
* The most comprehensive set of usage examples are in the XCTests in the sample iOSTests app. The following examples are extracted from those XCTests.

* In the following an `immutable` file is one assumed to not change while upload is occurring. A `temporary` file is one that will be deleted after upload.

* An optional `SMSyncServer.session.delegate` can provide information about the completion of server operations, errors etc.

## 1) Uploading: Immutable Files

        let fileName1 = "TwoFileUpload1"
    
        let (file1, fileSizeBytes1) = self.createFile(withName: fileName1)
        let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName1)
        
        SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
        
        let fileName2 = "TwoFileUpload2"
        let (file2, fileSizeBytes2) = self.createFile(withName: fileName2)
        let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file2.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName2)
        
        SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)
        
        SMSyncServer.session.commit()
    
## 2) Uploading: Temporary Files

    let fileName = "SingleTemporaryFileUpload"
    let (file, fileSizeBytes) = self.createFile(withName: fileName)
    let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
    
    SMSyncServer.session.uploadTemporaryFile(file.url(), withFileAttributes: fileAttributes)
    
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
    
## 5) Optional SMSyncServer.session.delegate

    public protocol SMSyncServerDelegate : class {
    
        // numberOperations includes upload and deletion operations.
        func syncServerCommitComplete(numberOperations numberOperations:Int?)
        
        // Called after a single file/item has been uploaded to the SyncServer.
        func syncServerSingleUploadComplete(uuid uuid:NSUUID)
    
        // Called after deletion operations have been sent to the SyncServer. All pending deletion operations are sent as a group.
        func syncServerDeletionsSent(uuids:[NSUUID])
    
        // This reports recovery progress from recoverable errors. Mostly useful for testing and debugging.
        func syncServerRecovery(progress:SMSyncServerRecovery)
    
        /* This error can occur in one of two types of circumstances:
        1) There was a client API error in which the user of the SMSyncServer (e.g., caller of this interface) made an error (e.g., using the same cloud file name with two different UUID's).
        2) There was an error that, after internal SMSyncServer recovery attempts, could not be dealt with.
        */
        func syncServerError(error:NSError)
    }



Contents:  
[Introduction](#markdown-header-introduction)  
[Installation](#markdown-header-installation)  
[Usage examples](#markdown-header-usage-examples)  

# Introduction

SMSyncServer has the following goals:  
(1) giving end-users permanent access to their mobile app data,  
(2) synchronizing mobile app data across end-user devices,  
(3) reducing data storage costs for app developers/publishers, and  
(4) allowing sharing of data with other users. 

See [The SyncServer: Permanent Access to Your App Data](http://www.spasticmuffin.biz/blog/2015/12/29/the-syncserver-permanent-access-to-your-app-data/)

# Installation

**1) Create Google Developer Credentials.**  
You have to create these credentials for your iOS app and the Node.js server. See
<https://developers.google.com/identity/sign-in/ios/>

***

**2) Do *either* steps 3) *or* 4) below.**  
Depending on whether you want to try the sample code (iOSTests) or just go for the gusto and use the SMSyncServer framework.

***

**3) Using the iOS Testing App (iOSTests) with the SMSyncServer iOS Framework.**

3.1) Install [iOSTests](https://bitbucket.org/SMSyncServer/iostests) and [iOSFramework](https://bitbucket.org/SMSyncServer/iosframework) into the same directory, i.e., have them at the same level. Like this:

    YourFolder/  
        iOSTests  
        iOSFramework  

3.2) You need to change the iOSTests Tests.workspace Xcode project to use your Google credentials. This involves replacing the GoogleService-Info.plist file and editing the URL Scheme's. See:
<https://developers.google.com/identity/sign-in/ios/>

3.3) Make sure to change the Google **serverClientID** in the iOSTests Xcode Tests.workspace (search for the string: *CHANGE THIS IN YOUR CODE*).
**4) Adding the SMSyncServer Framework into your own Xcode project**

3.4) Change the server URL to reflect the URL of your server 

3.5) Build the Tests.workspace project onto your device.

***

**4) Using the SMSyncServer framework with your Xcode project**

i) Dragged SMSyncServer.xcodeproj into app Xcode project
ii) Dragged SMSyncServer.framework to Embedded Binaries in General
iii) Dragged SMLib.framework to Embedded Binaries (I don’t this is optional; seems  necessary to build).

// Is this needed?
iv) Under Build Settings, search for Framework Search Paths. And add in:
${TARGET_BUILD_DIR}/SMSyncServer.framework
${TARGET_BUILD_DIR}/Google.framework

v) You need to add Google Sign into your app (I used Cocoapods in my sample app):
https://developers.google.com/identity/sign-in/ios/

***
   
**5) Server installation**

Create your own client_secret.json file (Node.js server/Code/client_secret.json). It’s currently a symbolic link and must be replaced. This info is from Google Sign In. Its structure is:

{
  "installed": {
    "client_id": "<snip>",
    "client_secret": "<snip>",
    "redirect_uris": ["<snip>"],
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://accounts.google.com/o/oauth2/token"
  }
}

# Usage examples
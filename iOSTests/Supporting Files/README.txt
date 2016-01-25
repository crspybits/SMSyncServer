SMSyncServer-client.plist is a symbolic link to a file with format: 

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

The GoogleService-Info.plist is a symbolic link to a file downloaded from the Google Developers website. See https://developers.google.com/identity/sign-in/ios/
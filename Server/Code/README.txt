1) The "Server.xcodeproj" Xcode project is being used for organizing and editing the code-- it is *not* being used for any build or upload purposes.

2) The client_secret.json file is a symbolic link, and is *not* provided. You must provide your own. It looks like this:

{
  "installed": {
    "client_id": "<snip>",
    "client_secret": "<snip>",
    "redirect_uris": ["<snip>"],
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://accounts.google.com/o/oauth2/token"
  }
}
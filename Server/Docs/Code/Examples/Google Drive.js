var http = require("http");
var url = require('url');
var google = require('googleapis');
var googleAuth = require('google-auth-library');
var fs = require('fs');

/*
http.createServer(function (request, response) {

   // Respond with HTTP header 
   // HTTP Status: 200 : OK
   // Content Type: text/plain
   response.writeHead(200, {'Content-Type': 'text/plain'});
   
   var result = {};
   result["status"] = "success";
   response.end(JSON.stringify(result));
   
   // See docs https://nodejs.org/api/http.html#http_http_incomingmessage
   console.log('Received request: ');
   console.log(request.url);
   var jsonQuery = url.parse(request.url, true)['query'];
   console.log(jsonQuery);
   
}).listen(8081);

console.log('Server running at http://127.0.0.1:8081/');
*/

// Load client secrets from a local file.
fs.readFile('client_secret.json', function processClientSecrets(err, content) {
	if (err) {
		console.log('Error loading client secret file: ' + err);
		return;
	}
	
	// Authorize a client with the loaded credentials, then call the
	// Drive API.
	authorize(JSON.parse(content), listFiles);
});

/**
 * Create an OAuth2 client with the given credentials, and then execute the
 * given callback function.
 *
 * @param {Object} credentials The authorization client credentials.
 * @param {function} callback The callback to call with the authorized client.
 */
function authorize(credentials, callback) {
  	var clientSecret = credentials.installed.client_secret;
  	var clientId = credentials.installed.client_id;
  	var redirectUrl = credentials.installed.redirect_uris[0];
  	var auth = new googleAuth();
  	var oauth2Client = new auth.OAuth2(clientId, clientSecret, redirectUrl);

	// Just for testing.
	var refreshToken = '1/91slwP_aZyRfq_eewOJXOgDn_T6TodsgjhoBCD842oxIgOrJDtdun6zK6XiATCKT';
	
	oauth2Client.setCredentials({
  		refresh_token: refreshToken
	});
	
	oauth2Client.refreshAccessToken(function(err, tokens) {
		console.log('refreshAccessToken result: ' + err);
  		callback(oauth2Client);
	});
}

/**
 * Lists the names and IDs of up to 10 files.
 *
 * @param {google.auth.OAuth2} auth An authorized OAuth2 client.
 */
function listFiles(auth) {
  var service = google.drive('v2');
  service.files.list({
    auth: auth,
    maxResults: 10,
  }, function(err, response) {
    if (err) {
      console.log('The API returned an error: ' + err);
      return;
    }
    var files = response.items;
    if (files.length == 0) {
      console.log('No files found.');
    } else {
      console.log('Files:');
      for (var i = 0; i < files.length; i++) {
        var file = files[i];
        console.log('%s (%s)', file.title, file.id);
      }
    }
  });
}

/* 
From: https://developers.google.com/identity/protocols/CrossClientAuth

"When developers build software, it routinely includes modules that run on a web server, other modules that run in the browser, and others that run as native mobile apps. Both developers and the people who use their software typically think of all these modules as part of a single app." 

"Since the refresh token does not expire, it is the responsibility of the web component to store the refresh token in a secure and long-lived manner."

"Use HTTP POST requests for all requests to the server, and include an ID token in the body of each POST request. The ID token, which you acquire as described in the preceding section, informs the back-end of the user's identity"
*/

/* From: https://developers.google.com/identity/protocols/OAuth2

"Note: Save refresh tokens in secure long-term storage and continue to use them as long as they remain valid. Limits apply to the number of refresh tokens that are issued per client-user combination, and per user across all clients, and these limits are different. If your application requests enough refresh tokens to go over one of the limits, older refresh tokens stop working."
*/

/* Web vs. installed applications
https://developers.google.com/identity/protocols/OAuth2
*/

/* Example Node.js code to use a refresh token to access Google Drive API
https://developers.google.com/drive/web/quickstart/nodejs
*/

/* client_secrets.json file
https://developers.google.com/api-client-library/python/guide/aaa_client_secrets 
*/

/* Structure of .credentials property of OAuth2Client object:

https://www.npmjs.com/package/googleapis

oauth2Client.setCredentials({
  access_token: 'ACCESS TOKEN HERE',
  refresh_token: 'REFRESH TOKEN HERE'
});

*/

/* Errors:

1) Error: invalid_client
	Solution: I went into the Google API console and made a specific Web set of credentials for the server.
	
2) Error: unauthorized_client
	I tried adding in the scope I was using to the iOS app, but that didn't work.
	It appears that you cannot refresh using a different client:
		http://stackoverflow.com/questions/13871982/unable-to-refresh-access-token-response-is-unauthorized-client
	So, it seems that my algorithm is wrong. I was assuming you could pass the refresh token from the iOS app
	to the server and do a refresh.
*/
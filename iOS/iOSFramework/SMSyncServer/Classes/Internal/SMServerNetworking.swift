//
//  SMServerNetworking.swift
//  NetDb
//
//  Created by Christopher Prince on 11/29/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

// Interface to AFNetworking

// 11/29/15; I switched over to AFNetworking because with Alamofire uploading a file with parameters was too complicated.
// See http://stackoverflow.com/questions/26335630/bridging-issue-while-using-afnetworking-with-pods-in-a-swift-project for integrating AFNetworking and Swift.

import Foundation
import SMCoreLib
import AFNetworking

internal class SMServerNetworking {
    private let manager: AFHTTPSessionManager!

    internal static let session = SMServerNetworking()
    
    private init() {
        self.manager = AFHTTPSessionManager()
            // http://stackoverflow.com/questions/26604911/afnetworking-2-0-parameter-encoding
        self.manager.responseSerializer = AFJSONResponseSerializer()
    
        // This does appear necessary for requests going out to server to receive properly encoded JSON parameters on the server.
        self.manager.requestSerializer = AFJSONRequestSerializer()

        self.manager.requestSerializer.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    
    private var uploadTask:NSURLSessionUploadTask?
    //private var downloadTask:NSURLSessionDownloadTask?
    //private var dataTask:NSURLSessionDataTask?
    
    internal func appLaunchSetup() {
        // To get "spinner" in status bar when ever we have network activity.
        // See http://cocoadocs.org/docsets/AFNetworking/2.0.0/Classes/AFNetworkActivityIndicatorManager.html
        AFNetworkActivityIndicatorManager.sharedManager().enabled = true
    }
    
    // In the completion hanlder, if error != nil, there will be a non-nil serverResponse.
    internal func sendServerRequestTo(toURL serverURL: NSURL, withParameters parameters:[String:AnyObject],
        completion:((serverResponse:[String:AnyObject]?, error:NSError?)->())?) {
        /*  
        1) The http address here must *not* be localhost as we're addressing my Mac Laptop, where the Node.js server is running, and this app is running on my iPhone, a separate device.
        2) Using responseJSON is causing an error. i.e., response.result.error is non-nil. See http://stackoverflow.com/questions/32355850/alamofire-invalid-value-around-character-0
        *** BUT this was because the server was returning "Hello World", a non-json string!
        3) Have used https://forums.developer.apple.com/thread/3544 so I don't need SSL/https for now.
        4) The "encoding: .JSON" parameter seems needed so that I get nested dictionaries in the parameters (i.e., dictionaries as the values of keys) correctly coming across as json structures on the server. See also http://stackoverflow.com/questions/30394112/how-do-i-use-json-arrays-with-alamofire-parameters (This was with Alamofire)
        */

        Log.special("serverURL: \(serverURL)")
        
        var sendParameters = parameters
#if DEBUG
        if (SMTest.session.serverDebugTest != nil) {
            sendParameters[SMServerConstants.debugTestCaseKey] = SMTest.session.serverDebugTest
        }
#endif

        if !Network.connected() {
            completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcNetworkFailure], error: Error.Create("Network not connected."))
            return
        }
        
        self.manager.POST(serverURL.absoluteString, parameters: sendParameters, progress: nil,
            success: { (request:NSURLSessionDataTask, response:AnyObject?) in
                if let responseDict = response as? [String:AnyObject] {
                    Log.msg("AFNetworking Success: \(response)")
                    completion?(serverResponse: responseDict, error: nil)
                }
                else {
                    completion?(serverResponse: nil, error: Error.Create("No dictionary given in response"))
                }
            },
            failure: { (request:NSURLSessionDataTask?, error:NSError) in
                print("**** AFNetworking FAILURE: \(error)")
                completion?(serverResponse: nil, error: error)
            })

        /*
        self.manager.POST(serverURL.absoluteString, parameters: sendParameters,
            success: {(request:NSURLSessionDataTask, response:AnyObject) in
                if let responseDict = response as? [String:AnyObject] {
                    Log.msg("AFNetworking Success: \(response)")
                    completion?(serverResponse: responseDict, error: nil)
                }
                else {
                    completion?(serverResponse: nil, error: Error.Create("No dictionary given in response"))
                }
            }, failure: { (request: AFHTTPRequestOperation?, error:NSError)  in
                print("**** AFNetworking FAILURE: \(error)")
                completion?(serverResponse: nil, error: error)
            })
        */
        /*
        Alamofire.request(.POST, serverURL, parameters: dictionary, encoding: .JSON)
            .responseJSON { response in
                if nil == response.result.error {
                    print(response.request)  // original URL request
                    print(response.response) // URL response
                    print(response.data)     // server data
                    print(response.result)   // result of response serialization
                    print("response.result.error: \(response.result.error)")
                    print("Status code: \(response.response!.statusCode)")

                    if let JSONDict = response.result.value as? [String : AnyObject] {
                        print("JSON: \(JSONDict)")
                        completion?(serverResponse: JSONDict, error: nil)
                    }
                    else {
                        completion?(serverResponse: nil, error: Error.Create("No JSON in response"))
                    }
                }
                else {
                    print("Error connecting to the server!")
                    completion?(serverResponse: nil, error: response.result.error)
                }
            }
            */
    }
    
    // withParameters must have a non-nil key SMServerConstants.fileMIMEtypeKey
    internal func uploadFileTo(serverURL: NSURL, fileToUpload:NSURL, withParameters parameters:[String:AnyObject]?, completion:((serverResponse:[String:AnyObject]?, error:NSError?)->())?) {
        
        Log.special("serverURL: \(serverURL)")
        Log.special("fileToUpload: \(fileToUpload)")
        
        var sendParameters:[String:AnyObject]? = parameters
#if DEBUG
        if (SMTest.session.serverDebugTest != nil) {
            if parameters == nil {
                sendParameters = [String:AnyObject]()
            }
            
            sendParameters![SMServerConstants.debugTestCaseKey] = SMTest.session.serverDebugTest
        }
#endif

        if !Network.connected() {
            completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcNetworkFailure], error: Error.Create("Network not connected."))
            return
        }
        
        let mimeType = sendParameters![SMServerConstants.fileMIMEtypeKey]
        Assert.If(mimeType == nil, thenPrintThisString: "You must give a mime type!")
        
        var error:NSError? = nil

        // For the reason for this JSON serialization, see https://stackoverflow.com/questions/37449472/afnetworking-v3-1-0-multipartformrequestwithmethod-uploads-json-numeric-values-w/
        var jsonData:NSData?
        
        do {
            try jsonData = NSJSONSerialization.dataWithJSONObject(sendParameters!, options: NSJSONWritingOptions(rawValue: 0))
        } catch (let error) {
            Assert.badMojo(alwaysPrintThisString: "Yikes: Error serializing to JSON data: \(error)")
        }
        
        // The server needs to pull SMServerConstants.serverParametersForFileUpload out of the request body, then convert the value to JSON
        let serverParameters = [SMServerConstants.serverParametersForFileUpload : jsonData!]
        
        // http://stackoverflow.com/questions/34517582/how-can-i-prevent-modifications-of-a-png-file-uploaded-using-afnetworking-to-a-n
        // I have now set the COMPRESS_PNG_FILES Build Setting to NO to deal with this.
        
        let request = AFHTTPRequestSerializer().multipartFormRequestWithMethod("POST", URLString: serverURL.absoluteString, parameters: serverParameters, constructingBodyWithBlock: { (formData: AFMultipartFormData) in
                // NOTE!!! the name: given here *must* match up with that used on the server in the "multer" single parameter.
                // Was getting an odd try/catch error here, so this is the reason for "try!"; see https://github.com/AFNetworking/AFNetworking/issues/3005
                // 12/12/15; I think this issue was because I wasn't doing the do/try/catch, however.
                do {
                    //try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName, fileName: "Kitty.png", mimeType: mimeType! as! String)
                    try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName)
                } catch let error {
                    let message = "Failed to appendPartWithFileURL: \(fileToUpload); error: \(error)!"
                    Log.error(message)
                    completion?(serverResponse: nil, error: Error.Create(message))
                }
            }, error: &error)
        
        if nil != error {
            completion?(serverResponse: nil, error: error)
            return
        }
        
        self.uploadTask = self.manager.uploadTaskWithStreamedRequest(request, progress: { (progress:NSProgress) in
            },
            completionHandler: { (request: NSURLResponse, responseObject: AnyObject?, error: NSError?) in
                if (error == nil) {
                    if let responseDict = responseObject as? [String:AnyObject] {
                        Log.msg("AFNetworking Success: \(responseObject)")
                        completion?(serverResponse: responseDict, error: nil)
                    }
                    else {
                        let error = Error.Create("No dictionary given in response")
                        Log.error("**** AFNetworking FAILURE: \(error)")
                        completion?(serverResponse: nil, error: error)
                    }
                }
                else {
                    Log.error("**** AFNetworking FAILURE: \(error)")
                    completion?(serverResponse: nil, error: error)
                }
            })
        
        if nil == self.uploadTask {
            completion?(serverResponse: nil, error: Error.Create("Could not start upload task"))
            return
        }
        
        self.uploadTask?.resume()
    }
    
    internal func downloadFileFrom(serverURL: NSURL, fileToDownload:NSURL, withParameters parameters:[String:AnyObject]?, completion:((serverResponse:[String:AnyObject]?, error:NSError?)->())?) {
        
        Log.special("serverURL: \(serverURL)")
        Log.special("fileToDownload: \(fileToDownload)")
        
        var sendParameters:[String:AnyObject]? = parameters
        
#if DEBUG
        if (SMTest.session.serverDebugTest != nil) {
            if parameters == nil {
                sendParameters = [String:AnyObject]()
            }
            
            sendParameters![SMServerConstants.debugTestCaseKey] = SMTest.session.serverDebugTest
        }
#endif

        if !Network.connected() {
            completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcNetworkFailure], error: Error.Create("Network not connected."))
            return
        }
        
        //self.download1(serverURL)
        //self.download2(serverURL)
        //self.download3(serverURL, parameters:sendParameters)
        
        let sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
        // TODO: When do we need a delegate/delegateQueue here?
        let session = NSURLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(URL: serverURL)
        request.HTTPMethod = "POST"
        
        if sendParameters != nil {
            var jsonData:NSData?
            
            do {
                try jsonData = NSJSONSerialization.dataWithJSONObject(sendParameters!, options: NSJSONWritingOptions(rawValue: 0))
            } catch (let error) {
                completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcInternalError], error: Error.Create("Could not serialize JSON parameters: \(error)"))
                return
            }
            
            request.HTTPBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("\(jsonData!.length)", forHTTPHeaderField: "Content-Length")
        }
        
        let task = session.downloadTaskWithRequest(request) { (urlOfDownload:NSURL?, response:NSURLResponse?, error:NSError?)  in
             if (error == nil) {
                // Success
                if let httpResponse = response as? NSHTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    if statusCode != 200 {
                        completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Status code= \(statusCode) was not 200!"))
                        return
                    }
                    
                    if urlOfDownload == nil {
                        completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Got nil downloaded file URL!"))
                        return
                    }
                    
                    Log.msg("urlOfDownload: \(urlOfDownload)")
                    
                    // I've not been able to figure out how to get a file downloaded along with parameters (e.g., return result from the server), so I'm using a custom HTTP header to get result parameters back from the server.
                    
                    Log.msg("httpResponse.allHeaderFields: \(httpResponse.allHeaderFields)")
                    let downloadParams = httpResponse.allHeaderFields[SMServerConstants.httpDownloadParamHeader]
                    Log.msg("downloadParams: \(downloadParams)")
                    
                    if let downloadParamsString = downloadParams as? String {
                        let downloadParamsDict = self.convertJSONStringToDictionary(downloadParamsString)

                        Log.msg("downloadParamsDict: \(downloadParamsDict)")
                        if downloadParamsDict == nil {
                            completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Did not get parameters from server!"))
                        }
                        else {
                            // We can still get to this point without a downloaded file. Oddly enough the urlOfDownload might not be nil, but we won't have a downloaded file. Our downloadParamsDict will indicate the error, and the caller will have to figure things out.
                            
                            // urlOfDownload is the temporary file location given by downloadTaskWithRequest. Not sure how long it persists. Move it to our own temporary location. We're more assured of that lasting.
                            
                            // Make sure destination file (fileToDownload) isn't there first. Get an error with moveItemAtURL if it is.
                            
                            let mgr = NSFileManager.defaultManager()
                            
                            // I don't really care about an error here, attempting to removeItemAtURL. i.e., it could be an error just because the file isn't there-- which would be the usual case.
                            do {
                                try mgr.removeItemAtURL(fileToDownload)
                            } catch (let err) {
                                Log.error("removeItemAtURL: \(err)")
                            }
                            
                            var error:NSError?
                            do {
                                try mgr.moveItemAtURL(urlOfDownload!, toURL: fileToDownload)
                            } catch (let err) {
                                let errorString = "moveItemAtURL: \(err)"
                                error = Error.Create(errorString)
                                Log.error(errorString)
                            }
                            
                            // serverResponse will be non-nil if we throw an errow in the file move, but the caller should check the error so, should be OK.
                            completion?(serverResponse: downloadParamsDict, error: error)
                        }
                    }
                    else {
                        completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Did not get downloadParamsString from server!"))
                    }
                }
                else {
                    // Could not get NSHTTPURLResponse
                    completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Did not get NSHTTPURLResponse from server!"))
                }
            }
            else {
                // Failure
                completion?(serverResponse: nil, error: error)
            }
        }
        
        task.resume()
    }

/*
    func download0() {
        //let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        //let manager = AFURLSessionManager(sessionConfiguration: configuration)
        var error:NSError? = nil

        // Not getting anything received on server.
        // let request = AFHTTPRequestSerializer().multipartFormRequestWithMethod("POST", URLString: serverURL.absoluteString, parameters: sendParameters, constructingBodyWithBlock: nil, error: &error)
        
        // Not getting anything received on server.
        // let request = AFHTTPRequestSerializer().requestWithMethod("POST", URLString: serverURL.absoluteString, parameters: parameters, error: &error)
        
        let request = NSMutableURLRequest(URL: serverURL)
        request.HTTPMethod = "POST"
        
        if nil != error {
            completion?(serverResponse: nil, error: error)
            return
        }

        // Doesn't show up on server.
        /*
        self.dataTask = self.manager.dataTaskWithRequest(request,
            uploadProgress: { (uploadProgress:NSProgress) -> Void in
                
            }, downloadProgress: { (downloadProgress:NSProgress) -> Void in
                
            }) { (response:NSURLResponse, responseObject:AnyObject?, error:NSError?) -> Void in
            }
        */

        self.downloadTask = self.manager.downloadTaskWithRequest(request,
            progress: { (progress:NSProgress) in
            
            }, destination: { (targetPath:NSURL, response:NSURLResponse) -> NSURL in
                // destination: A block object to be executed in order to determine the destination of the downloaded file. This block takes two arguments, the target path & the server response, and returns the desired file URL of the resulting download. The temporary file used during the download will be automatically deleted after being moved to the returned URL.
                Log.msg("destination: targetPath: \(targetPath)")
                Log.msg("destination: response: \(response)")
                return fileToDownload
            }, completionHandler: { (response:NSURLResponse, url:NSURL?, error:NSError?) in
                // completionHandler A block to be executed when a task finishes. This block has no return value and takes three arguments: the server response, the path of the downloaded file, and the error describing the network or parsing error that occurred, if any.
                Log.msg("response: \(response)")
                Log.msg("url: \(url)")
                completion?(serverResponse: nil, error: error)
            })
    }
*/

/*
    // This gets through to the server, but, of course, I'm not getting the credentials parameters.
    func download1(URL: NSURL) {
        let sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = "POST"
        
        let task = session.dataTaskWithRequest(request, completionHandler: { (data: NSData?, response: NSURLResponse?, error: NSError?) in
            if (error == nil) {
                // Success
                let statusCode = (response as! NSHTTPURLResponse).statusCode
                Log.msg("statusCode: \(statusCode)")
                Log.msg("response: \(response)")
                Log.msg("data: \(data)")
                // This is your file-variable:
                // data
            }
            else {
                // Failure
                Log.msg("Failure: \(error)")
            }
        })
        
        task.resume()
    }

    // This also gets through to the server, but, of course, I'm not getting the credentials parameters.
    func download2(URL: NSURL) {
        let sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = "POST"
        
        let task = session.downloadTaskWithRequest(request) { (urlOfDownload:NSURL?, response:NSURLResponse?, error:NSError?)  in
             if (error == nil) {
                // Success
                let statusCode = (response as! NSHTTPURLResponse).statusCode
                Log.msg("statusCode: \(statusCode)")
                Log.msg("response: \(response)")
                Log.msg("urlOfDownload: \(urlOfDownload)")
            }
            else {
                // Failure
                Log.msg("Failure: \(error)")
            }
        }
        
        task.resume()
    }
*/
    
    func download3(URL: NSURL, parameters:[String:AnyObject]?) {
        let sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = "POST"
        
        if parameters != nil {
            var jsonData:NSData?
            
            do {
                try jsonData = NSJSONSerialization.dataWithJSONObject(parameters!, options: NSJSONWritingOptions(rawValue: 0))
            } catch (let error) {
                Log.msg("error: \(error)")
                return
            }
            
            request.HTTPBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("\(jsonData!.length)", forHTTPHeaderField: "Content-Length")
        }
        
        let task = session.downloadTaskWithRequest(request) { (urlOfDownload:NSURL?, response:NSURLResponse?, error:NSError?)  in
             if (error == nil) {
                // Success
                let httpResponse = response as! NSHTTPURLResponse
                
                let statusCode = httpResponse.statusCode
                // statusCode should be 200-- check it.
                
                Log.msg("statusCode: \(statusCode)")
                Log.msg("urlOfDownload: \(urlOfDownload)")
                Log.msg("httpResponse.allHeaderFields: \(httpResponse.allHeaderFields)")
                let downloadParams = httpResponse.allHeaderFields[SMServerConstants.httpDownloadParamHeader]
                Log.msg("downloadParams: \(downloadParams)")
                Log.msg("downloadParams type: \(downloadParams.dynamicType)")
                if let downloadParamsString = downloadParams as? String {
                    let downloadParamsDict = self.convertJSONStringToDictionary(downloadParamsString)
                    Log.msg("downloadParamsDict: \(downloadParamsDict)")
                    if downloadParamsDict == nil {
                    }
                    else {
                    
                    }
                }
            }
            else {
                // Failure
                Log.msg("Failure: \(error)")
            }
        }
        
        task.resume()
    }
    
    // See http://stackoverflow.com/questions/30480672/how-to-convert-a-json-string-to-a-dictionary
    private func convertJSONStringToDictionary(text: String) -> [String:AnyObject]? {
        if let data = text.dataUsingEncoding(NSUTF8StringEncoding) {
            do {
                let json = try NSJSONSerialization.JSONObjectWithData(data, options: .MutableContainers) as? [String:AnyObject]
                return json
            } catch {
                Log.error("Something went wrong")
            }
        }
        return nil
    }
    
/*
NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];

NSURL *URL = [NSURL URLWithString:@"http://example.com/download.zip"];
NSURLRequest *request = [NSURLRequest requestWithURL:URL];

NSURLSessionDownloadTask *downloadTask = [manager downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
    NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    return [documentsDirectoryURL URLByAppendingPathComponent:[response suggestedFilename]];
} completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
    NSLog(@"File downloaded to: %@", filePath);
}];
[downloadTask resume];
*/
    
    
}

extension SMServerNetworking /* Extras */ {
    // Returns a duration in seconds.
    private class func exponentialFallbackDuration(forAttempt numberTimesTried:Int) -> Float {
        let duration:Float = pow(Float(numberTimesTried), 2.0)
        Log.msg("Will try operation again in \(duration) seconds")
        return duration
    }

    // I'm making this available from SMServerNetworking because the concept of exponential fallback is at the networking level.
    class func exponentialFallback(forAttempt numberTimesTried:Int, completion:()->()) {
        let duration = SMServerNetworking.exponentialFallbackDuration(forAttempt: numberTimesTried)

        TimedCallback.withDuration(duration) {
            completion()
        }
    }
}
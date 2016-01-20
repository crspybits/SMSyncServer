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

public class SMServerNetworking {
    private let manager: AFHTTPSessionManager!

    public static let session = SMServerNetworking()
    
    private init() {
        self.manager = AFHTTPSessionManager()
            // http://stackoverflow.com/questions/26604911/afnetworking-2-0-parameter-encoding
        self.manager.responseSerializer = AFJSONResponseSerializer()
    
        // This does appear necessary for requests going out to server to receive properly encoded JSON parameters on the server.
        self.manager.requestSerializer = AFJSONRequestSerializer()

        self.manager.requestSerializer.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    
    private var uploadTask:NSURLSessionUploadTask?
    
    public func appLaunchSetup() {
        // To get "spinner" in status bar when ever we have network activity.
        // See http://cocoadocs.org/docsets/AFNetworking/2.0.0/Classes/AFNetworkActivityIndicatorManager.html
        AFNetworkActivityIndicatorManager.sharedManager().enabled = true
    }
    
    // In the completion hanlder, if error != nil, there will be a non-nil serverResponse.
    public func sendServerRequestTo(toURL serverURL: NSURL, withParameters parameters:[String:AnyObject],
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
    public func uploadFileTo(serverURL: NSURL, fileToUpload:NSURL, withParameters parameters:[String:AnyObject]?, completion:((serverResponse:[String:AnyObject]?, error:NSError?)->())?) {
        
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
        
        /*
        self.manager.POST(serverURL.absoluteString, parameters: sendParameters, constructingBodyWithBlock: { (formData: AFMultipartFormData) in
                // NOTE!!! the name: given here *must* match up with that used on the server in the "multer" single parameter.
                // Was getting an odd try/catch error here, so this is the reason for "try!"; see https://github.com/AFNetworking/AFNetworking/issues/3005
                // 12/12/15; I think this issue was because I wasn't doing the do/try/catch, however.
                do {
                    try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName, fileName: SMServerConstants.fileUploadFieldName, mimeType: mimeType! as! String)
                    //try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName)
                } catch let error {
                    let message = "Failed to appendPartWithFileURL: \(fileToUpload); error: \(error)!"
                    Log.error(message)
                    completion?(serverResponse: nil, error: Error.Create(message))
                }
            },
            progress: nil,
            success: { (request:NSURLSessionDataTask, response:AnyObject?) in
                if let responseDict = response as? [String:AnyObject] {
                    print("AFNetworking Success: \(response)")
                    completion?(serverResponse: responseDict, error: nil)
                }
                else {
                    let error = Error.Create("No dictionary given in response")
                    print("**** AFNetworking FAILURE: \(error)")
                    completion?(serverResponse: nil, error: error)
                }
            },
            failure: { (request:NSURLSessionDataTask?, error:NSError) in
                Log.msg("**** AFNetworking FAILURE: \(error)")
                completion?(serverResponse: nil, error: error)
            })
        */
        
        var error:NSError? = nil
        
        // let fileData = NSData(contentsOfURL: fileToUpload)
        // Log.special("size of fileData: \(fileData!.length)")
        
        // http://stackoverflow.com/questions/34517582/how-can-i-prevent-modifications-of-a-png-file-uploaded-using-afnetworking-to-a-n
        // I have now set the COMPRESS_PNG_FILES Build Setting to NO to deal with this.
        
        let request = AFHTTPRequestSerializer().multipartFormRequestWithMethod("POST", URLString: serverURL.absoluteString, parameters: sendParameters, constructingBodyWithBlock: { (formData: AFMultipartFormData) in
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

        /*
        self.manager.POST(serverURL.absoluteString, parameters: sendParameters, constructingBodyWithBlock: { (formData: AFMultipartFormData) in
            // NOTE!!! the name: given here *must* match up with that used on the server in the "multer" single parameter.
            // Was getting an odd try/catch error here, so this is the reason for "try!"; see https://github.com/AFNetworking/AFNetworking/issues/3005
            // 12/12/15; I think this issue was because I wasn't doing the do/try/catch, however.
            do {
                try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName, fileName: SMServerConstants.fileUploadFieldName, mimeType: mimeType! as! String)
                //try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName)
            } catch let error {
                let message = "Failed to appendPartWithFileURL: \(fileToUpload); error: \(error)!"
                Log.error(message)
                completion?(serverResponse: nil, error: Error.Create(message))
            }
        }, success: { (request: AFHTTPRequestOperation, response:AnyObject) in
            if let responseDict = response as? [String:AnyObject] {
                print("AFNetworking Success: \(response)")
                completion?(serverResponse: responseDict, error: nil)
            }
            else {
                let error = Error.Create("No dictionary given in response")
                print("**** AFNetworking FAILURE: \(error)")
                completion?(serverResponse: nil, error: error)
            }
        }, failure:  { (request: AFHTTPRequestOperation?, error:NSError) in
            print("**** AFNetworking FAILURE: \(error)")
            completion?(serverResponse: nil, error: error)
        })
        */
        
        // This was not working with multer on the server side. I was getting req.file and req.files as undefined. Seems this doesn't use a multi-part form.
        /*
        Alamofire.upload(.POST, serverURL, file: fileURL)
             .progress { bytesWritten, totalBytesWritten, totalBytesExpectedToWrite in
                 print(totalBytesWritten)

                 // This closure is NOT called on the main queue for performance
                 // reasons. To update your ui, dispatch to the main queue.
                 dispatch_async(dispatch_get_main_queue()) {
                     print("Total bytes written: \(totalBytesWritten)")
                 }
             }
             .responseJSON { response in
                 debugPrint(response)
             }
        */
        
        /*
        // https://github.com/Alamofire/Alamofire/issues/679
        Alamofire.upload(
            .POST,
            serverURL,
            multipartFormData: { multipartFormData in
                // NOTE!!! the name: given here *must* match up with that used on the server in the "multer" single parameter.
                multipartFormData.appendBodyPart(fileURL: fileURL, name: SMSyncServerConstants.fileUploadFieldName)
            },
            encodingCompletion: { encodingResult in
                switch encodingResult {
                case .Success(let upload, _, _):
                    upload.progress { bytesRead, totalBytesRead, totalBytesExpectedToRead in
                        print(totalBytesRead)
                    }
                    upload.responseJSON { result in
                        debugPrint(result)
                    }
                case .Failure(let encodingError):
                    print(encodingError)
                }
            })
            */
    }
}
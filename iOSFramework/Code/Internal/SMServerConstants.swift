//
//  SMServerConstants.swift
//  NetDb
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

// Constants used in communication between the remote Node.js server and the iOS SMSyncServer framework.

import Foundation

public class SMServerConstants {
    
    // Don't change the following constant. I'm using it to extract constants and use them in the Node.js
    // Each line in the following is assumed (by the processing script) to either be a comment (starts with "//"), or have the structure: public static let X = Y (with a possible following comment)
    //SERVER-CONSTANTS-START
    
    // --------  Information sent to the server --------
    
    // MARK: REST API entry points on the server.
    
    // Append '/' and one these values to the serverURL to create the specific operation URL:
    public static let operationCheckForExistingUser = "CheckForExistingUser"
    public static let operationCreateNewUser = "CreateNewUser"
    
    // TODO: This will remove user credentials and all FileIndex entries from the SyncServer.
    public static let operationRemoveUser = "RemoveUser"

    public static let operationLock = "Lock"
    
    public static let operationUploadFile = "UploadFile"
    public static let operationDeleteFiles = "DeleteFiles"
    
    // Holding the lock is optional for this operation (but the lock cannot already be held by another user of the same cloud storage account).
    public static let operationGetFileIndex = "GetFileIndex"
    
    public static let operationSetupInboundTransfers = "SetupInboundTransfers"

    // Both of these implicitly do an Unlock after the cloud storage transfer.
    // operationStartOutboundTransfer is also known as the "commit" operation.
    public static let operationStartOutboundTransfer = "StartOutboundTransfer"
    public static let operationStartInboundTransfer = "StartInboundTransfer"
    
    // Provided to deal with the case of checking for downloads, but no downloads need to be carried out. Don't use if an operationId has been generated.
    public static let operationUnlock = "Unlock"
    
    public static let operationGetOperationId = "GetOperationId"

    // Both of the following are carried out in an unlocked state.
    public static let operationDownloadFile = "DownloadFile"
    // Remove the downloaded file from the server.
    public static let operationRemoveDownloadFile = "RemoveDownloadFile"

    public static let operationCheckOperationStatus = "CheckOperationStatus"
    public static let operationRemoveOperationId = "RemoveOperationId"
    
    // Recover from errors that occur after starting to transfer files from cloud storage.
    public static let operationInboundTransferRecovery = "InboundTransferRecovery"

    // For development/debugging only. Removes lock. Removes all outbound file changes. Intended for use with automated testing to cleanup between tests that cause rcServerAPIError.
    public static let operationCleanup = "Cleanup"

    // MARK: Custom HTTP headers sent back from server
    // For custom header naming conventions, see http://stackoverflow.com/questions/3561381/custom-http-headers-naming-conventions
    
    // Used for operationDownloadFile only.
    public static let httpDownloadParamHeader = "SMSyncServer-Download-Parameters"

    // MARK: Credential parameters sent to the server.
    
    // Key:
    public static let userCredentialsDataKey = "CredentialsData"
    // Each storage system type has one common key in the user credentials data nested structure:
    // Nested key:
    public static let cloudType = "CloudType"
    // Nested values
    public static let cloudTypeGoogle = "Google"
    
    // Nested key:
    public static let cloudFolderPath = "CloudFolderPath"
    // Value: The path into the cloud storage system where the files will be stored. *All* files are stored in a single folder in the cloud storage system. Currently, this *must* be a folder immediately off of the root. E.g., /Petunia. Subfolders (e.g., /Petunia/subfolder) are not allowable currently.
    
    // And each specific storage system has its own specific keys in the credentials data for the specific user.
    // MARK: For cloudTypeGoogle Google, there are the following additional keys.
    public static let googleUserCredentialsIdToken = "IdToken" // Value is an id token representing the user
    public static let googleUserCredentialsAuthCode = "AuthCode" // Value is a one-time authentication code

    // MARK: Other parameters sent to the server.

    // Required for all operations.
    // Key:
    public static let mobileDeviceUUIDKey = "MobileDeviceUUID"
    // Value: A UUID assigned by the app that uniquely represents this device.
    
    // When one or more files are being deleted (operationDeleteFiles), use the following
    // Key:
    public static let filesToDeleteKey = "FilesToDelete"
    // Value: an array of JSON objects with keys: fileUUIDKey, fileVersionKey, cloudFileNameKey, fileMIMEtypeKey.
    
    // When one or more files are being transferred from cloud storage (operationTransferFromCloudStorage), use the following
    // Key:
    public static let filesToTransferFromCloudStorageKey = "FilesToTransferFromCloudStorage"
    // Value: an array of JSON objects with keys: fileUUIDKey
    // Only the UUID key is needed because no change is being made to the file index-- the transfer operation consists of copying the current version of the file from cloud storage to the server temporary storage.
    
    // When a file is being downloaded (operationDownloadFile, or operationRemoveDownloadFile), use the following key.
    public static let downloadFileAttributes = "DownloadFileAttr"
    // Value: a JSON object with key: fileUUIDKey.
    // Like above, no change is being made to the file index, thus only the UUID is needed.
    
    // The following keys are required for file uploads (and some for deletions and downloads, see above).
    // Key:
    public static let fileUUIDKey = "FileUUID"
    // Value: A UUID assigned by the app that uniquely represents this file.
    
    // Key:
    public static let fileVersionKey = "FileVersion"
    // Value: A integer value, > 0, indicating the version number of the file. The version number is application specific, but provides a way of indicating progressive changes or updates to the file. It is an error for the version number to be reduced. E.g., if version number N is stored currently in the cloud, then after some changes, version N+1 should be next to be stored.
    
    // Key:
    public static let cloudFileNameKey = "CloudFileName"
    // Value: The name of the file on the cloud system.
    
    // Key:
    public static let fileMIMEtypeKey = "FileMIMEType"
    // Value: The MIME type of the file in the cloud/app.
    // TODO: Give a list of allowable MIME types. We have to restrict this because otherwise, there could be some injection error of the REST interface user creating a Google Drive folder or other special GD object.
    
    // Key:
    public static let appFileTypeKey = "AppFileType"
    // Value: An (optional) app-dependent file type for the file.
    
    // TODO: I'm not yet using this.
    public static let appGroupIdKey = "AppGroupId"
    // Value: A UUID string that (optionally) indicates an app-specific logical group that the file belongs to.
    
    // Used with operationCheckOperationStatus and operationRemoveOperationId
    // Key:
    public static let operationIdKey = "OperationId"
    // Value: An operationId that resulted from operationCommitChanges, or from operationTransferFromCloudStorage
    
    // Only used in development, not in production.
    // Key:
    public static let debugTestCaseKey = "DebugTestCase"
    // Value: An integer number (values given next) indicating a particular test case.
    
    // Values for debugTestCaseKey. These trigger simulated failures on the server at various points-- for testing.
    
    // Simulated failure when marking all files for user/device in PSOutboundFileChange's as committed. This applies only to file uploads (and upload deletions).
    public static let dbTcCommitChanges = 1

    // Simulated failure when updating the file index on the server. Occurs when finishing sending a file to cloud storage. And when checking the log for consistency when doing outbound transfer recovery. Applies only to uploads (and upload deletions).
    public static let dbTcSendFilesUpdate = 2
    
    // Simulated failure when changing the operation id status to "in progress" when transferring files to/from cloud storage. Applies to both uploads and downloads.
    public static let dbTcInProgress = 3
    
    // Simulated failure when setting up for transferring files to/from cloud storage. This occurrs after changing the operation id status to "in progress" and before the actual transferring of files. Applies to both uploads and downloads.
    public static let dbTcSetup = 4
    
    // Simulated failure when transferring files to/from cloud storage. Occurs after dbTcSetup. Applies to both uploads and downloads.
    public static let dbTcTransferFiles = 5
    
    // Simulated failure when removing the lock after doing cloud storage transfer. Applies to both uploads and downloads.
    public static let dbTcRemoveLockAfterCloudStorageTransfer = 6
    
    public static let dbTcGetLockForDownload = 7

    // Simulated failure in a file download, when getting download file info. Applies to download only.
    public static let dbTcGetDownloadFileInfo = 8
    
    // MARK: Responses from server
    
    // Key:
    public static let internalUserId = "InternalUserId"
    // Values: See documentation on internalUserId in SMSyncServerUser
    
    // Key:
    public static let resultCodeKey = "ServerResult"
    // Values: Integer values, defined below.
    
    // This is returned on a successful call to operationStartFileChanges.
    // Key:
    public static let resultOperationIdKey = "ServerOperationId"
    // Values: A unique string identifying the operation on the server. Valid until the operation completes on the server, and the client checks the state of the operation using operationCheckOpStatus.
    
    // If there was an error, the value of this key may have textual details.
    public static let errorDetailsKey = "ServerErrorDetails"

    // This is returned on a successful call to operationGetFileIndex
    // Key:
    public static let resultFileIndexKey = "ServerFileIndex"
    // Values: An JSON array of JSON objects describing the files for the user.
    
    // The keys/values within the elements of that file index array are as follows:
    // (Server side implementation note: Just changing these string constants below is not sufficient to change the names on the server. See PSFileIndex.sjs on the server).
    public static let fileIndexFileId = "fileId" // Value: UUID String; Client identifier for the file.
    public static let fileIndexCloudFileName = "cloudFileName" // Value: String; name of file in cloud storage.
    public static let fileIndexMimeType = "mimeType" // Value: String; A valid MIME type
    public static let fileIndexAppFileType = "appFileType" // Value: String; an app-specific file type
    public static let fileIndexDeleted = "deleted" // Value: Boolean; Has file been deleted?
    public static let fileIndexFileVersion = "fileVersion" // Value: Integer; version of file
    public static let fileIndexLastModified = "lastModified" // Value: String; a Javascript date.
    public static let fileSizeBytes = "fileSizeBytes" // Value: Integer; The size of the file in cloud storage.
    
    // These are returned on a successful call to operationCheckOperationStatus. Note that "successful" doesn't mean the server operation being checked completed successfully.
    // Key:
    public static let resultOperationStatusCodeKey = "ServerOperationStatusCode"
    // Values: Numeric values as indicated in rc's for OperationStatus below.
    
    // Key:
    public static let resultOperationStatusErrorKey = "ServerOperationStatusError"
    // Values: Will be empty if no error occurred, and otherwise has a string describing the error.
    
    // Key:
    public static let resultOperationStatusCountKey = "ServerOperationStatusCount"
    // Values: The numer of cloud storage operations attempted.
    
    // Server result codes (rc's)
    
    // Common result codes
    // Generic success! Some of the other result codes below also can indicate success.
    public static let rcOK = 0
    
    public static let rcUndefinedOperation = 1
    public static let rcOperationFailed = 2
    
    // TODO: What happens when we get this return code back from the server? Can we do a (silent) sign in again and refresh this? Not currently dealing with this. See, however, [1] in Settings.swift, and [1] in SMServerAPI.swift
    // TODO: Create a test case that tests this situation-- though it seems like it's not that easy to do WRT to automated testing: Because it involves a large time delay, on the order of a day to get the Google Drive security info to go stale.
    public static let rcStaleUserSecurityInfo = 3
    
    // An error due to the way the server API was used. This error is *not* recoverable in the sense that the server API caller should not try to use operationFileChangesRecovery or other such recovery operations to just repeat the request because without changes the operation will just fail again.
    public static let rcServerAPIError = 4
    
    public static let rcNetworkFailure = 5
    
    // Used only by client side: To indicate that a return code could not be obtained.
    public static let rcInternalError = 6
    
    public static let rcUserOnSystem = 51
    public static let rcUserNotOnSystem = 52
    
    // 2/13/16; This is not necessarily an API error. E.g., I just ran into a situation where a lock wasn't obtained (because it was held by another app/device), and this resulted in an attempted upload recovery. And the upload recovery failed because the lock wasn't held.
    public static let rcLockNotHeld = 53
    
    public static let rcNoOperationId = 54
    
    // rc's for serverOperationCheckForExistingUser
    // rcUserOnSystem
    // rcUserNotOnSystem
    // rcOperationFailed: error

    // rc's for operationCreateNewUser
    // rcOK (new user was created).
    // rcUserOnSystem: Informational response; could be an error in app, depending on context.
    // rcOperationFailed: error
    
    // operationStartUploads
    public static let rcLockAlreadyHeld = 100
    
    // rc's for OperationStatus
    
    // The operation hasn't started asynchronous operation yet.
    public static let rcOperationStatusNotStarted = 200
    
    // Operation is in asynchronous operation. It is running after operationCommitChanges returned success to the REST/API caller.
    public static let rcOperationStatusInProgress = 201
    
    // These three can occur after the commit returns success to the client/app. For purposes of recovering from failure, the following three statuses should be taken to be the same-- just indicating failure. Use the resultOperationStatusCountKey to determine what kind of recovery to perform.
    public static let rcOperationStatusFailedBeforeTransfer = 202
    public static let rcOperationStatusFailedDuringTransfer = 203
    public static let rcOperationStatusFailedAfterTransfer = 204
    
    public static let rcOperationStatusSuccessfulCompletion = 210

    // rc's for operationFileChangesRecovery
    
    // Really the same as rcOperationStatusInProgress, but making this a different different value because of the Swift -> Javascript conversion.
    public static let rcOperationInProgress = 300
    
    // For convenience on client side; not returned by server.
    public static let rcNoFilesToDownload = 400
    
    // -------- Other constants --------

    // Used in the file upload form. This is not a key specifically, but has to correspond to that used on the server.
    public static let fileUploadFieldName = "file"
    
    //SERVER-CONSTANTS-END
    // Don't change the preceding constant. I'm using it to extract constants and use them in Node.js
}
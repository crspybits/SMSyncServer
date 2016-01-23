// ***** This is a machine generated file: Do not change by hand!! *****
'use strict';
function define(name, value) {
	Object.defineProperty(exports, name, {
		value:      value,
		enumerable: true
	});
}
    
    // --------  Information sent to the server --------
    
    // MARK: REST API entry points on the server.
    
    // Append '/' and one these values to the serverURL to create the specific operation URL:
	define("operationCheckForExistingUser", "CheckForExistingUser");
	define("operationCreateNewUser", "CreateNewUser");
    
    // TODO: This will remove user credentials and all FileIndex entries from the SyncServer.
	define("operationRemoveUser", "RemoveUser");

	define("operationLock", "Lock");
    
	define("operationUploadFile", "UploadFile");
	define("operationDeleteFiles", "DeleteFiles");
    
    // Holding the lock is optional for this operation (but the lock cannot already be held by another user of the same cloud storage account).
	define("operationGetFileIndex", "GetFileIndex");
    
    // Both of these implicitly do an Unlock after the cloud storage transfer.
    // operationStartOutboundTransfer is also known as the "commit" operation.
	define("operationStartOutboundTransfer", "StartOutboundTransfer");
	define("operationStartInboundTransfer", "StartInboundTransfer");
    
	define("operationGetOperationId", "GetOperationId");

    // Carried out in an unlocked state.
	define("operationDownloadFile", "DownloadFile");

	define("operationCheckOperationStatus", "CheckOperationStatus");
	define("operationRemoveOperationId", "RemoveOperationId");

    // Recovery from errors during upload process (i.e., prior to transferring files to cloud storage).
	define("operationUploadRecovery", "UploadRecovery");

    // Recover from errors that occur after starting to transfer files to cloud storage. To use this recovery, the operation must have failed with rcOperationStatusFailedDuringTransfer. On successful operation, this will transfer any remaining needed files to cloud storage.
	define("operationOutboundTransferRecovery", "OutboundTransferRecovery");

    // For development/debugging only. Removes lock. Removes all outbound file changes. Intended for use with automated testing to cleanup between tests that cause rcServerAPIError.
	define("operationCleanup", "Cleanup");

    // MARK: Credential parameters sent to the server.
    
    // Key:
	define("userCredentialsDataKey", "CredentialsData");
    // Each storage system type has one common key in the user credentials data nested structure:
    // Nested key:
	define("cloudType", "CloudType");
    // Nested values
	define("cloudTypeGoogle", "Google");
    
    // Nested key:
	define("cloudFolderPath", "CloudFolderPath");
    // Value: The path into the cloud storage system where the files will be stored. *All* files are stored in a single folder in the cloud storage system. Currently, this *must* be a folder immediately off of the root. E.g., /Petunia. Subfolders (e.g., /Petunia/subfolder) are not allowable currently.
    
    // And each specific storage system has its own specific keys in the credentials data for the specific user.
    // MARK: For cloudTypeGoogle Google, there are the following additional keys.
	define("googleUserCredentialsIdToken", "IdToken");
	define("googleUserCredentialsAuthCode", "AuthCode");

    // MARK: Other parameters sent to the server.

    // Required for all operations.
    // Key:
	define("mobileDeviceUUIDKey", "MobileDeviceUUID");
    // Value: A UUID assigned by the app that uniquely represents this device.
    
    // When one or more files are being deleted (operationDeleteFiles), use the following
    // Key:
	define("filesToDeleteKey", "FilesToDelete");
    // Value: an array of JSON objects with keys: fileUUIDKey, fileVersionKey, cloudFileNameKey, fileMIMEtypeKey.
    
    // When one or more files are being transferred from cloud storage (operationTransferFromCloudStorage), use the following
    // Key:
	define("filesToTransferFromCloudStorageKey", "FilesToTransferFromCloudStorage");
    // Value: an array of JSON objects with keys: fileUUIDKey, fileVersionKey, cloudFileNameKey, fileMIMEtypeKey.
    
    // The following keys are required for file uploads and downloads (and some for deletions, see above).
    // Key:
	define("fileUUIDKey", "FileUUID");
    // Value: A UUID assigned by the app that uniquely represents this file.
    
    // Key:
	define("fileVersionKey", "FileVersion");
    // Value: A integer value, > 0, indicating the version number of the file. The version number is application specific, but provides a way of indicating progressive changes or updates to the file. It is an error for the version number to be reduced. E.g., if version number N is stored currently in the cloud, then after some changes, version N+1 should be next to be stored.
    
    // Key:
	define("cloudFileNameKey", "CloudFileName");
    // Value: The name of the file on the cloud system.
    
    // Key:
	define("fileMIMEtypeKey", "FileMIMEType");
    // Value: The MIME type of the file in the cloud/app.
    // TODO: Give a list of allowable MIME types. We have to restrict this because otherwise, there could be some injection error of the REST interface user creating a Google Drive folder or other special GD object.
    
    // Key:
	define("appFileTypeKey", "AppFileType");
    // Value: An (optional) app-dependent file type for the file.
    
    // TODO: I'm not yet using this.
	define("appGroupIdKey", "AppGroupId");
    // Value: A UUID string that (optionally) indicates an app-specific logical group that the file belongs to.
    
    // Used with operationCheckOperationStatus and operationRemoveOperationId
    // Key:
	define("operationIdKey", "OperationId");
    // Value: An operationId that resulted from operationCommitChanges, or from operationTransferFromCloudStorage
    
    // Only used in development, not in production.
    // Key:
	define("debugTestCaseKey", "DebugTestCase");
    // Value: An integer number (values given next) indicating a particular test case.
    
    // Values for debugTestCaseKey
	define("dbTcCommitChanges", 1);
	define("dbTcInProgress", 2);
	define("dbTcSetup", 3);
	define("dbTcSendFiles", 4);
	define("dbTcSendFilesUpdate", 5);
	define("dbTcRemoveLock", 6);
    
    // MARK: Responses from server
    
    // Key:
	define("resultCodeKey", "ServerResult");
    // Values: Integer values, defined below.
    
    // This is returned on a successful call to operationStartFileChanges.
    // Key:
	define("resultOperationIdKey", "ServerOperationId");
    // Values: A unique string identifying the operation on the server. Valid until the operation completes on the server, and the client checks the state of the operation using operationCheckOpStatus.
    
    // If there was an error, the value of this key may have textual details.
	define("errorDetailsKey", "ServerErrorDetails");

    // This is returned on a successful call to operationGetFileIndex
    // Key:
	define("resultFileIndexKey", "ServerFileIndex");
    // Values: An JSON array of JSON objects describing the files for the user.
    
    // The keys/values within the elements of that file index array are as follows:
    // (Server side implementation note: Just changing these string constants below is not sufficient to change the names on the server. See PSFileIndex.sjs on the server).
	define("fileIndexFileId", "fileId");
	define("fileIndexCloudFileName", "cloudFileName");
	define("fileIndexMimeType", "mimeType");
	define("fileIndexAppFileType", "appFileType");
	define("fileIndexDeleted", "deleted");
	define("fileIndexFileVersion", "fileVersion");
	define("fileIndexLastModified", "lastModified");
	define("fileSizeBytes", "fileSizeBytes");
    
    // These are returned on a successful call to operationCheckOperationStatus. Note that "successful" doesn't mean the server operation being checked completed successfully.
    // Key:
	define("resultOperationStatusCodeKey", "ServerOperationStatusCode");
    // Values: Numeric values as indicated in rc's for OperationStatus below.
    
    // Key:
	define("resultOperationStatusErrorKey", "ServerOperationStatusError");
    // Values: Will be empty if no error occurred, and otherwise has a string describing the error.
    
    // Key:
	define("resultOperationStatusCountKey", "ServerOperationStatusCount");
    // Values: The numer of cloud storage operations attempted.
    
    // Server result codes (rc's)
    
    // Common result codes
    // Generic success! Some of the other result codes below also can indicate success.
	define("rcOK", 0);
    
	define("rcUndefinedOperation", 1);
	define("rcOperationFailed", 2);
    
    // TODO: What happens when we get this return code back from the server? Can we do a (silent) sign in again and refresh this? Not currently dealing with this. See, however, [1] in Settings.swift, and [1] in SMServerAPI.swift
    // TODO: Create a test case that tests this situation-- though it seems like it's not that easy to do WRT to automated testing: Because it involves a large time delay, on the order of a day to get the Google Drive security info to go stale.
	define("rcStaleUserSecurityInfo", 3);
    
    // An error due to the way the server API was used. This error is *not* recoverable in the sense that the server API caller should not try to use operationFileChangesRecovery or other such recovery operations to just repeat the request because without changes the operation will just fail again.
	define("rcServerAPIError", 4);
    
	define("rcNetworkFailure", 5);
    
    // Used only by client side: To indicate that a return code could not be obtained.
	define("rcInternalError", 6);
    
	define("rcUserOnSystem", 51);
	define("rcUserNotOnSystem", 52);
    
    // rc's for serverOperationCheckForExistingUser
    // rcUserOnSystem
    // rcUserNotOnSystem
    // rcOperationFailed: error

    // rc's for operationCreateNewUser
    // rcOK (new user was created).
    // rcUserOnSystem: Informational response; could be an error in app, depending on context.
    // rcOperationFailed: error
    
    // operationStartUploads
	define("rcLockAlreadyHeld", 100);
    
    // rc's for OperationStatus
    
    // The operation hasn't started asynchronous operation yet.
	define("rcOperationStatusNotStarted", 200);

    // No files transferred to cloud storage. Didn't successfully kick off commit-- commit would have returned an error.
	define("rcOperationStatusCommitFailed", 201);
    
    // Operation is in asynchronous operation. It is running after operationCommitChanges returned success to the REST/API caller.
	define("rcOperationStatusInProgress", 202);
    
    // These three can occur after the commit returns success to the client/app. For purposes of recovering from failure, the following three statuses should be taken to be the same-- just indicating failure. Use the resultOperationStatusCountKey to determine what kind of recovery to perform.
	define("rcOperationStatusFailedBeforeTransfer", 203);
	define("rcOperationStatusFailedDuringTransfer", 204);
	define("rcOperationStatusFailedAfterTransfer", 205);
    
	define("rcOperationStatusSuccessfulCompletion", 210);

    // rc's for operationFileChangesRecovery
    
    // Really the same as rcOperationStatusInProgress, but making this a different different value because of the Swift -> Javascript conversion.
	define("rcOperationInProgress", 300);
    
    // -------- Other constants --------

    // Used in the file upload form. This is not a key specifically, but has to correspond to that used on the server.
	define("fileUploadFieldName", "file");
    
// ***** This is a machine generated file: Do not change by hand!! *****
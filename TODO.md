# TODO List: In priority order (top are more important)

## Shared Notes demo app issues

1. Figure out if we have a combination of adds and deletes of images if we upload the right ones and delete the right ones-- with no trash left over.
1. Why does font go smaller when we reenter the editing VC? This appears to be because of the way I'm setting the attributed text at ranges. It stripping out the attributed properties.
1. Should use the appDataType field of attr here-- to interpret the type of data downloaded.
1. Encode related object of a ImageNote in the JSON. So after it's received at destination, we can relate it. HOW DO WE DO THIS: The way we are doing it so far files don't have any general meta data that apps can set. It seems we need to provide this -- e.g., a json structure would seem to be a good way to go. And make it part of the SMSyncAttributes. This could just replace the appDataType-- as it's a really just more general app specific chunk of data.

## FUNCTIONALITY

1. DONE 5/19/16. Conflict management: Dealing with downloads that conflict with local modifications.
1. DONE. What about conflicts where the local app is modifying some data. It seems like there should be some kind of lock that can be set by an app to prevent modification while modifying the data. E.g., in the Shared Notes app, a user might be in the midst of making a change to a note. Don't want that note overwritten without taking their changes into account. Presumably these locks should not span launches of the app. e.g., to deal with the case where the app crashes or loses CPU. DECISION: I decided not to deal with app level modification locks within the SMSyncServer. [For the rationale for that choice see this link](http://www.spasticmuffin.biz/blog/2016/05/11/conflict-management-in-the-smsyncserver/)

1. DONE. Make sure the client upload operations have the documented property: If there is a file with the same uuid, which has been enqueued but not yet committed, it will be replaced by the given file. (NOTE: This had previously been implemented).

1. DONE 5/20/16. Add ability to upload a zero length file or a nil NSData. It should be possible to have an empty file on cloud storage.

1. Improve robustness of recovering from errors in network/server access. I've been encountering some failures in server access where (I think) due to a poor network connection (a) I don't detect that the network is down, but (b) the connection to the server fails. Right now what happens is that the server API call is retried several times, then the client goes into a failure mode. Instead, upon such a server API failure, it should be treated the same as a network loss. Even if the server was down, I think this is the right way to handle this issue. With the server down, we'd need to restart the server, and the app should later retry. TESTING: Add manual tests which shut down the network at certain points. In that way, the network will be up, but the server will be unresponsive.

1. Some calls to SMServerAPI break down into multiple server calls. Need to change this because I think it's interfering with recovery ability of client.

1. Improving detection of errors in file data using checksums (From Daniel Pfeiffer): "I would suggest putting some technological solutions in place to shore up your third assumption (about users messing with the files). I’ve used both Dropbox and Google Drive in some of the apps I’ve worked on and have found that I can’t trust the integrity of that data. Sometimes it wasn’t even the user’s fault. I don’t know if Dropbox still does this, but there was a point in time it was changing line endings when files were synced between different OSes—just the sort of thing to make the SyncServer stumble! Perhaps SyncServer should store an MD5 hash of the last known integral version of the file. When reading, it compares hashes. If the hashes don’t match, then SyncServer knows the file was changed somewhere else. It can try reading it, or provide the app with a warning about the file being changed."

1. Need to get autocommit working-- so that can periodically initiate sync calls.

1. I need to rethink the use of .ClientAPIError in the mode. E.g., in the SMSyncServer.session.deleteFile call, the call can change the mode to .ClientAPIError. But, what if the mode was .Synchronizing before this??? Seems like I need to separate between internal mode of the sync server, and errors caused directly by calling the client API. Need also to review uses of .NonRecoverableError. Some of these are .ClientAPIErrors and need to be rethought as above.

1. Incorporate appFileType; See SMSyncAttributes. Seems like we should change that from appFileType to appDataType to get ready for generic upload interface.
 
1. Generic upload interface: One call that will enable various types of items (NSData, file URL's, AnyObject's) to be uploaded. Will need delegate methods that will provide coding and decoding of these items. The `syncServerDownloadsComplete` delegate method will need to deal with this-- providing items back to the caller in the form they were given. E.g., if you upload NSData, then it should be downloaded as NSData.

1. Add Dropbox to cloud storage systems. Needs work on both server side and client side. Need to figure out how to do something like inheritance in Javascript so I can have a superclass definition of the interface for a generic cloud storage system, which will hopefully make it easier to implement interfaces to new specific cloud storage systems.

1. Need to use SMSyncServer within published/deployed apps.

1. Improve performance/reliability of file upload and download by breaking up files into blocks and transmitting/receiving those blocks. E.g., 100K blocks. Have already sketched with NSManagedObject descriptions. While this can be considered a performance issue, it's also a functionality issue: In the case of having a lower speed network connection, or larger files, it's possible that without this change, uploads/downloads would never complete-- they would always fail (e.g., when the user gets frustrated with progress) and restart from the beginning and never complete overall.

1. Need ability for app to change the name of a remote file. There is an obvious issue with this-- we can't tell for certain if the change will succeed. Though, after updating with any current downloads this should be possible. An alternative to this is to have have an app upload an index.html file to user cloud storage which can be opened in a browser, and map the UUID's for the files, used as remote names, to more useful user names.

1. The server operation operationCleanup should also remove any entries from the PSFileTransferLog and from PSInboundFile.

1. [Make it possible to logout of one cloud storage account on the client, and log into another](http://www.spasticmuffin.biz/blog/2016/04/02/design-issue-changing-cloud-storage-accounts-with-the-smsyncserver/).

1. Create an Android client.

1. Create a Mac OS X client -- i.e., enable programs running on Mac OS X to sync using these tools.

1. Create a Windows client-- i.e., enable programs running on the Windows Operating System to sync using these tools.

1. Create a read-only client for use in a web-browser. It needs to be read-only because clients for SMSyncServer rely on persistent storage in order to perform recovery and relatively large scale persistent storage is not available in a web-browser.

1. Implement an improved sharing mechanism. Currently, sharing of data requires sharing of credentials for a cloud storage account. A user should be able to invite a Facebook or other user, give them some (possibly) limited permissions and give them access to their data. Since we've got cloud storage credentials (OAuth2) stored on the server, this should be possible. Part of the intent of this improved sharing mechanism is also to allow integration with other systems. E.g., in the case of a Pet Vet Records app such as the Petunia iPad app, to enable back-end office vet systems to add/read data from a particular client's data in a specific manner-- without giving the vet access to all of your data!

1. Lock breaking on the server: It is possible that a client will not be able to remove a lock. E.g., if the client obtains a lock, fails, and then never gains access to the network again. To implement lock breaking, we need at minimum a means to know if an ongoing transfer is still ongoing. What I'd like to do is break a lock if it has not been removed by the owner, after some fixed period of time after an ongoing transfer has completed. Or after that fixed period of time if an ongoing transfer has not been initiated.

1. Making the client API fully reentrant: I have not yet specifically taken steps to ensure that the client API is reentrant. It should be analyzed to see if multiple threads making calls on the SMSyncServer.session calls may cause synchronization problems. (Note that I have taken steps within the client-side SMSyncServer framework to deal with synchronization issues due to the asynchronous callbacks present within the client-side framework). For now, I'm assuming that the typical use case for the client API is where it is called from *only* the main thread, and this reentrancy issue should not be an issue.

## PERFORMANCE ISSUES

1. [File system change to enable server-side scaling](http://www.spasticmuffin.biz/blog/2016/05/09/re-architecting-the-smsyncserver-file-system/).

1. WebSockets: Make it possible to not use polling on the app to detect the end of a long-running server operation or the availability of downloads on the server.

1. Deal with issue that downloading groups of objects may grow too large. I.e., when uploading we can control a collection of items that need to be uploaded by terminating it with a commit. But have no sense of this on download. An example of a worst case of this is a download of all files with a new device when other device(s) have accumulated a large amount of data/files. Would like some logical, i.e., transactional way of grouping the files for download.

## SECURITY

1. Improve security so that other apps can't use your server: e.g., [On iOS, implement in-app purchase-based app](security.http://stackoverflow.com/questions/29212225/is-there-a-way-to-verify-that-an-identifier-for-vendor-idfv-is-valid).

1. Improving security (From Daniel Pfeiffer): "I know it’s early in the process, but have you thought about how data encryption might come into play at all (for the data at rest on the cloud service)? Encryption might be tricky to implement that while still allowing the data to be portable, but without it, it might limit the type of data people are willing to store."


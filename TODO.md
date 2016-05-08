# TODO List: In priority order (top are more important)

1. I've been doing hosted testing with Heroku, and I've just learned that the file system, for writing files, in Heroku is `emphemeral`. "The underlying filesystem will be destroyed when an app is restarted, reconfigured (e.g. heroku config ...), scaled, etc." "Any files that require permanence should be written to S3, or a similar durable store. S3 is preferred as Heroku runs on AWS and S3 offers some performance advantages." (http://stackoverflow.com/questions/12416738/how-to-use-herokus-ephemeral-filesystem). And "During the dyno’s lifetime its running processes can use the filesystem as a temporary scratchpad, but no files that are written are visible to processes in any other dyno and any files written will be discarded the moment the dyno is stopped or restarted." (https://devcenter.heroku.com/articles/dynos).
I've been assuming that files in the hosting file system will have stable persistence. E.g., that the app can upload a series of files to the Node.js host and there is no danger of those files being lost. A main question here is: Is this `ephemeral` file system persistence typical of Node.js hosting systems?
Looking at OpenShift, it seems that this not universal: "OpenShift Online provides 1GB of persistent disk storage to each application container." "This [is] a great place to stash user-generated content, or other persistent runtime information that should be kept through reboots and deploys (without being checked in to your project’s source tree)." (https://blog.openshift.com/10-reasons-openshift-is-the-best-place-to-host-your-nodejs-app/).

1. Add ability to upload a zero length file or a nil NSData. It should be possible to have an empty file on cloud storage.

1. Conflict management: Dealing with downloads that conflict with local modifications.
1. What about conflicts where the local app is modifying some data. It seems like there should be some kind of lock that can be set by an app to prevent modification while modifying the data. E.g., in the Shared Notes app, a user might be in the midst of making a change to a note. Don't want that note overwritten without taking their changes into account. Presumably these locks should not span launches of the app. e.g., to deal with the case where the app crashes or loses CPU.

1. Need ability for app to change the name of a remote file. There is an obvious issue with this-- we can't tell for certain if the change will succeed. Though, after updating with any current downloads this should be possible.

1. Improve robustness of recovering from errors in network/server access. I've been encountering some failures in server access where (I think) due to a poor network connection (a) I don't detect that the network is down, but (b) the connection to the server fails. Right now what happens is that the server API call is retried several times, then the client goes into a failure mode. Instead, upon such a server API failure, it should be treated the same as a network loss. Even if the server was down, I think this is the right way to handle this issue. With the server down, we'd need to restart the server, and the app should later retry. TESTING: Add manual tests which shut down the network at certain points. In that way, the network will be up, but the server will be unresponsive.

1. Generic upload interface: One call that will enable various types of items (NSData, file URL's, AnyObject's) to be uploaded. Will need delegate methods that will provide coding and decoding of these items. The `syncServerDownloadsComplete` delegate method will need to deal with this-- providing items back to the caller in the form they were given. E.g., if you upload NSData, then it should be downloaded as NSData. (How does this relate to the appFileType we already have planned? What if we changed that from appFileType to appDataType?).

1. WebSockets: Make it possible to not use polling on the app to detect the end of a long-running server operation or the availability of downloads on the server.

1. Improve performance/reliability of file upload and download by breaking up files into blocks and transmitting/receiving those blocks. E.g., 100K blocks. Have already sketched with NSManagedObject descriptions.

1. Add Dropbox to cloud storage systems. Needs work on both server side and client side.

1. Make it possible to logout of one cloud storage account, and log into another. See http://www.spasticmuffin.biz/blog/2016/04/02/design-issue-changing-cloud-storage-accounts-with-the-smsyncserver/

1. Deal with issue that downloading groups of objects may grow too large. I.e., when uploading we can control a collection of items that need to be uploaded by terminating it with a commit. But have no sense of this on download. An example of a worst case of this is a download of all files with a new device when other device(s) have accumulated a large amount of data/files. Would like some logical, i.e., transactional way of grouping the files for download.

1. Create an Android client.

1. Improve security so that other apps can't use your server: e.g., On iOS, implement in-app purchase-based app security.http://stackoverflow.com/questions/29212225/is-there-a-way-to-verify-that-an-identifier-for-vendor-idfv-is-valid 

1. Implement a sharing mechanism. It's inappropriate now that sharing of data requires sharing of credentials for a cloud storage account. A user should be able to invite a Facebook or other user, give them some (possibly) limited permissions and give them access to their data. Since we've got cloud storage credentials (OAuth2) stored on the server, this should be possible.

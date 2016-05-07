# TODO List: In priority order (top are more important)

1. Add ability to upload a zero length file or a nil NSData. It should be possible to have an empty file on cloud storage.

1. Conflict management: Dealing with downloads that conflict with local modifications.
1. What about conflicts where the local app is modifying some data. It seems like there should be some kind of lock that can be set by an app to prevent modification while modifying the data. E.g., in the Shared Notes app, a user might be in the midst of making a change to a note. Don't want that note overwritten without taking their changes into account. Presumably these locks should not span launches of the app. e.g., to deal with the case where the app crashes or loses CPU.

1. Need ability for app to change the name of a remote file. There is an obvious issue with this-- we can't tell for certain if the change will succeed. Though, after updating with any current downloads this should be possible.

1. Generic upload interface: One call that will enable various types of items (NSData, file URL's, AnyObject's) to be uploaded. Will need delegate methods that will provide coding and decoding of these items. The `syncServerDownloadsComplete` delegate method will need to deal with this-- providing items back to the caller in the form they were given. E.g., if you upload NSData, then it should be downloaded as NSData.

1. Deal with issue that downloading groups of objects may grow too large. I.e., when uploading we can control a collection of items that need to be uploaded by terminating it with a commit. But have no sense of this on download. An example of a worst case of this is a download of all files with a new device when other device(s) have accumulated a large amount of data/files. Would like some logical, i.e., transactional way of grouping the files for download.



SMUploadQueue:
    `changes` property: A collection of file changes (uploads or upload-deletes) represented by this object.
    For a single instance of an SMUploadQueue, exactly one of the following is non-nil:
        i) `beingUploaded`: file changes currently being uploaded to the server.
        ii) `committed`: file changes that have been committed and are awaiting upload.
        iii) `beingCreated`: file changes not yet committed.

SMQueues:
    There is only ever a single instance of this Core Data object.
    i) `uploadsBeingPrepared`: The app is adding uploads and/or upload-deletes to this queue, and hasn't yet commited it.
    ii) `committedUploads`: The series of queue's of uploads/upload-deletions which have been committed.

    Only one of the following two can be non-nil (i.e., the client is doing uploads or doing downloads but not both).
    iii) `beingUploaded`: The series of uploads/upload-deletions currently being uploaded.

    iv) `beingDownloaded`: The series of downloads/download-deletions currently being downloaded.
    With this being non-nil, there can also be conflicts:
    v) `downloadConflicts`: The collection of possible conflicts with local files arising from the downloads.


SMUploadFileChange:
    One of these instances is created for each upload or upload-delete client API method called.
    `changedFile` property: The SMLocalFile which is being uploaded or upload-deleted.
    `queue` property: The SMUploadQueue instance to which this file change belongs.
    `blocks` property: For files which are being uploaded (not upload-deleted), and when its SMUploadQueue is being processed (i.e., sent to the server), this references the series of blocks which need to be uploaded for the file.

SMLocalFile:
    `deletedOnServer`: Indicates an upload-deletion has already been performed.
    `pendingUploads`: The (possibly nil) series of uploads/upload-deletions which are pending for this UUID/file.
    `download`: The (possibly nil) download/download-deletion pending for this file.

    At most one of the above can be non-nil. If a download becomes available for a file that has a pending upload, then this needs to be managed as a conflict. The conflict will have to be resolved by the app/client. (E.g., the pending upload could be purged-- meaning that the local change could be overriden).

SMDownloadConflict:
    The purpose of these entities are to ensure that the client app deals with conflicts arising between files about to be downloaded or download-deleted and local pending uploads and upload-deletions.

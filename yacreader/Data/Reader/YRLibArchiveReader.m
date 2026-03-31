#import "YRLibArchiveReader.h"

#import "LibArchiveShim.h"
#import <os/log.h>

static NSString * const YRLibArchiveReaderErrorDomain = @"YRLibArchiveReaderErrorDomain";

typedef NS_ENUM(NSInteger, YRLibArchiveReaderErrorCode) {
    YRLibArchiveReaderErrorOpenFailed = 1,
    YRLibArchiveReaderErrorReadFailed = 2,
    YRLibArchiveReaderErrorInvalidEntry = 3,
};

@interface YRLibArchiveReader ()

@property (nonatomic, strong, readonly) NSURL *archiveURL;
@property (nonatomic, strong, readonly) id<YRLibArchiveDataSource> dataSource;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *entryPaths;
@property (nonatomic) struct archive *archiveHandle;
@property (nonatomic) NSInteger nextReadableEntryIndex;
@property (nonatomic) la_int64_t currentOffset;
@property (nonatomic, copy) NSData *currentReadBuffer;

@end

static int YRLibArchiveOpenCallback(struct archive *archive, void *clientData);
static la_ssize_t YRLibArchiveReadCallback(struct archive *archive, void *clientData, const void **buffer);
static la_int64_t YRLibArchiveSkipCallback(struct archive *archive, void *clientData, la_int64_t request);
static la_int64_t YRLibArchiveSeekCallback(struct archive *archive, void *clientData, la_int64_t offset, int whence);
static int YRLibArchiveCloseCallback(struct archive *archive, void *clientData);

@implementation YRLibArchiveReader

- (nullable instancetype)initWithArchiveURL:(NSURL *)archiveURL error:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _archiveURL = archiveURL;
    _dataSource = nil;
    _entryPaths = @[];
    _archiveHandle = NULL;
    _nextReadableEntryIndex = 0;
    _currentOffset = 0;
    _currentReadBuffer = nil;

    if (![self enumerateEntryPaths:error]) {
        return nil;
    }

    return self;
}

- (nullable instancetype)initWithDataSource:(id<YRLibArchiveDataSource>)dataSource error:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _archiveURL = nil;
    _dataSource = dataSource;
    _entryPaths = @[];
    _archiveHandle = NULL;
    _nextReadableEntryIndex = 0;
    _currentOffset = 0;
    _currentReadBuffer = nil;

    if (![self enumerateEntryPaths:error]) {
        return nil;
    }

    return self;
}

- (void)dealloc {
    [self closeArchive];
}

- (nullable NSData *)dataForEntryAtIndex:(NSInteger)index error:(NSError * _Nullable * _Nullable)error {
    if (index < 0 || index >= self.entryPaths.count) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:YRLibArchiveReaderErrorDomain
                                         code:YRLibArchiveReaderErrorInvalidEntry
                                     userInfo:@{NSLocalizedDescriptionKey: @"The requested archive entry index is invalid."}];
        }
        return nil;
    }

    if (![self seekToEntryAtIndex:index error:error]) {
        return nil;
    }

    return [self readCurrentEntry:error];
}

- (BOOL)enumerateEntryPaths:(NSError * _Nullable * _Nullable)error {
    if (![self openArchive:error]) {
        return NO;
    }

    NSMutableArray<NSString *> *entryPaths = [NSMutableArray array];
    struct archive_entry *entry = NULL;

    while (YES) {
        int result = archive_read_next_header(self.archiveHandle, &entry);
        if (result == ARCHIVE_EOF) {
            break;
        }

        if (result != ARCHIVE_OK) {
            [self closeArchive];
            return [self populateArchiveError:error fallback:@"Unable to enumerate archive entries."];
        }

        if ([self shouldIndexEntry:entry]) {
            const char *path = archive_entry_pathname(entry);
            [entryPaths addObject:[NSString stringWithUTF8String:path]];
        }

        if (archive_read_data_skip(self.archiveHandle) != ARCHIVE_OK) {
            [self closeArchive];
            return [self populateArchiveError:error fallback:@"Unable to skip archive entry data."];
        }
    }

    self.entryPaths = [entryPaths copy];
    [self closeArchive];
    return YES;
}

- (BOOL)openArchive:(NSError * _Nullable * _Nullable)error {
    if (self.archiveHandle != NULL) {
        return YES;
    }

    struct archive *archiveHandle = archive_read_new();
    if (archiveHandle == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:YRLibArchiveReaderErrorDomain
                                         code:YRLibArchiveReaderErrorOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to allocate libarchive reader."}];
        }
        return NO;
    }

    archive_read_support_format_all(archiveHandle);
    archive_read_support_filter_all(archiveHandle);

    int openResult = ARCHIVE_OK;
    if (self.archiveURL != nil) {
        openResult = archive_read_open_filename(archiveHandle, self.archiveURL.fileSystemRepresentation, 64 * 1024);
    } else {
        archive_read_set_callback_data(archiveHandle, (__bridge void *)self);
        archive_read_set_open_callback(archiveHandle, YRLibArchiveOpenCallback);
        archive_read_set_read_callback(archiveHandle, YRLibArchiveReadCallback);
        archive_read_set_seek_callback(archiveHandle, YRLibArchiveSeekCallback);
        archive_read_set_skip_callback(archiveHandle, YRLibArchiveSkipCallback);
        archive_read_set_close_callback(archiveHandle, YRLibArchiveCloseCallback);
        openResult = archive_read_open1(archiveHandle);
    }

    if (openResult != ARCHIVE_OK) {
        self.archiveHandle = archiveHandle;
        BOOL populated = [self populateArchiveError:error fallback:@"Unable to open archive."];
        [self closeArchive];
        return populated;
    }

    self.archiveHandle = archiveHandle;
    self.nextReadableEntryIndex = 0;
    self.currentOffset = 0;
    self.currentReadBuffer = nil;
    return YES;
}

- (void)closeArchive {
    if (self.archiveHandle != NULL) {
        archive_read_free(self.archiveHandle);
        self.archiveHandle = NULL;
    }

    self.nextReadableEntryIndex = 0;
    self.currentOffset = 0;
    self.currentReadBuffer = nil;
}

- (BOOL)seekToEntryAtIndex:(NSInteger)targetIndex error:(NSError * _Nullable * _Nullable)error {
    if (self.archiveHandle == NULL && ![self openArchive:error]) {
        return NO;
    }

    if (self.nextReadableEntryIndex > targetIndex) {
        [self closeArchive];
        if (![self openArchive:error]) {
            return NO;
        }
    }

    struct archive_entry *entry = NULL;
    while (self.nextReadableEntryIndex < targetIndex) {
        int result = archive_read_next_header(self.archiveHandle, &entry);
        if (result != ARCHIVE_OK) {
            return [self populateArchiveError:error fallback:@"Unable to seek within archive."];
        }

        if ([self shouldIndexEntry:entry]) {
            self.nextReadableEntryIndex += 1;
        }

        if (archive_read_data_skip(self.archiveHandle) != ARCHIVE_OK) {
            return [self populateArchiveError:error fallback:@"Unable to skip archive data while seeking."];
        }
    }

    return YES;
}

- (nullable NSData *)readCurrentEntry:(NSError * _Nullable * _Nullable)error {
    struct archive_entry *entry = NULL;

    while (YES) {
        int result = archive_read_next_header(self.archiveHandle, &entry);
        if (result != ARCHIVE_OK) {
            [self populateArchiveError:error fallback:@"Unable to read archive entry."];
            return nil;
        }

        if (![self shouldIndexEntry:entry]) {
            if (archive_read_data_skip(self.archiveHandle) != ARCHIVE_OK) {
                [self populateArchiveError:error fallback:@"Unable to skip non-page archive entry."];
                return nil;
            }
            continue;
        }

        la_int64_t size = archive_entry_size(entry);
        if (size < 0 || size > NSIntegerMax) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:YRLibArchiveReaderErrorDomain
                                             code:YRLibArchiveReaderErrorReadFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Archive entry size is invalid."}];
            }
            return nil;
        }

        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)size];
        NSUInteger bytesRead = 0;

        while (bytesRead < (NSUInteger)size) {
            la_ssize_t chunk = archive_read_data(
                self.archiveHandle,
                ((uint8_t *)data.mutableBytes) + bytesRead,
                (NSUInteger)size - bytesRead
            );

            if (chunk < 0) {
                [self populateArchiveError:error fallback:@"Unable to extract archive entry data."];
                return nil;
            }

            if (chunk == 0) {
                break;
            }

            bytesRead += (NSUInteger)chunk;
        }

        if (bytesRead < (NSUInteger)size) {
            os_log_error(OS_LOG_DEFAULT,
                         "YRLibArchiveReader: incomplete read — expected %lu bytes, got %lu (entry index %ld)",
                         (unsigned long)size, (unsigned long)bytesRead, (long)(self.nextReadableEntryIndex));
            [data setLength:bytesRead];
        }

        self.nextReadableEntryIndex += 1;
        return data;
    }
}

- (BOOL)shouldIndexEntry:(struct archive_entry *)entry {
    const char *path = archive_entry_pathname(entry);
    la_int64_t size = archive_entry_size(entry);
    return path != NULL && path[0] != '\0' && size > 0;
}

- (BOOL)populateArchiveError:(NSError * _Nullable * _Nullable)error fallback:(NSString *)fallback {
    if (error == NULL) {
        return NO;
    }

    NSString *message = fallback;
    if (self.archiveHandle != NULL) {
        const char *errorString = archive_error_string(self.archiveHandle);
        if (errorString != NULL && errorString[0] != '\0') {
            message = [NSString stringWithUTF8String:errorString];
        }
    }

    *error = [NSError errorWithDomain:YRLibArchiveReaderErrorDomain
                                 code:YRLibArchiveReaderErrorReadFailed
                             userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

@end

static YRLibArchiveReader *YRLibArchiveReaderFromClientData(void *clientData) {
    return (__bridge YRLibArchiveReader *)clientData;
}

static int YRLibArchiveOpenCallback(struct archive *archive, void *clientData) {
    YRLibArchiveReader *reader = YRLibArchiveReaderFromClientData(clientData);
    reader.currentOffset = 0;
    reader.currentReadBuffer = nil;
    return ARCHIVE_OK;
}

static la_ssize_t YRLibArchiveReadCallback(struct archive *archive, void *clientData, const void **buffer) {
    YRLibArchiveReader *reader = YRLibArchiveReaderFromClientData(clientData);
    NSError *error = nil;
    NSData *data = [reader.dataSource readDataAtOffset:reader.currentOffset length:64 * 1024 error:&error];
    if (data == nil) {
        NSString *message = error.localizedDescription ?: @"Unable to read remote archive data.";
        archive_set_error(archive, -1, "%s", message.UTF8String);
        return -1;
    }

    if (data.length == 0) {
        reader.currentReadBuffer = nil;
        *buffer = NULL;
        return 0;
    }

    reader.currentReadBuffer = data;
    *buffer = reader.currentReadBuffer.bytes;
    reader.currentOffset += (la_int64_t)reader.currentReadBuffer.length;
    return (la_ssize_t)reader.currentReadBuffer.length;
}

static la_int64_t YRLibArchiveSkipCallback(struct archive *archive, void *clientData, la_int64_t request) {
    YRLibArchiveReader *reader = YRLibArchiveReaderFromClientData(clientData);
    la_int64_t nextOffset = reader.currentOffset + request;
    nextOffset = MAX(0, MIN(nextOffset, (la_int64_t)reader.dataSource.archiveSize));
    la_int64_t skipped = nextOffset - reader.currentOffset;
    reader.currentOffset = nextOffset;
    reader.currentReadBuffer = nil;
    return skipped;
}

static la_int64_t YRLibArchiveSeekCallback(struct archive *archive, void *clientData, la_int64_t offset, int whence) {
    YRLibArchiveReader *reader = YRLibArchiveReaderFromClientData(clientData);
    la_int64_t baseOffset = 0;

    switch (whence) {
        case SEEK_SET:
            baseOffset = 0;
            break;
        case SEEK_CUR:
            baseOffset = reader.currentOffset;
            break;
        case SEEK_END:
            baseOffset = (la_int64_t)reader.dataSource.archiveSize;
            break;
        default:
            archive_set_error(archive, -1, "%s", "Unsupported remote archive seek mode.");
            return -1;
    }

    la_int64_t nextOffset = baseOffset + offset;
    if (nextOffset < 0 || nextOffset > (la_int64_t)reader.dataSource.archiveSize) {
        archive_set_error(archive, -1, "%s", "Remote archive seek is out of bounds.");
        return -1;
    }

    reader.currentOffset = nextOffset;
    reader.currentReadBuffer = nil;
    return nextOffset;
}

static int YRLibArchiveCloseCallback(struct archive *archive, void *clientData) {
    YRLibArchiveReader *reader = YRLibArchiveReaderFromClientData(clientData);
    reader.currentReadBuffer = nil;
    return ARCHIVE_OK;
}

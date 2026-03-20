#import <Foundation/Foundation.h>
#include <stddef.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef long long la_int64_t;
typedef long long la_ssize_t;

struct archive;
struct archive_entry;

typedef int archive_open_callback(struct archive *archive, void *client_data);
typedef la_ssize_t archive_read_callback(struct archive *archive, void *client_data, const void **buffer);
typedef la_int64_t archive_skip_callback(struct archive *archive, void *client_data, la_int64_t request);
typedef la_int64_t archive_seek_callback(struct archive *archive, void *client_data, la_int64_t offset, int whence);
typedef int archive_close_callback(struct archive *archive, void *client_data);

struct archive *archive_read_new(void);
int archive_read_support_format_all(struct archive *archive);
int archive_read_support_filter_all(struct archive *archive);
int archive_read_open_filename(struct archive *archive, const char *filename, size_t block_size);
int archive_read_open2(struct archive *archive, void *client_data, archive_open_callback *open_callback, archive_read_callback *read_callback, archive_skip_callback *skip_callback, archive_close_callback *close_callback);
int archive_read_set_callback_data(struct archive *archive, void *client_data);
int archive_read_set_open_callback(struct archive *archive, archive_open_callback *open_callback);
int archive_read_set_read_callback(struct archive *archive, archive_read_callback *read_callback);
int archive_read_set_seek_callback(struct archive *archive, archive_seek_callback *seek_callback);
int archive_read_set_skip_callback(struct archive *archive, archive_skip_callback *skip_callback);
int archive_read_set_close_callback(struct archive *archive, archive_close_callback *close_callback);
int archive_read_open1(struct archive *archive);
int archive_read_next_header(struct archive *archive, struct archive_entry **entry);
la_ssize_t archive_read_data(struct archive *archive, void *buffer, size_t length);
int archive_read_data_skip(struct archive *archive);
int archive_read_free(struct archive *archive);
int archive_errno(struct archive *archive);
const char *archive_error_string(struct archive *archive);
void archive_set_error(struct archive *archive, int error_number, const char *fmt, ...);
const char *archive_entry_pathname(struct archive_entry *entry);
la_int64_t archive_entry_size(struct archive_entry *entry);

#ifdef __cplusplus
}
#endif

#define ARCHIVE_OK 0
#define ARCHIVE_EOF 1

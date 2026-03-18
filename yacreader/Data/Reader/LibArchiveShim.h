#import <Foundation/Foundation.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef long long la_int64_t;
typedef long long la_ssize_t;

struct archive;
struct archive_entry;

struct archive *archive_read_new(void);
int archive_read_support_format_all(struct archive *archive);
int archive_read_support_filter_all(struct archive *archive);
int archive_read_open_filename(struct archive *archive, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *archive, struct archive_entry **entry);
la_ssize_t archive_read_data(struct archive *archive, void *buffer, size_t length);
int archive_read_data_skip(struct archive *archive);
int archive_read_free(struct archive *archive);
int archive_errno(struct archive *archive);
const char *archive_error_string(struct archive *archive);
const char *archive_entry_pathname(struct archive_entry *entry);
la_int64_t archive_entry_size(struct archive_entry *entry);

#ifdef __cplusplus
}
#endif

#define ARCHIVE_OK 0
#define ARCHIVE_EOF 1

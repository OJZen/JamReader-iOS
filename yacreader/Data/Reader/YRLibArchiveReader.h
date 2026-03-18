#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YRLibArchiveReader : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString *> *entryPaths;

- (nullable instancetype)initWithArchiveURL:(NSURL *)archiveURL error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable NSData *)dataForEntryAtIndex:(NSInteger)index error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

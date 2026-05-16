#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface YRMuPDFDocument : NSObject

@property (nonatomic, readonly) NSInteger pageCount;

+ (BOOL)isAvailable;

- (nullable instancetype)initWithURL:(NSURL *)url error:(NSError **)error NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(url:));
- (instancetype)init NS_UNAVAILABLE;

- (nullable UIImage *)renderPageAtIndex:(NSInteger)pageIndex
                           maxPixelSize:(NSInteger)maxPixelSize
                                  error:(NSError **)error NS_SWIFT_NAME(renderPage(at:maxPixelSize:));

@end

NS_ASSUME_NONNULL_END

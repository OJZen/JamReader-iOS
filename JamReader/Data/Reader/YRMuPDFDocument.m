#import "YRMuPDFDocument.h"
#import <math.h>

#if __has_include(<mupdf/fitz.h>)
#import <mupdf/fitz.h>
#define JR_HAS_MUPDF 1
#else
#define JR_HAS_MUPDF 0
#endif

#if JR_HAS_MUPDF
static const size_t YRMuPDFStoreLimit = 64 * 1024 * 1024;
#endif

static NSString * const YRMuPDFDocumentErrorDomain = @"ooou.fun.jamreader.mupdf";

typedef NS_ENUM(NSInteger, YRMuPDFDocumentErrorCode) {
    YRMuPDFDocumentErrorUnavailable = 1,
    YRMuPDFDocumentErrorOpenFailed = 2,
    YRMuPDFDocumentErrorPageOutOfRange = 3,
    YRMuPDFDocumentErrorRenderFailed = 4,
    YRMuPDFDocumentErrorImageCreationFailed = 5
};

static NSError *YRMuPDFError(YRMuPDFDocumentErrorCode code, NSString *message) {
    return [NSError errorWithDomain:YRMuPDFDocumentErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface YRMuPDFDocument ()
#if JR_HAS_MUPDF
@property (nonatomic) fz_context *context;
@property (nonatomic) fz_document *document;
#endif
@property (nonatomic, readwrite) NSInteger pageCount;
@end

@implementation YRMuPDFDocument

+ (BOOL)isAvailable {
#if JR_HAS_MUPDF
    return YES;
#else
    return NO;
#endif
}

- (nullable instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

#if JR_HAS_MUPDF
    _context = fz_new_context(NULL, NULL, YRMuPDFStoreLimit);
    if (!_context) {
        if (error) {
            *error = YRMuPDFError(YRMuPDFDocumentErrorOpenFailed, @"MuPDF could not create a rendering context.");
        }
        return nil;
    }

    fz_register_document_handlers(_context);

    BOOL didOpen = NO;
    fz_try(_context) {
        _document = fz_open_document(_context, url.fileSystemRepresentation);
        fz_layout_document(_context, _document, 450, 640, 12);
        _pageCount = fz_count_pages(_context, _document);
        didOpen = _pageCount > 0;
    }
    fz_catch(_context) {
        didOpen = NO;
    }

    if (!didOpen) {
        if (_document) {
            fz_drop_document(_context, _document);
            _document = NULL;
        }
        if (_context) {
            fz_drop_context(_context);
            _context = NULL;
        }
        if (error) {
            *error = YRMuPDFError(YRMuPDFDocumentErrorOpenFailed, @"MuPDF could not open this document.");
        }
        return nil;
    }

    return self;
#else
    if (error) {
        *error = YRMuPDFError(YRMuPDFDocumentErrorUnavailable, @"MuPDF is not linked into this build.");
    }
    return nil;
#endif
}

- (void)dealloc {
#if JR_HAS_MUPDF
    if (_document) {
        fz_drop_document(_context, _document);
        _document = NULL;
    }
    if (_context) {
        fz_drop_context(_context);
        _context = NULL;
    }
#endif
}

- (nullable UIImage *)renderPageAtIndex:(NSInteger)pageIndex
                           maxPixelSize:(NSInteger)maxPixelSize
                                  error:(NSError **)error {
#if JR_HAS_MUPDF
    if (pageIndex < 0 || pageIndex >= self.pageCount) {
        if (error) {
            *error = YRMuPDFError(YRMuPDFDocumentErrorPageOutOfRange, @"The requested MuPDF page is out of range.");
        }
        return nil;
    }

    __block fz_page *page = NULL;
    __block fz_pixmap *pixmap = NULL;
    BOOL didRender = NO;

    fz_try(_context) {
        page = fz_load_page(_context, _document, (int)pageIndex);
        fz_rect bounds = fz_bound_page(_context, page);
        float pageWidth = fmaxf(bounds.x1 - bounds.x0, 1.0f);
        float pageHeight = fmaxf(bounds.y1 - bounds.y0, 1.0f);
        float largestPageDimension = fmaxf(pageWidth, pageHeight);
        float targetDimension = (float)MAX(maxPixelSize, 1);
        float scale = fmaxf(targetDimension / largestPageDimension, 0.1f);
        fz_matrix transform = fz_scale(scale, scale);
        pixmap = fz_new_pixmap_from_page(_context, page, transform, fz_device_rgb(_context), 0);
        fz_drop_page(_context, page);
        page = NULL;
        didRender = pixmap != NULL;
    }
    fz_catch(_context) {
        if (page) {
            fz_drop_page(_context, page);
            page = NULL;
        }
        didRender = NO;
    }

    if (!didRender || !pixmap) {
        if (error) {
            *error = YRMuPDFError(YRMuPDFDocumentErrorRenderFailed, @"MuPDF could not render this page.");
        }
        return nil;
    }

    UIImage *image = [self imageFromPixmap:pixmap];
    fz_drop_pixmap(_context, pixmap);

    if (!image && error) {
        *error = YRMuPDFError(YRMuPDFDocumentErrorImageCreationFailed, @"MuPDF rendered the page, but the bitmap could not be converted.");
    }
    return image;
#else
    if (error) {
        *error = YRMuPDFError(YRMuPDFDocumentErrorUnavailable, @"MuPDF is not linked into this build.");
    }
    return nil;
#endif
}

#if JR_HAS_MUPDF
- (nullable UIImage *)imageFromPixmap:(fz_pixmap *)pixmap {
    int width = fz_pixmap_width(_context, pixmap);
    int height = fz_pixmap_height(_context, pixmap);
    int stride = fz_pixmap_stride(_context, pixmap);
    int components = fz_pixmap_components(_context, pixmap);
    unsigned char *samples = fz_pixmap_samples(_context, pixmap);

    if (width <= 0 || height <= 0 || stride <= 0 || components < 3 || samples == NULL) {
        return nil;
    }

    size_t byteCount = (size_t)stride * (size_t)height;
    NSData *bitmapData = [NSData dataWithBytes:samples length:byteCount];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)bitmapData);
    if (!provider) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo alphaInfo = (CGBitmapInfo)(components >= 4 ? kCGImageAlphaLast : kCGImageAlphaNone);
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | alphaInfo;

    CGImageRef cgImage = CGImageCreate((size_t)width,
                                       (size_t)height,
                                       8,
                                       (size_t)(components * 8),
                                       (size_t)stride,
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       false,
                                       kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    if (!cgImage) {
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:cgImage scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return image;
}
#endif

@end

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

NS_ASSUME_NONNULL_BEGIN
// Build a passage beginning at a clicked UTF-16 offset, preserving following blocks.
FOUNDATION_EXPORT NSString * _Nullable GRReadingSuffix(NSArray<NSString *> *blocks, NSUInteger blockIndex, NSUInteger offset);
// Exact highlighted text wins over the remembered click from the same app.
FOUNDATION_EXPORT NSString * _Nullable GRPreferredReadingText(NSString * _Nullable selection,
                                                               NSString * _Nullable clickedText,
                                                               BOOL clickedAppMatches);
// Read the clicked accessibility text and following blocks in its document/scroll area.
FOUNDATION_EXPORT NSString * _Nullable GRReadingTextAtElement(AXUIElementRef element, CGPoint point);
NS_ASSUME_NONNULL_END

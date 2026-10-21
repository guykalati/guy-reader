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
// Find the topmost normal application window PID at a Quartz screen coordinate.
FOUNDATION_EXPORT pid_t GRAppPIDAtScreenPoint(CGPoint point, pid_t excludePID);
// Wake accessibility and extract reading text at a Quartz screen coordinate for a target app PID.
FOUNDATION_EXPORT NSString * _Nullable GRExtractReadingTextAtScreenPoint(CGPoint point, pid_t targetPID);
NS_ASSUME_NONNULL_END

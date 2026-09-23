#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "../src/reading_origin.h"

int main(void) {
    @autoreleasepool {
        pid_t targetPid = 0;
        for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if ([app.bundleIdentifier isEqualToString:@"com.google.antigravity"]) {
                targetPid = app.processIdentifier;
                break;
            }
        }
        if (!targetPid) return 1;

        AXUIElementRef appElem = AXUIElementCreateApplication(targetPid);
        AXUIElementSetAttributeValue(appElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);

        CFTypeRef focusedWindow = NULL;
        AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute, &focusedWindow);
        if (!focusedWindow) AXUIElementCopyAttributeValue(appElem, kAXMainWindowAttribute, &focusedWindow);

        if (focusedWindow) {
            CFTypeRef posVal = NULL, sizeVal = NULL;
            CGPoint winPos; CGSize winSize;
            AXUIElementCopyAttributeValue((AXUIElementRef)focusedWindow, kAXPositionAttribute, &posVal);
            AXUIElementCopyAttributeValue((AXUIElementRef)focusedWindow, kAXSizeAttribute, &sizeVal);
            if (posVal && sizeVal) {
                AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &winPos);
                AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &winSize);

                CGPoint testPoint = CGPointMake(winPos.x + winSize.width / 2.0, winPos.y + winSize.height / 2.0);
                AXUIElementRef system = AXUIElementCreateSystemWide();
                AXUIElementRef hit = NULL;
                AXUIElementCopyElementAtPosition(system, testPoint.x, testPoint.y, &hit);
                if (hit) {
                    NSString *res = GRReadingTextAtElement(hit, testPoint);
                    printf("Result from GRReadingTextAtElement: %p (length %lu)\n", res, (unsigned long)res.length);
                    if (res) printf("Content: %s\n", [res substringToIndex:MIN((NSUInteger)100, res.length)].UTF8String);
                    CFRelease(hit);
                }
                CFRelease(system);
            }
            if (posVal) CFRelease(posVal);
            if (sizeVal) CFRelease(sizeVal);
            CFRelease(focusedWindow);
        }
        CFRelease(appElem);
    }
    return 0;
}

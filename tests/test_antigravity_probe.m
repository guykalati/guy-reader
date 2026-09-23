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
        if (!targetPid) {
            printf("Antigravity not found!\n");
            return 1;
        }
        printf("Found Antigravity PID: %d\n", targetPid);

        AXUIElementRef appElem = AXUIElementCreateApplication(targetPid);
        AXUIElementSetAttributeValue(appElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);

        CFTypeRef focusedWindow = NULL;
        AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute, &focusedWindow);
        if (!focusedWindow) {
            AXUIElementCopyAttributeValue(appElem, kAXMainWindowAttribute, &focusedWindow);
        }
        printf("Antigravity window: %p\n", focusedWindow);

        if (focusedWindow) {
            CFTypeRef title = NULL;
            AXUIElementCopyAttributeValue((AXUIElementRef)focusedWindow, kAXTitleAttribute, &title);
            printf("Window Title: %s\n", title ? [(__bridge id)title description].UTF8String : "none");
            if (title) CFRelease(title);

            // Check window frame
            CFTypeRef posVal = NULL, sizeVal = NULL;
            CGPoint winPos; CGSize winSize;
            AXUIElementCopyAttributeValue((AXUIElementRef)focusedWindow, kAXPositionAttribute, &posVal);
            AXUIElementCopyAttributeValue((AXUIElementRef)focusedWindow, kAXSizeAttribute, &sizeVal);
            if (posVal && sizeVal) {
                AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &winPos);
                AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &winSize);
                printf("Window Frame: (%.1f, %.1f, %.1f, %.1f)\n", winPos.x, winPos.y, winSize.width, winSize.height);

                // Let's test a point in the middle of the window:
                CGPoint testPoint = CGPointMake(winPos.x + winSize.width / 2.0, winPos.y + winSize.height / 2.0);
                printf("Testing hit at center: (%.1f, %.1f)\n", testPoint.x, testPoint.y);

                AXUIElementRef system = AXUIElementCreateSystemWide();
                AXUIElementRef hit = NULL;
                AXError err = AXUIElementCopyElementAtPosition(system, testPoint.x, testPoint.y, &hit);
                printf("System hit-test at center: err=%d, hit=%p\n", err, hit);

                if (hit) {
                    CFTypeRef hRole = NULL, hVal = NULL;
                    AXUIElementCopyAttributeValue(hit, kAXRoleAttribute, &hRole);
                    AXUIElementCopyAttributeValue(hit, kAXValueAttribute, &hVal);
                    printf("Hit Role: %s\n", hRole ? [(__bridge id)hRole description].UTF8String : "none");
                    printf("Hit Value: %s\n", hVal ? [(__bridge id)hVal description].UTF8String : "none");

                    NSString *txt = GRReadingTextAtElement(hit, testPoint);
                    printf("GRReadingTextAtElement length: %lu\n", (unsigned long)txt.length);
                    if (txt.length) {
                        printf("GRReadingTextAtElement snippet: %s\n",
                               [txt substringToIndex:MIN((NSUInteger)160, txt.length)].UTF8String);
                    }
                    if (hRole) CFRelease(hRole);
                    if (hVal) CFRelease(hVal);
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

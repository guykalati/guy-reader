#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "../src/reading_origin.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
        printf("Front app: %s (pid: %d, bundle: %s)\n",
               front.localizedName.UTF8String ?: "none",
               front.processIdentifier,
               front.bundleIdentifier.UTF8String ?: "none");

        // Wake accessibility on front app
        AXUIElementRef frontElem = AXUIElementCreateApplication(front.processIdentifier);
        if (frontElem) {
            AXUIElementSetAttributeValue(frontElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
            CFRelease(frontElem);
        }

        NSPoint mouse = [NSEvent mouseLocation];
        CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
        CGPoint point = CGPointMake(mouse.x, top - mouse.y);
        printf("Mouse point: (%.1f, %.1f)\n", point.x, point.y);

        AXUIElementRef system = AXUIElementCreateSystemWide();
        AXUIElementRef hit = NULL;
        AXError err = AXUIElementCopyElementAtPosition(system, point.x, point.y, &hit);
        printf("CopyElementAtPosition: err=%d, hit=%p\n", err, hit);
        if (hit) {
            CFTypeRef role = NULL;
            AXUIElementCopyAttributeValue(hit, kAXRoleAttribute, &role);
            printf("Hit Role: %s\n", role ? [(__bridge id)role description].UTF8String : "none");
            if (role) CFRelease(role);

            CFTypeRef children = NULL;
            AXUIElementCopyAttributeValue(hit, kAXChildrenAttribute, &children);
            if (children && [(__bridge id)children isKindOfClass:[NSArray class]]) {
                NSArray *arr = (__bridge NSArray *)children;
                printf("Hit has %lu children\n", (unsigned long)arr.count);
                for (NSUInteger i = 0; i < MIN((NSUInteger)5, arr.count); i++) {
                    AXUIElementRef c = (__bridge AXUIElementRef)arr[i];
                    CFTypeRef cRole = NULL, cVal = NULL;
                    AXUIElementCopyAttributeValue(c, kAXRoleAttribute, &cRole);
                    AXUIElementCopyAttributeValue(c, kAXValueAttribute, &cVal);
                    printf("  Child %lu: role=%s, val=%s\n",
                           (unsigned long)i,
                           cRole ? [(__bridge id)cRole description].UTF8String : "none",
                           cVal ? [(__bridge id)cVal description].UTF8String : "none");
                    if (cRole) CFRelease(cRole);
                    if (cVal) CFRelease(cVal);
                }
            }
            if (children) CFRelease(children);

            NSString *resultText = GRReadingTextAtElement(hit, point);
            printf("GRReadingTextAtElement result length: %lu\n", (unsigned long)resultText.length);
            if (resultText.length > 0) {
                printf("GRReadingTextAtElement snippet: %s\n",
                       [resultText substringToIndex:MIN((NSUInteger)120, resultText.length)].UTF8String);
            }

            CFRelease(hit);
        }
        CFRelease(system);
    }
    return 0;
}

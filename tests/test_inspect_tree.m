#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

void printElementTree(AXUIElementRef elem, int depth) {
    if (depth > 6) return;
    CFTypeRef role = NULL, val = NULL, title = NULL, desc = NULL;
    AXUIElementCopyAttributeValue(elem, kAXRoleAttribute, &role);
    AXUIElementCopyAttributeValue(elem, kAXValueAttribute, &val);
    AXUIElementCopyAttributeValue(elem, kAXTitleAttribute, &title);
    AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute, &desc);

    char indent[32] = {0};
    for (int i = 0; i < depth * 2; i++) indent[i] = ' ';

    printf("%sRole: %s | Val: %s | Title: %s | Desc: %s\n",
           indent,
           role ? [(__bridge id)role description].UTF8String : "none",
           val ? [(__bridge id)val description].UTF8String : "none",
           title ? [(__bridge id)title description].UTF8String : "none",
           desc ? [(__bridge id)desc description].UTF8String : "none");

    if (role) CFRelease(role);
    if (val) CFRelease(val);
    if (title) CFRelease(title);
    if (desc) CFRelease(desc);

    CFTypeRef children = NULL;
    AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute, &children);
    if (children && [(__bridge id)children isKindOfClass:[NSArray class]]) {
        NSArray *arr = (__bridge NSArray *)children;
        for (NSUInteger i = 0; i < arr.count; i++) {
            printElementTree((__bridge AXUIElementRef)arr[i], depth + 1);
        }
    }
    if (children) CFRelease(children);
}

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
                    printf("--- Tree from Hit Element ---\n");
                    printElementTree(hit, 0);
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

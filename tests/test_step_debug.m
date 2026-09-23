#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

static id attribute(AXUIElementRef element, CFStringRef name) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, name, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}

static NSString *extractString(id val) {
    if (!val) return nil;
    if ([val isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? (NSString *)val : nil;
    }
    return nil;
}

static NSString *textValue(AXUIElementRef element) {
    if (!element) return nil;
    NSString *role = attribute(element, kAXRoleAttribute);
    if ([role isEqualToString:@"AXButton"] || [role isEqualToString:@"AXToolbar"] ||
        [role isEqualToString:@"AXMenuBar"] || [role isEqualToString:@"AXMenu"] ||
        [role isEqualToString:@"AXScrollBar"] || [role isEqualToString:@"AXSlider"]) return nil;
    NSString *str = extractString(attribute(element, kAXValueAttribute));
    if (str) return str;
    str = extractString(attribute(element, kAXTitleAttribute));
    if (str) return str;
    str = extractString(attribute(element, kAXDescriptionAttribute));
    if (str) return str;
    return nil;
}

static void collect(AXUIElementRef element, NSMutableArray *elements, NSMutableArray *texts, NSUInteger depth, NSUInteger *budget) {
    if (!element || !*budget || depth > 40) return;
    (*budget)--;
    NSString *role = attribute(element, kAXRoleAttribute);
    if ([role isEqualToString:@"AXButton"] || [role isEqualToString:@"AXToolbar"] ||
        [role isEqualToString:@"AXMenuBar"] || [role isEqualToString:@"AXMenu"] ||
        [role isEqualToString:@"AXScrollBar"] || [role isEqualToString:@"AXSlider"]) return;

    NSString *text = textValue(element);
    id children = attribute(element, kAXChildrenAttribute);
    BOOL hasChildren = [children isKindOfClass:[NSArray class]] && [(NSArray *)children count] > 0;

    if (text && (!hasChildren || [role isEqualToString:(__bridge NSString *)kAXTextAreaRole] || [role isEqualToString:(__bridge NSString *)kAXTextFieldRole])) {
        [elements addObject:(__bridge id)element];
        [texts addObject:text];
        return;
    }

    if (hasChildren) {
        for (id child in (NSArray *)children) {
            collect((__bridge AXUIElementRef)child, elements, texts, depth + 1, budget);
        }
    } else if (text) {
        [elements addObject:(__bridge id)element];
        [texts addObject:text];
    }
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
                    printf("Hit element: %p role: %s\n", hit, [attribute(hit, kAXRoleAttribute) UTF8String]);

                    // Step 1: walk up to root
                    id root = (__bridge id)hit;
                    for (NSUInteger i = 0; i < 10; i++) {
                        id next = attribute((__bridge AXUIElementRef)root, kAXParentAttribute);
                        if (!next) break;
                        NSString *pRole = attribute((__bridge AXUIElementRef)next, kAXRoleAttribute);
                        printf("Parent %lu: role=%s\n", i, pRole.UTF8String);
                        if ([pRole isEqualToString:@"AXWindow"] || [pRole isEqualToString:@"AXApplication"]) break;
                        root = next;
                        if ([pRole isEqualToString:@"AXScrollArea"] || [pRole isEqualToString:@"AXWebArea"]) break;
                    }
                    printf("Root element: %p role: %s\n", (__bridge void*)root, [attribute((__bridge AXUIElementRef)root, kAXRoleAttribute) UTF8String]);

                    NSMutableArray *elements = [NSMutableArray array], *texts = [NSMutableArray array];
                    NSUInteger budget = 3000;
                    collect((__bridge AXUIElementRef)root, elements, texts, 0, &budget);
                    printf("Collected %lu elements, %lu texts\n", elements.count, texts.count);
                    for (NSUInteger i = 0; i < MIN((NSUInteger)5, texts.count); i++) {
                        printf("  Text %lu: %s\n", i, [texts[i] substringToIndex:MIN((NSUInteger)60, [texts[i] length])].UTF8String);
                    }
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

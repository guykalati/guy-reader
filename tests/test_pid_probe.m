#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
int main() {
    pid_t targetPid = 0;
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([app.bundleIdentifier isEqualToString:@"com.google.antigravity"]) { targetPid = app.processIdentifier; break; }
    }
    AXUIElementRef appElem = AXUIElementCreateApplication(targetPid);
    CFTypeRef win = NULL;
    AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute, &win);
    if (!win) AXUIElementCopyAttributeValue(appElem, kAXMainWindowAttribute, &win);
    CGPoint winPos; CGSize winSize;
    CFTypeRef pv=NULL, sv=NULL;
    AXUIElementCopyAttributeValue((AXUIElementRef)win, kAXPositionAttribute, &pv);
    AXUIElementCopyAttributeValue((AXUIElementRef)win, kAXSizeAttribute, &sv);
    AXValueGetValue((AXValueRef)pv, kAXValueCGPointType, &winPos);
    AXValueGetValue((AXValueRef)sv, kAXValueCGSizeType, &winSize);
    CGPoint pt = CGPointMake(winPos.x + winSize.width/2.0, winPos.y + winSize.height/2.0);
    AXUIElementRef sys = AXUIElementCreateSystemWide(), hit = NULL;
    AXUIElementCopyElementAtPosition(sys, pt.x, pt.y, &hit);
    pid_t hitPid = 0;
    AXUIElementGetPid(hit, &hitPid);
    printf("Target PID: %d, Hit PID: %d\n", targetPid, hitPid);
    NSRunningApplication *ha = [NSRunningApplication runningApplicationWithProcessIdentifier:hitPid];
    printf("HitApp: %p, bundle: %s\n", ha, ha.bundleIdentifier.UTF8String ?: "nil");
    return 0;
}

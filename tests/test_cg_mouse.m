#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

int main() {
    @autoreleasepool {
        CGEventRef ev = CGEventCreate(NULL);
        CGPoint cgPoint = CGEventGetLocation(ev);
        CFRelease(ev);

        NSPoint mouse = [NSEvent mouseLocation];
        CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
        CGPoint manualPoint = CGPointMake(mouse.x, top - mouse.y);

        printf("CGEvent location:   (%.1f, %.1f)\n", cgPoint.x, cgPoint.y);
        printf("Manual point:       (%.1f, %.1f)\n", manualPoint.x, manualPoint.y);
        printf("Diff: (%.1f, %.1f)\n", cgPoint.x - manualPoint.x, cgPoint.y - manualPoint.y);
    }
    return 0;
}

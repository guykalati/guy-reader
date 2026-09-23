#import <Cocoa/Cocoa.h>

int main(void) {
    @autoreleasepool {
        for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
                printf("PID: %6d | Bundle: %-40s | Name: %s\n",
                       app.processIdentifier,
                       app.bundleIdentifier.UTF8String ?: "none",
                       app.localizedName.UTF8String ?: "none");
            }
        }
    }
    return 0;
}

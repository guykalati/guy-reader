#import <Cocoa/Cocoa.h>

int main() {
    @autoreleasepool {
        NSArray *screens = [NSScreen screens];
        printf("Screen count: %lu\n", (unsigned long)screens.count);
        for (NSUInteger i = 0; i < screens.count; i++) {
            NSScreen *s = screens[i];
            NSRect f = s.frame;
            NSRect vf = s.visibleFrame;
            printf("Screen %lu: frame=(%.1f, %.1f, %.1f, %.1f), visible=(%.1f, %.1f, %.1f, %.1f)\n",
                   (unsigned long)i, f.origin.x, f.origin.y, f.size.width, f.size.height,
                   vf.origin.x, vf.origin.y, vf.size.width, vf.size.height);
        }
    }
    return 0;
}

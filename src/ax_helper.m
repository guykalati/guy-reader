#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import "reading_origin.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "Usage: ax_helper <x> <y> [pid]\n");
            return 1;
        }
        double x = atof(argv[1]);
        double y = atof(argv[2]);
        pid_t pid = (argc >= 4) ? (pid_t)atoi(argv[3]) : 0;
        CGPoint pt = CGPointMake(x, y);
        if (pid <= 0) {
            pid = GRAppPIDAtScreenPoint(pt, getpid());
        }
        BOOL trusted = AXIsProcessTrusted() ? YES : NO;
        NSString *text = GRExtractReadingTextAtScreenPoint(pt, pid);
        NSDictionary *out = @{
            @"trusted": @(trusted),
            @"pid": @(pid),
            @"text": text ?: @""
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
        if (json) {
            fwrite(json.bytes, 1, json.length, stdout);
            fputc('\n', stdout);
        }
    }
    return 0;
}

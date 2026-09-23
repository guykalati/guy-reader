#define main GuyReaderApplicationMain
#import "../src/main.m"
#undef main
#import <objc/runtime.h>

@interface TestPasteboard : NSObject
@property NSString *text;
@property NSInteger revision;
@end
@implementation TestPasteboard
- (NSString *)stringForType:(NSPasteboardType)type { return self.text; }
- (NSInteger)changeCount { return self.revision; }
- (NSInteger)clearContents { self.text = nil; return ++self.revision; }
- (BOOL)setString:(NSString *)text forType:(NSPasteboardType)type { self.text = text; self.revision++; return YES; }
@end
static NSPasteboard *testPasteboard;
static NSPasteboard *isolatedPasteboard(id self, SEL cmd) { return testPasteboard; }

@interface TestSpeech : SpeechEngine
@property BOOL pausedForTest;
@property NSUInteger stops;
@end
@implementation TestSpeech
- (BOOL)isSpeaking { return !self.pausedForTest; }
- (BOOL)isPaused { return self.pausedForTest; }
- (void)stop { self.stops++; }
- (void)pause {}
- (void)resume {}
@end

@interface TestCoordinator : AppDelegate
@property NSString *delivered;
@property NSString *selected;
@property BOOL captured;
@end
@implementation TestCoordinator
- (NSString *)getSelectedTextViaAccessibility:(pid_t)pid { return self.selected; }
- (void)sendTextToWebView:(NSString *)text { self.delivered = text; }
- (void)captureAndSpeak { self.captured = YES; }
@end

int main(void) {
    @autoreleasepool {
        testPasteboard = (id)[TestPasteboard new];
        Method method = class_getClassMethod([NSPasteboard class], @selector(generalPasteboard));
        IMP original = method_setImplementation(method, (IMP)isolatedPasteboard);
        int failures = 0;
        for (NSNumber *paused in @[@NO, @YES]) {
            TestCoordinator *reader = [TestCoordinator new];
            TestSpeech *speech = [TestSpeech new]; speech.pausedForTest = paused.boolValue;
            reader.speechEngine = speech;
            reader.currentReadingText = @"Old passage";
            [testPasteboard clearContents];
            [testPasteboard setString:@"New copied passage" forType:NSPasteboardTypeString];
            [reader readSelectionFromActiveApp];
            if (reader.delivered) {
                fprintf(stderr, "FAIL: Read consumed unrelated clipboard text while %s\n", paused.boolValue ? "paused" : "playing");
                failures++;
            }
            [NSThread sleepForTimeInterval:0.36];
        }
        TestCoordinator *reader = [TestCoordinator new];
        reader.speechEngine = [TestSpeech new];
        [reader deliverTextToReader:@"Selected passage"];
        reader.delivered = nil;
        [reader readSelectionFromActiveApp];
        if (reader.delivered) {
            fprintf(stderr, "FAIL: unchanged clipboard replaced an active selection\n");
            failures++;
        }
        method_setImplementation(method, original);

        if (!failures) puts("Native selection and explicit-paste tests passed (3)");
        return failures ? 1 : 0;
    }
}

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "../src/speech_engine.h"

int g_testsRun = 0;
int g_testsPassed = 0;

#define ASSERT(cond, desc) do { \
    g_testsRun++; \
    if (cond) { \
        printf("  [PASS] %s\n", desc); \
        g_testsPassed++; \
    } else { \
        printf("  [FAIL] %s (line %d)\n", desc, __LINE__); \
    } \
} while(0)

@interface TestSpeechDelegate : NSObject <SpeechEngineDelegate>
@property (nonatomic, assign) NSInteger startCount;
@property (nonatomic, assign) NSInteger finishCount;
@property (nonatomic, assign) NSInteger pauseCount;
@end

@implementation TestSpeechDelegate
- (void)speechDidStartSpeaking {
    self.startCount++;
}
- (void)speechDidFinishSentence {
    self.finishCount++;
}
- (void)speechDidPause {
    self.pauseCount++;
}
@end

// Offline network adapter: fallback tests must not depend on Bing accepting a request.
@interface OfflineTask : NSObject
@property (copy) void (^failure)(void);
@end
@implementation OfflineTask
- (void)resume { if (self.failure) self.failure(); }
- (void)cancel {}
- (void)cancelWithCloseCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason {}
- (void)sendMessage:(NSURLSessionWebSocketMessage *)message completionHandler:(void (^)(NSError *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
    });
}
- (void)receiveMessageWithCompletionHandler:(void (^)(NSURLSessionWebSocketMessage *, NSError *))completion {}
@end
static id offlineSocket(id self, SEL cmd, NSURLRequest *request) { return [OfflineTask new]; }
static id offlineData(id self, SEL cmd, NSURLRequest *request,
                      void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    OfflineTask *task = [OfflineTask new];
    task.failure = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
        });
    };
    return task;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("=== Running SpeechEngine Unit Tests ===\n");

        SpeechEngine *engine = [SpeechEngine sharedInstance];
        ASSERT(engine != nil, "SpeechEngine instance is created");

        // Test R2. Default Voice
        ASSERT([engine.currentVoice isEqualToString:@"apple-evan"], "Default voice is apple-evan out-of-the-box");

        // Test Hebrew Detection
        ASSERT([engine isHebrew:@"שלום עולם"], "Detects pure Hebrew text");
        ASSERT([engine isHebrew:@"Hello שלום world"], "Detects mixed Hebrew text");
        ASSERT(![engine isHebrew:@"Hello world, this is English!"], "English text is not detected as Hebrew");
        ASSERT(![engine isHebrew:@"1234567890 !@#$%^&*()"], "Numbers and symbols are not Hebrew");
        ASSERT(![engine isHebrew:@""], "Empty string is not Hebrew");
        NSString *nilStr = nil;
        ASSERT(![engine isHebrew:nilStr], "Nil string is not Hebrew");

        // Test Speed Rate Clamping
        engine.speedRate = 1.5f;
        ASSERT(fabs(engine.speedRate - 1.5f) < 0.01f, "speedRate updates to 1.5x");
        engine.speedRate = 0.2f;
        ASSERT(fabs(engine.speedRate - 0.5f) < 0.01f, "speedRate clamps underflow to 0.5x (minimum)");
        engine.speedRate = 4.0f;
        ASSERT(fabs(engine.speedRate - 2.5f) < 0.01f, "speedRate clamps overflow to 2.5x (maximum)");
        engine.speedRate = 1.0f;

        // Test Voice Switching & Speak invocations
        [engine speakText:@"Testing Apple Evan default voice." voice:@"apple-evan" rate:1.0f];
        ASSERT([engine.currentVoice isEqualToString:@"apple-evan"], "currentVoice is apple-evan after speakText");
        NSDate *speechDeadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (![engine isSpeaking] && [speechDeadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        ASSERT([engine isSpeaking], "Engine isSpeaking returns YES during speech");

        // Real pause verification
        [engine pause];
        ASSERT(![engine isSpeaking], "pause() sets isSpeaking to NO");

        // Real resume verification
        [engine resume];
        ASSERT([engine isSpeaking], "resume() restores isSpeaking to YES");

        // Stop verification
        [engine stop];
        ASSERT(![engine isSpeaking], "stop() stops speaking immediately");

        // Native Hebrew routes to Edge Avri neural voice; Carmit is permanently eradicated.
        [engine speakText:@"בדיקת קול עברי מקומי" voice:nil rate:1.0f];
        ASSERT([engine.currentVoice isEqualToString:@"edge-he-avri"], "Native Hebrew routes to edge-he-avri");
        [engine stop];

        [engine speakText:@"English text should auto-route to Evan" voice:nil rate:1.0f];
        ASSERT([engine.currentVoice isEqualToString:@"apple-evan"], "English text auto-routes voice to apple-evan");
        [engine stop];

        [engine speakText:@"Custom Apple voice should be preserved" voice:@"apple-samantha" rate:1.0f];
        ASSERT([engine.currentVoice isEqualToString:@"apple-samantha"], "apple-samantha voice is preserved");
        [engine stop];

        // Adversarial test: eleven-rachel must NOT trigger Hebrew voice routing in speakText
        [engine speakText:@"Hello world with Rachel" voice:@"eleven-rachel" rate:1.0f];
        ASSERT([engine.currentVoice isEqualToString:@"eleven-rachel"], "eleven-rachel voice is preserved without false Hebrew switch");
        [engine stop];

        // Objective-C isHebrewVoice unit tests
        ASSERT(![engine isHebrewVoice:@"eleven-rachel"], "Native isHebrewVoice rejects eleven-rachel");
        ASSERT(![engine isHebrewVoice:@"apple-heather"], "Native isHebrewVoice rejects apple-heather");
        ASSERT(![engine isHebrewVoice:@"apple-evan"], "Native isHebrewVoice rejects apple-evan");
        ASSERT(![engine isHebrewVoice:@"edge-en-jenny"], "Native isHebrewVoice rejects edge-en-jenny");
        ASSERT(![engine isHebrewVoice:@"edge-en-guy"], "Native isHebrewVoice rejects edge-en-guy");
        ASSERT(![engine isHebrewVoice:@"english"], "Native isHebrewVoice rejects english");
        ASSERT([engine isHebrewVoice:@"edge-he-avri"], "Native isHebrewVoice accepts edge-he-avri");
        ASSERT([engine isHebrewVoice:@"edge-he-hila"], "Native isHebrewVoice accepts edge-he-hila");
        ASSERT([engine isHebrewVoice:@"google-he-neural2"], "Native isHebrewVoice accepts google-he-neural2");
        ASSERT([engine isHebrewVoice:@"avri"], "Native isHebrewVoice accepts standalone avri");
        ASSERT([engine isHebrewVoice:@"hila"], "Native isHebrewVoice accepts standalone hila");
        ASSERT([engine isHebrewVoice:@"he-IL"], "Native isHebrewVoice accepts he-IL prefix");
        ASSERT([engine isHebrewVoice:@"he-roboshaul"], "Native isHebrewVoice accepts he-roboshaul");
        ASSERT([engine isHebrewVoice:@"roboshaul"], "Native isHebrewVoice accepts standalone roboshaul");
        ASSERT([engine isHebrewVoice:@"shaul"], "Native isHebrewVoice accepts standalone shaul");
        ASSERT(![engine isHebrewVoice:nil], "Native isHebrewVoice handles nil safely");

        // Stub only the OS network boundary for deterministic offline behavior.
        Class sessionClass = [[NSURLSession sharedSession] class];
        Method socketMethod = class_getInstanceMethod(sessionClass, @selector(webSocketTaskWithRequest:));
        Method dataMethod = class_getInstanceMethod(sessionClass, @selector(dataTaskWithRequest:completionHandler:));
        IMP originalSocket = method_setImplementation(socketMethod, (IMP)offlineSocket);
        IMP originalData = method_setImplementation(dataMethod, (IMP)offlineData);

        // Test Edge TTS single-fallback execution and Hebrew voice fallback
        TestSpeechDelegate *del = [[TestSpeechDelegate alloc] init];
        engine.delegate = del;

        // Test English Edge TTS fallback
        del.startCount = 0;
        [engine speakEdgeTTS:@"English fallback test" voice:@"edge-en-jenny" rate:1.0f];
        NSDate *start = [NSDate date];
        while (del.startCount == 0 && [[NSDate date] timeIntervalSinceDate:start] < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];

        ASSERT(del.startCount == 1, "English Edge TTS fallback triggers speech start once");
        ASSERT([engine.currentVoice isEqualToString:@"apple-evan"], "English Edge TTS fallback correctly routes to apple-evan");
        [engine stop];

        // Test ElevenLabs fallback on invalid/dummy API key
        del.startCount = 0;
        [engine speakElevenLabs:@"Testing ElevenLabs fallback with invalid key." voiceId:@"eleven-rachel" apiKey:@"invalid-key" rate:1.0f];
        start = [NSDate date];
        while (del.startCount == 0 && [[NSDate date] timeIntervalSinceDate:start] < 3.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        ASSERT(del.startCount == 1, "ElevenLabs fallback on bad key triggers local speech once");
        ASSERT([engine.currentVoice isEqualToString:@"apple-evan"], "ElevenLabs English fallback routes to apple-evan");
        [engine stop];

        // Test Google TTS fallback on invalid/dummy API key for English
        del.startCount = 0;
        [engine speakGoogleTTS:@"Google TTS fallback test" voice:@"google-en-neural2" apiKey:@"invalid-key" rate:1.0f];
        start = [NSDate date];
        while (del.startCount == 0 && [[NSDate date] timeIntervalSinceDate:start] < 3.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        ASSERT(del.startCount == 1, "Google TTS fallback on bad key triggers local speech once");
        ASSERT([engine.currentVoice isEqualToString:@"apple-evan"], "Google TTS English fallback routes to apple-evan");
        [engine stop];

        // Queued transport events must retain ownership when stop replaces a request.
        del.pauseCount = 0;
        [engine pause];
        [engine stop];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        ASSERT(del.pauseCount == 0, "Cancelled native pause cannot affect a replacement passage");

        method_setImplementation(socketMethod, originalSocket);
        method_setImplementation(dataMethod, originalData);
        engine.delegate = nil;

        printf("SpeechEngine tests: %d / %d passed\n\n", g_testsPassed, g_testsRun);
        return (g_testsPassed == g_testsRun) ? 0 : 1;
    }
}

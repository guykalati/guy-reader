#import <Cocoa/Cocoa.h>
#import "../src/speech_engine.h"
@interface BoundaryObserver : NSObject <SpeechEngineDelegate>
@property NSMutableArray<NSValue *> *ranges;
@property BOOL finished;
@end
@implementation BoundaryObserver
- (void)speechDidStartSpeaking {}
- (void)speechDidPause {}
- (void)speechDidFinishSentence { self.finished = YES; }
- (void)speechWillSpeakRange:(NSRange)range { [self.ranges addObject:[NSValue valueWithRange:range]]; }
@end
int main(void) {
 @autoreleasepool {
  SpeechEngine *engine = [SpeechEngine new]; BoundaryObserver *observer = [BoundaryObserver new];
  observer.ranges = [NSMutableArray array];engine.delegate=observer;
  NSString *text=@"First word. Second phrase continues.";
  [engine speakText:text voice:@"apple-evan" rate:1.2];
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
  while(!observer.finished && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  BOOL second=NO;
  for(NSValue *value in observer.ranges){ NSRange range=value.rangeValue;
   if(NSMaxRange(range)<=text.length && [[text substringWithRange:range] isEqualToString:@"Second"]) second=YES;
  }
  [engine stop];
  printf("Native boundary events: %lu; second sentence mapped: %s\n",(unsigned long)observer.ranges.count,second?"yes":"no");
  return second && observer.finished ? 0 : 1;
 }
}

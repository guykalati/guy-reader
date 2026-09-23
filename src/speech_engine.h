#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SpeechEngineDelegate <NSObject>
- (void)speechDidFinishSentence;
- (void)speechDidStartSpeaking;
- (void)speechDidPause;
@optional
- (void)speechWillSpeakRange:(NSRange)range;
@end

@interface SpeechEngine : NSObject <AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate>

@property (nonatomic, weak) id<SpeechEngineDelegate> delegate;
@property (nonatomic, assign) float speedRate; // 0.5 to 2.5
@property (nonatomic, copy) NSString *currentVoice;
@property (nonatomic, assign) uint64_t currentSentenceId;
@property (nonatomic, assign) uint64_t playingSentenceId;
@property (nonatomic, assign, readonly) BOOL isPaused;

+ (instancetype)sharedInstance;

- (void)speakText:(NSString *)text voice:(nullable NSString *)voiceName rate:(float)rate;
- (void)pause;
- (void)resume;
- (void)stop;
- (BOOL)isSpeaking;

- (void)speakEdgeTTS:(NSString *)text voice:(nullable NSString *)shortVoiceName rate:(float)rate;
- (void)speakElevenLabs:(NSString *)text voiceId:(NSString *)voiceId apiKey:(NSString *)apiKey rate:(float)rate;
- (void)speakGoogleTTS:(NSString *)text voice:(NSString *)voiceName apiKey:(NSString *)apiKey rate:(float)rate;

- (BOOL)isHebrew:(NSString *)text;
- (BOOL)isHebrewVoice:(nullable NSString *)voiceName;
- (void)openSystemVoiceSettings;

@end

NS_ASSUME_NONNULL_END

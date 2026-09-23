#import "speech_engine.h"
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *const kEdgeTrustedToken = @"6A5AA1D4EAFF4E9FB37E23D68491D6F4";
static NSString *const kEdgeSecMsGecVersion = @"1-143.0.3650.75";

static NSString *GenerateSecMsGec(void) {
    uint64_t WIN_EPOCH = 11644473600ULL;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    uint64_t ticks = (uint64_t)(now + WIN_EPOCH);
    ticks -= (ticks % 300ULL);
    ticks *= 10000000ULL;
    NSString *strToHash = [NSString stringWithFormat:@"%llu%@", ticks, kEdgeTrustedToken];
    const char *cStr = [strToHash UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02X", digest[i]];
    }
    return hex;
}

@interface SpeechEngine () {
    AVSpeechSynthesizer *_synthesizer;
    AVSpeechUtterance *_activeUtterance;
    NSURLSessionDataTask *_cloudTask;
    AVAudioPlayer *_audioPlayer;
    NSURLSessionWebSocketTask *_webSocketTask;
    NSMutableData *_edgeAudioBuffer;
    BOOL _isPaused;
    BOOL _isSynthesizerSpeaking;
    BOOL _edgeFallbackTriggered;
}
@end

@implementation SpeechEngine

+ (instancetype)sharedInstance {
    static SpeechEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SpeechEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;
        _speedRate = 1.0f;
        _currentVoice = @"apple-evan";
        _isPaused = NO;
        _isSynthesizerSpeaking = NO;
        _edgeAudioBuffer = [NSMutableData data];
    }
    return self;
}

- (void)setSpeedRate:(float)speedRate {
    if (speedRate < 0.5f) speedRate = 0.5f;
    if (speedRate > 2.5f) speedRate = 2.5f;
    _speedRate = speedRate;
    if (_audioPlayer && _audioPlayer.isPlaying) {
        _audioPlayer.rate = speedRate;
    }
}

- (BOOL)isHebrew:(NSString *)text {
    if (!text || text.length == 0) return NO;
    NSRange range = [text rangeOfString:@"[\\u0590-\\u05FF]" options:NSRegularExpressionSearch];
    return range.location != NSNotFound;
}

- (BOOL)isHebrewVoice:(NSString *)voiceName {
    if (!voiceName || voiceName.length == 0) return NO;
    NSString *lower = [voiceName lowercaseString];
    return [lower containsString:@"-he-"] ||
           [lower containsString:@"_he_"] ||
           [lower hasPrefix:@"he-"] ||
           [lower hasPrefix:@"he_"] ||
           [lower containsString:@"hebrew"] ||
           [lower containsString:@"avri"] ||
           [lower containsString:@"hila"] ||
           [lower containsString:@"roboshaul"] ||
           [lower containsString:@"shaul"];
}

- (void)openSystemVoiceSettings {
    // Open macOS Accessibility Spoken Content settings pane
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Playback Control

- (void)pause {
    uint64_t sentenceId = self.currentSentenceId;
    _isPaused = YES;
    if ([_synthesizer isSpeaking]) {
        [_synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    if (_audioPlayer && [_audioPlayer isPlaying]) {
        [_audioPlayer pause];
    }
    if ([self.delegate respondsToSelector:@selector(speechDidPause)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentSentenceId != sentenceId) return;
            [self.delegate speechDidPause];
        });
    }
}

- (void)resume {
    uint64_t sentenceId = self.currentSentenceId;
    _isPaused = NO;
    if ([_synthesizer isPaused]) {
        [_synthesizer continueSpeaking];
    }
    if (_audioPlayer && ![_audioPlayer isPlaying]) {
        _audioPlayer.rate = _speedRate;
        [_audioPlayer play];
    }
    if ([self.delegate respondsToSelector:@selector(speechDidStartSpeaking)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentSentenceId != sentenceId) return;
            [self.delegate speechDidStartSpeaking];
        });
    }
}

- (void)stop {
    self.currentSentenceId++;
    _activeUtterance = nil;
    [_cloudTask cancel];
    _cloudTask = nil;
    self.playingSentenceId = 0;
    _isPaused = NO;
    _isSynthesizerSpeaking = NO;
    _edgeFallbackTriggered = YES;
    if ([_synthesizer isSpeaking] || [_synthesizer isPaused]) {
        [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    if (_audioPlayer) {
        _audioPlayer.delegate = nil;
        [_audioPlayer stop];
        _audioPlayer = nil;
    }
    if (_webSocketTask) {
        [_webSocketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        _webSocketTask = nil;
    }
    [_edgeAudioBuffer setLength:0];
}

- (BOOL)isSpeaking {
    if (_isPaused) return NO;
    if (_isSynthesizerSpeaking && _synthesizer.isSpeaking && !_synthesizer.isPaused) return YES;
    if (_audioPlayer && _audioPlayer.isPlaying) return YES;
    return NO;
}

- (BOOL)isPaused {
    return _isPaused;
}

#pragma mark - Engine 1: Apple Local Voices (Evan Enhanced)

- (void)speakText:(NSString *)text voice:(NSString *)voiceName rate:(float)rate {
    [self stop];
    uint64_t mySentenceId = ++self.currentSentenceId;
    self.playingSentenceId = mySentenceId;
    self.speedRate = rate;
    
    if (!text || text.length == 0) return;

    BOOL isHebrewText = [self isHebrew:text] || [self isHebrewVoice:voiceName];
    if (isHebrewText) {
        NSString *hebVoice = [self isHebrewVoice:voiceName] ? voiceName : @"edge-he-avri";
        self.currentVoice = hebVoice;
        if ([hebVoice containsString:@"roboshaul"] || [hebVoice containsString:@"shaul"]) {
            [self synthesizeViaLocalBridgeForText:text voice:hebVoice rate:rate sentenceId:mySentenceId];
            return;
        }
        [self speakEdgeTTS:text voice:hebVoice rate:rate];
        return;
    }

    if ([voiceName hasPrefix:@"edge-"]) {
        [self speakEdgeTTS:text voice:voiceName rate:rate];
        return;
    }

    self.currentVoice = voiceName ?: @"apple-evan";
    _isSynthesizerSpeaking = YES;

    AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:text];

    // Speed mapping: Apple rate is 0.0 to 1.0 (default is 0.5)
    float baseRate = AVSpeechUtteranceDefaultSpeechRate;
    float mappedRate = baseRate * self.speedRate;
    if (mappedRate < AVSpeechUtteranceMinimumSpeechRate) mappedRate = AVSpeechUtteranceMinimumSpeechRate;
    if (mappedRate > AVSpeechUtteranceMaximumSpeechRate) mappedRate = AVSpeechUtteranceMaximumSpeechRate;
    utterance.rate = mappedRate;

    AVSpeechSynthesisVoice *selectedVoice = nil;
    NSString *cleanVoiceName = voiceName;
    if ([cleanVoiceName hasPrefix:@"apple-"]) {
        cleanVoiceName = [cleanVoiceName substringFromIndex:6];
    }

    // 1. Try to find the voice by identifier or by name
    if (cleanVoiceName.length > 0 && ![cleanVoiceName isEqualToString:@"default"]) {
        selectedVoice = [AVSpeechSynthesisVoice voiceWithIdentifier:cleanVoiceName];
        if (!selectedVoice) {
            for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
                if ([v.name localizedCaseInsensitiveContainsString:cleanVoiceName] ||
                    [v.identifier localizedCaseInsensitiveContainsString:cleanVoiceName]) {
                    selectedVoice = v;
                    break;
                }
            }
        }
    }

    // 2. If Evan or default requested, look for Evan
    if (!selectedVoice && (!cleanVoiceName || [cleanVoiceName localizedCaseInsensitiveContainsString:@"evan"])) {
        NSArray *evanIds = @[
            @"com.apple.voice.enhanced.en-US.Evan",
            @"com.apple.voice.premium.en-US.Evan",
            @"com.apple.voice.compact.en-US.Evan",
            @"com.apple.ttsbundle.Evan-compact"
        ];
        for (NSString *vid in evanIds) {
            AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithIdentifier:vid];
            if (v) {
                selectedVoice = v;
                break;
            }
        }
        if (!selectedVoice) {
            for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
                if ([v.name containsString:@"Evan"] && [v.language hasPrefix:@"en"]) {
                    if (v.quality == AVSpeechSynthesisVoiceQualityEnhanced || v.quality == AVSpeechSynthesisVoiceQualityPremium) {
                        selectedVoice = v;
                        break;
                    }
                    selectedVoice = v;
                }
            }
        }
    }

    // 3. Fallback to any enhanced English voice or default English voice
    if (!selectedVoice) {
        for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
            if ([v.language hasPrefix:@"en-US"] && (v.quality == AVSpeechSynthesisVoiceQualityEnhanced || v.quality == AVSpeechSynthesisVoiceQualityPremium)) {
                selectedVoice = v;
                break;
            }
        }
    }
    if (!selectedVoice) {
        selectedVoice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    }

    if (selectedVoice) {
        utterance.voice = selectedVoice;
    }

    if ([self.delegate respondsToSelector:@selector(speechDidStartSpeaking)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentSentenceId == mySentenceId) [self.delegate speechDidStartSpeaking];
        });
    }

    _activeUtterance = utterance;
    [_synthesizer speakUtterance:utterance];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)range utterance:(AVSpeechUtterance *)utterance {
    uint64_t sentenceId = self.currentSentenceId;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (utterance != self->_activeUtterance || sentenceId != self.currentSentenceId || self->_isPaused) return;
        if ([self.delegate respondsToSelector:@selector(speechWillSpeakRange:)]) [self.delegate speechWillSpeakRange:range];
    });
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance) return;
    uint64_t sentenceId = self.currentSentenceId;
    _isSynthesizerSpeaking = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.currentSentenceId == sentenceId && utterance == self->_activeUtterance) {
            if ([self.delegate respondsToSelector:@selector(speechDidFinishSentence)]) {
                [self.delegate speechDidFinishSentence];
            }
        }
    });
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance == _activeUtterance) _isSynthesizerSpeaking = NO;
}

#pragma mark - Engine 2: Microsoft Edge Neural TTS (Avri, Hila, Jenny, Guy)

- (void)synthesizeViaLocalBridgeForText:(NSString *)text voice:(NSString *)voice rate:(float)rate sentenceId:(uint64_t)sentenceId {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5050/synthesize"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.timeoutInterval = 8.0;

    NSDictionary *body = @{
        @"text": text ?: @"",
        @"voice": voice ?: @"edge-he-avri",
        @"speed": @(rate)
    };
    NSError *jsonErr = nil;
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.currentSentenceId != sentenceId) return;
        if (!error && data.length > 100) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf->_edgeAudioBuffer setData:data];
                [strongSelf playBufferedAudioForText:text rate:rate sentenceId:sentenceId];
            });
        } else {
            NSLog(@"Local speech engine bridge unavailable for Hebrew: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.currentSentenceId == sentenceId) {
                    if ([strongSelf.delegate respondsToSelector:@selector(speechDidFinishSentence)]) {
                        [strongSelf.delegate speechDidFinishSentence];
                    }
                }
            });
        }
    }];
    [task resume];
}

- (void)handleEdgeTTSFallbackForText:(NSString *)text rate:(float)rate {
    if (_edgeFallbackTriggered) return;
    _edgeFallbackTriggered = YES;

    if (_webSocketTask) {
        [_webSocketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        _webSocketTask = nil;
    }

    uint64_t sentenceId = self.currentSentenceId;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.currentSentenceId != sentenceId) return;
        if ([self isHebrew:text]) {
            [self synthesizeViaLocalBridgeForText:text voice:self.currentVoice rate:rate sentenceId:sentenceId];
            return;
        }
        BOOL paused = self->_isPaused;
        NSString *fbVoice = [self.currentVoice hasPrefix:@"apple-"] ? self.currentVoice : @"apple-evan";
        [self speakText:text voice:fbVoice rate:rate];
        if (paused) [self pause];
    });
}

- (void)speakEdgeTTS:(NSString *)text voice:(NSString *)shortVoiceName rate:(float)rate {
    [self stop];
    uint64_t sentenceId = ++self.currentSentenceId;
    self.speedRate = rate;
    self.currentVoice = shortVoiceName ?: @"edge-he-avri";
    _edgeFallbackTriggered = NO;
    if (!text || text.length == 0) return;

    BOOL hebrewText = [self isHebrew:text];
    BOOL hebrewVoice = [self isHebrewVoice:shortVoiceName];
    BOOL hasLatin = [text rangeOfString:@"[a-zA-Z]" options:NSRegularExpressionSearch].location != NSNotFound;
    BOOL useHebrew = hebrewText || (hebrewVoice && !hasLatin);

    NSString *voiceFullName = @"he-IL-AvriNeural";
    if ([shortVoiceName containsString:@"hila"]) {
        voiceFullName = useHebrew ? @"he-IL-HilaNeural" : @"en-US-JennyNeural";
    } else if ([shortVoiceName containsString:@"jenny"]) {
        voiceFullName = useHebrew ? @"he-IL-AvriNeural" : @"en-US-JennyNeural";
    } else if ([shortVoiceName containsString:@"guy"]) {
        voiceFullName = useHebrew ? @"he-IL-AvriNeural" : @"en-US-GuyNeural";
    } else if ([shortVoiceName containsString:@"avri"]) {
        voiceFullName = useHebrew ? @"he-IL-AvriNeural" : @"en-US-GuyNeural";
    } else if (!useHebrew) {
        voiceFullName = @"en-US-JennyNeural";
    }

    // Percentage rate string for SSML
    int percent = (int)((rate - 1.0f) * 100);
    NSString *rateStr = (percent >= 0) ? [NSString stringWithFormat:@"+%d%%", percent] : [NSString stringWithFormat:@"%d%%", percent];

    NSString *langCode = [voiceFullName substringToIndex:5];
    NSString *ssml = [NSString stringWithFormat:
        @"<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='%@'>"
         "<voice name='%@'>"
          "<prosody rate='%@'>%@</prosody>"
         "</voice>"
        "</speak>", langCode, voiceFullName, rateStr, text];

    NSString *connId = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *gec = GenerateSecMsGec();
    NSString *wsUrlStr = [NSString stringWithFormat:@"wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=%@&ConnectionId=%@&Sec-MS-GEC=%@&Sec-MS-GEC-Version=%@", kEdgeTrustedToken, connId, gec, kEdgeSecMsGecVersion];
    NSURL *wsUrl = [NSURL URLWithString:wsUrlStr];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:wsUrl];
    [request setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold" forHTTPHeaderField:@"Origin"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    NSString *muid = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    [request setValue:[NSString stringWithFormat:@"muid=%@;", muid] forHTTPHeaderField:@"Cookie"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    _webSocketTask = [session webSocketTaskWithRequest:request];
    [_edgeAudioBuffer setLength:0];
    [_webSocketTask resume];
    [self receiveEdgeWebSocketMessagesForText:text sentenceId:sentenceId];

    // Safety timeout: if network stalls or hangs without response, fall back in 6.0s
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.currentSentenceId == sentenceId && strongSelf->_webSocketTask && !strongSelf->_edgeFallbackTriggered && (!strongSelf->_audioPlayer || !strongSelf->_audioPlayer.isPlaying)) {
            NSLog(@"Edge TTS timeout reached for sentence %llu, falling back cleanly", sentenceId);
            [strongSelf handleEdgeTTSFallbackForText:text rate:rate];
        }
    });

    // Send initial config message
    NSString *configMsg = @"Content-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n"
                          "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}";
    
    NSURLSessionWebSocketMessage *cfgMessage = [[NSURLSessionWebSocketMessage alloc] initWithString:configMsg];
    [_webSocketTask sendMessage:cfgMessage completionHandler:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.currentSentenceId != sentenceId) return;
        if (error) {
            if (error.code == NSURLErrorCancelled) return;
            NSLog(@"Edge TTS config send error: %@", error);
            [strongSelf handleEdgeTTSFallbackForText:text rate:rate];
            return;
        }

        // Send SSML synthesis request
        NSString *reqId = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
        NSString *ssmlMsg = [NSString stringWithFormat:@"X-RequestId:%@\r\nContent-Type:application/ssml+xml\r\nPath:ssml\r\n\r\n%@", reqId, ssml];
        NSURLSessionWebSocketMessage *sMessage = [[NSURLSessionWebSocketMessage alloc] initWithString:ssmlMsg];
        [strongSelf->_webSocketTask sendMessage:sMessage completionHandler:^(NSError * _Nullable err) {
            if (strongSelf.currentSentenceId != sentenceId) return;
            if (err) {
                if (err.code == NSURLErrorCancelled) return;
                NSLog(@"Edge TTS SSML send error: %@", err);
                [strongSelf handleEdgeTTSFallbackForText:text rate:rate];
            }
        }];
    }];
}

- (void)receiveEdgeWebSocketMessagesForText:(NSString *)text sentenceId:(uint64_t)sentenceId {
    if (!_webSocketTask) return;

    __weak typeof(self) weakSelf = self;
    [_webSocketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.currentSentenceId != sentenceId) return;
        if (error) {
            if (error.code == NSURLErrorCancelled) return;
            if (strongSelf->_edgeAudioBuffer.length > 0) {
                [strongSelf playBufferedAudioForText:text rate:strongSelf.speedRate sentenceId:sentenceId];
            } else {
                [strongSelf handleEdgeTTSFallbackForText:text rate:strongSelf.speedRate];
            }
            return;
        }

        if (message.type == NSURLSessionWebSocketMessageTypeData) {
            NSData *data = message.data;
            // Edge TTS binary audio headers: 2 bytes header length
            if (data.length > 2) {
                const uint8_t *bytes = (const uint8_t *)data.bytes;
                uint16_t headerLen = (bytes[0] << 8) | bytes[1];
                if (data.length > (NSUInteger)(2 + headerLen)) {
                    NSData *audioChunk = [data subdataWithRange:NSMakeRange(2 + headerLen, data.length - 2 - headerLen)];
                    [strongSelf->_edgeAudioBuffer appendData:audioChunk];
                }
            }
            [strongSelf receiveEdgeWebSocketMessagesForText:text sentenceId:sentenceId];
        } else if (message.type == NSURLSessionWebSocketMessageTypeString) {
            NSString *str = message.string;
            if ([str containsString:@"Path:turn.end"]) {
                [strongSelf playBufferedAudioForText:text rate:strongSelf.speedRate sentenceId:sentenceId];
                [strongSelf->_webSocketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
                strongSelf->_webSocketTask = nil;
            } else {
                [strongSelf receiveEdgeWebSocketMessagesForText:text sentenceId:sentenceId];
            }
        }
    }];
}

- (void)playBufferedAudioForText:(NSString *)text rate:(float)rate sentenceId:(uint64_t)sentenceId {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.currentSentenceId != sentenceId) return; // Discard stale/cancelled sentence!
        if (self->_edgeAudioBuffer.length == 0) {
            [self handleEdgeTTSFallbackForText:text rate:rate];
            return;
        }

        NSError *err = nil;
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:self->_edgeAudioBuffer error:&err];
        if (err || !self->_audioPlayer) {
            NSLog(@"Audio player init error: %@", err);
            [self handleEdgeTTSFallbackForText:text rate:rate];
            return;
        }
        self.playingSentenceId = sentenceId;
        self->_audioPlayer.delegate = self;
        self->_audioPlayer.enableRate = YES;
        self->_audioPlayer.rate = self.speedRate;
        [self->_audioPlayer prepareToPlay];
        if (self->_isPaused) return;
        BOOL started = [self->_audioPlayer play];
        if (!started) {
            NSLog(@"Audio player failed to start playback, falling back");
            [self handleEdgeTTSFallbackForText:text rate:rate];
            return;
        }

        if ([self.delegate respondsToSelector:@selector(speechDidStartSpeaking)]) {
            [self.delegate speechDidStartSpeaking];
        }
    });
}

#pragma mark - Engine 3: ElevenLabs Multilingual v2

- (void)speakElevenLabs:(NSString *)text voiceId:(NSString *)voiceId apiKey:(NSString *)apiKey rate:(float)rate {
    [self stop];
    uint64_t sentenceId = self.currentSentenceId;
    self.playingSentenceId = sentenceId;
    self.speedRate = rate;
    self.currentVoice = voiceId;
    if (!text || text.length == 0 || !apiKey || apiKey.length == 0) return;

    NSString *urlStr = [NSString stringWithFormat:@"https://api.elevenlabs.io/v1/text-to-speech/%@", voiceId];
    NSURL *url = [NSURL URLWithString:urlStr];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 8.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:apiKey forHTTPHeaderField:@"xi-api-key"];

    NSDictionary *body = @{
        @"text": text,
        @"model_id": @"eleven_multilingual_v2",
        @"voice_settings": @{
            @"stability": @0.5,
            @"similarity_boost": @0.8
        }
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.currentSentenceId != sentenceId) return;
        NSHTTPURLResponse *httpResp = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (error || !data || (httpResp && httpResp.statusCode != 200)) {
            NSLog(@"ElevenLabs TTS error (status %ld): %@", (long)(httpResp ? httpResp.statusCode : 0), error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.currentSentenceId != sentenceId || strongSelf->_isPaused) return;
                if ([strongSelf isHebrew:text]) {
                    [strongSelf speakEdgeTTS:text voice:@"edge-he-avri" rate:rate];
                } else {
                    [strongSelf speakText:text voice:@"apple-evan" rate:rate];
                }
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.currentSentenceId != sentenceId) return;
            NSError *pErr = nil;
            strongSelf->_audioPlayer = [[AVAudioPlayer alloc] initWithData:data error:&pErr];
            if (!pErr && strongSelf->_audioPlayer) {
                strongSelf->_audioPlayer.delegate = strongSelf;
                strongSelf->_audioPlayer.enableRate = YES;
                strongSelf->_audioPlayer.rate = strongSelf.speedRate;
                if (![strongSelf->_audioPlayer play]) {
                    if ([strongSelf isHebrew:text]) {
                        [strongSelf speakEdgeTTS:text voice:@"edge-he-avri" rate:rate];
                    } else {
                        [strongSelf speakText:text voice:@"apple-evan" rate:rate];
                    }
                    return;
                }
                if ([strongSelf.delegate respondsToSelector:@selector(speechDidStartSpeaking)]) {
                    [strongSelf.delegate speechDidStartSpeaking];
                }
            } else {
                if ([strongSelf isHebrew:text]) {
                    [strongSelf speakEdgeTTS:text voice:@"edge-he-avri" rate:rate];
                } else {
                    [strongSelf speakText:text voice:@"apple-evan" rate:rate];
                }
            }
        });
    }];
    _cloudTask = task;
    [task resume];
}

#pragma mark - Engine 4: Google Cloud TTS

- (void)speakGoogleTTS:(NSString *)text voice:(NSString *)voiceName apiKey:(NSString *)apiKey rate:(float)rate {
    [self stop];
    uint64_t sentenceId = self.currentSentenceId;
    self.playingSentenceId = sentenceId;
    self.speedRate = rate;
    self.currentVoice = voiceName;
    if (!text || text.length == 0 || !apiKey || apiKey.length == 0) return;

    NSString *urlStr = [NSString stringWithFormat:@"https://texttospeech.googleapis.com/v1/text:synthesize?key=%@", apiKey];
    NSURL *url = [NSURL URLWithString:urlStr];

    BOOL isHebrew = [self isHebrew:text] || [self isHebrewVoice:voiceName];
    NSString *langCode = isHebrew ? @"he-IL" : @"en-US";
    NSString *googleVoice = isHebrew ? ([voiceName containsString:@"neural2"] ? @"he-IL-Neural2-A" : @"he-IL-Wavenet-A") : @"en-US-Neural2-F";

    NSDictionary *body = @{
        @"input": @{@"text": text},
        @"voice": @{
            @"languageCode": langCode,
            @"name": googleVoice
        },
        @"audioConfig": @{
            @"audioEncoding": @"MP3",
            @"speakingRate": @(rate)
        }
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 8.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.currentSentenceId != sentenceId) return;
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.currentSentenceId != sentenceId || strongSelf->_isPaused) return;
                if ([strongSelf isHebrew:text]) {
                    [strongSelf speakEdgeTTS:text voice:@"edge-he-avri" rate:rate];
                } else {
                    [strongSelf speakText:text voice:@"apple-evan" rate:rate];
                }
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *audioB64 = json[@"audioContent"];
        if (audioB64) {
            NSData *audioData = [[NSData alloc] initWithBase64EncodedString:audioB64 options:0];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.currentSentenceId != sentenceId || strongSelf->_isPaused) return;
                NSError *pErr = nil;
                strongSelf->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:&pErr];
                if (!pErr && strongSelf->_audioPlayer) {
                    strongSelf->_audioPlayer.delegate = strongSelf;
                    strongSelf->_audioPlayer.enableRate = YES;
                    strongSelf->_audioPlayer.rate = strongSelf.speedRate;
                    if (![strongSelf->_audioPlayer play]) {
                        if ([strongSelf isHebrew:text]) {
                            [strongSelf speakEdgeTTS:text voice:@"edge-he-avri" rate:rate];
                        } else {
                            [strongSelf speakText:text voice:@"apple-evan" rate:rate];
                        }
                        return;
                    }
                    if ([strongSelf.delegate respondsToSelector:@selector(speechDidStartSpeaking)]) {
                        [strongSelf.delegate speechDidStartSpeaking];
                    }
                } else {
                    if ([strongSelf isHebrew:text]) {
                        [strongSelf speakEdgeTTS:text voice:@"edge-he-avri" rate:rate];
                    } else {
                        [strongSelf speakText:text voice:@"apple-evan" rate:rate];
                    }
                }
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.currentSentenceId != sentenceId || strongSelf->_isPaused) return;
                if ([strongSelf isHebrew:text]) {
                    [strongSelf speakEdgeTTS:text voice:@"edge-he-avri" rate:rate];
                } else {
                    [strongSelf speakText:text voice:@"apple-evan" rate:rate];
                }
            });
        }
    }];
    _cloudTask = task;
    [task resume];
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    uint64_t sentenceId = self.currentSentenceId;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (player != self->_audioPlayer || sentenceId != self.currentSentenceId) return;
        if (self.playingSentenceId == self.currentSentenceId && self.currentSentenceId > 0) {
            if ([self.delegate respondsToSelector:@selector(speechDidFinishSentence)]) {
                [self.delegate speechDidFinishSentence];
            }
        }
    });
}

@end

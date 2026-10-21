#import "speech_engine.h"
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *const kEdgeTrustedToken = @"6A5AA1D4EAFF4E9FB37E23D68491D6F4";
static NSString *const kEdgeSecMsGecVersion = @"2-143.0.3650.75";

static const uint32_t kSha256Initial[8] = {
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
};
static const uint32_t kSha256State[8] = {
    0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
    0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2
};
static const uint32_t kSha256Schedule[14] = {
    0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA,
    0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6,
    0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
    0xD258B060, 0x72766564
};
static const uint32_t kSha256RoundConstants[64] = {
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
};
static const uint32_t kSha256Adjustment = 0xC9DC06A7;
static const uint32_t kSha256Sigma0Adjustment = 0x059C0B80;
static const uint32_t kSha256Sigma1Adjustment = 0x000B92C0;

static const uint32_t kCs64Coefficients[14][2] = {
    {0xE82E91B1, 0xB32700D0}, {0x44DE24C6, 0x88DFF51D},
    {0x3BEB65BC, 0x29514038}, {0xC89C5933, 0xB328CBDF},
    {0x8D1EC211, 0xD405B4D5}, {0x314EF5D5, 0x26E55F3C},
    {0xE92491B1, 0x607801C6}, {0xF0A5B9D5, 0x82B2C1FB},
    {0x06064CF3, 0xFA51A3DA}, {0xDA79FA60, 0x207CC464},
    {0xBED20560, 0x3C3C74F3}, {0x89F9C9F8, 0xD2D14B61},
    {0x35FA38C6, 0xBB04A2C1}, {0xCB49E3C6, 0xC5626167}
};
static const uint32_t kCs64Factor = 0x82893933;
static const uint32_t kCs64Adjustment0 = 0xF2F90B1A;
static const uint32_t kCs64Adjustment1 = 0x0B1A0000;

static inline uint32_t Rol16(uint32_t v) { return (v << 16) | (v >> 16); }
static inline uint32_t Rotr32(uint32_t v, int n) { return (v >> n) | (v << (32 - n)); }
static inline uint32_t Sigma0(uint32_t v) { return Rotr32(v, 7) ^ Rotr32(v, 18) ^ (v >> 3); }
static inline uint32_t Sigma1(uint32_t v) { return Rotr32(v, 17) ^ Rotr32(v, 19) ^ (v >> 10); }

static void ExpandSha256Schedule(uint32_t words[64], int firstWord) {
    for (int i = firstWord; i < 64; i++) {
        words[i] = Sigma1(words[i - 2]) + words[i - 7] + Sigma0(words[i - 15]) + words[i - 16];
    }
}

static void Sha256Rounds(uint32_t state[8], const uint32_t words[64], int firstRound) {
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];
    for (int i = firstRound; i < 64; i++) {
        uint32_t k = (firstRound == 14 && i == 14) ? kSha256Adjustment : kSha256RoundConstants[i];
        uint32_t S1 = Rotr32(e, 6) ^ Rotr32(e, 11) ^ Rotr32(e, 25);
        uint32_t ch = g ^ (e & (f ^ g));
        uint32_t t1 = h + S1 + ch + k + words[i];
        uint32_t S0 = Rotr32(a, 2) ^ Rotr32(a, 13) ^ Rotr32(a, 22);
        uint32_t maj = (a & b) | (c & (a | b));
        uint32_t t2 = S0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    state[0] = a; state[1] = b; state[2] = c; state[3] = d;
    state[4] = e; state[5] = f; state[6] = g; state[7] = h;
}

static void Sha256Init(const uint8_t data7[7], uint32_t outState[8]) {
    uint32_t words[64] = {0};
    words[14] = ((uint32_t)data7[0] << 16) | ((uint32_t)data7[1] << 8) | (uint32_t)data7[2];
    words[15] = ((uint32_t)data7[3] << 24) | ((uint32_t)data7[4] << 16) | ((uint32_t)data7[5] << 8) | (uint32_t)data7[6];
    for (int i = 16; i < 30; i++) {
        uint32_t val = kSha256Schedule[i - 16];
        if (i - 2 >= 14) {
            val += (i == 16) ? (Sigma1(words[i - 2]) ^ kSha256Sigma1Adjustment) : Sigma1(words[i - 2]);
        }
        if (i - 7 >= 14) {
            val += words[i - 7];
        }
        if (i - 15 >= 14) {
            val += (i == 29) ? (Sigma0(words[i - 15]) ^ kSha256Sigma0Adjustment) : Sigma0(words[i - 15]);
        }
        words[i] = val;
    }
    words[30] = Sigma1(words[28]) + words[23] + Sigma0(words[15]) + words[14] + kSha256Adjustment - kSha256RoundConstants[14];
    ExpandSha256Schedule(words, 31);
    uint32_t working[8];
    memcpy(working, kSha256State, sizeof(working));
    Sha256Rounds(working, words, 14);
    for (int i = 0; i < 8; i++) {
        outState[i] = kSha256Initial[i] + working[i];
    }
}

static void Sha256Digest(const uint8_t *data, size_t dataLen, uint8_t outDigest[32]) {
    size_t length = 57 + dataLen;
    size_t remLen = dataLen - 7;
    size_t padZeroLen = (64 - ((length - 55) % 64)) % 64;
    if ((55 - (ssize_t)length) % 64 != 0) {
        ssize_t mod = (55 - (ssize_t)length) % 64;
        if (mod < 0) mod += 64;
        padZeroLen = (size_t)mod;
    } else {
        padZeroLen = 0;
    }
    size_t paddedLen = remLen + 1 + padZeroLen + 8;
    uint8_t *padded = (uint8_t *)calloc(paddedLen, 1);
    memcpy(padded, data + 7, remLen);
    padded[remLen] = 0x80;
    uint64_t bitLen = (uint64_t)length * 8ULL;
    for (int i = 0; i < 8; i++) {
        padded[paddedLen - 1 - i] = (uint8_t)((bitLen >> (i * 8)) & 0xFF);
    }

    uint32_t state[8];
    Sha256Init(data, state);
    for (size_t offset = 0; offset < paddedLen; offset += 64) {
        uint32_t words[64] = {0};
        for (int j = 0; j < 16; j++) {
            const uint8_t *p = padded + offset + j * 4;
            words[j] = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
        }
        ExpandSha256Schedule(words, 16);
        uint32_t working[8];
        memcpy(working, state, sizeof(state));
        Sha256Rounds(working, words, 0);
        for (int j = 0; j < 8; j++) state[j] += working[j];
    }
    free(padded);
    for (int i = 0; i < 8; i++) {
        outDigest[i * 4 + 0] = (uint8_t)((state[i] >> 24) & 0xFF);
        outDigest[i * 4 + 1] = (uint8_t)((state[i] >> 16) & 0xFF);
        outDigest[i * 4 + 2] = (uint8_t)((state[i] >> 8) & 0xFF);
        outDigest[i * 4 + 3] = (uint8_t)(state[i] & 0xFF);
    }
}

static void Cs64Digest(const uint8_t *data, size_t dataLen, const uint8_t digest[32], uint8_t outCs64[8]) {
    uint32_t keyA = ((uint32_t)digest[0] | ((uint32_t)digest[1] << 8) | ((uint32_t)digest[2] << 16) | ((uint32_t)digest[3] << 24)) | 1U;
    uint32_t keyB = ((uint32_t)digest[4] | ((uint32_t)digest[5] << 8) | ((uint32_t)digest[6] << 16) | ((uint32_t)digest[7] << 24)) | 1U;
    uint32_t factors[2] = { keyA * kCs64Factor, keyB * kCs64Factor };

    size_t prefLen = 1 + dataLen;
    size_t padLen = (4 - (prefLen % 4)) % 4;
    size_t wordCount = (prefLen + padLen) / 4;
    if (wordCount % 2 == 1) wordCount++;
    uint8_t *prefixed = (uint8_t *)calloc(wordCount * 4, 1);
    memcpy(prefixed + 1, data, dataLen);

    size_t totalTerms = 14 + wordCount;
    uint32_t *terms = (uint32_t *)calloc(totalTerms, sizeof(uint32_t));
    uint32_t *offsets = (uint32_t *)calloc(totalTerms, sizeof(uint32_t));
    for (int i = 0; i < 14; i++) {
        terms[i] = kCs64Coefficients[i][0] * factors[i % 2];
        offsets[i] = kCs64Coefficients[i][1];
    }
    for (size_t idx = 0; idx < wordCount; idx++) {
        const uint8_t *p = prefixed + idx * 4;
        uint32_t word = (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
        uint32_t term = word * ((idx % 2 == 0) ? keyA : keyB);
        uint32_t offset = Rol16(word) * ((idx % 2 == 0) ? 0xEF0569FBU : 0xC31713DBU);
        if (idx == 0) {
            term += kCs64Adjustment0 * factors[0];
            offset += kCs64Adjustment1;
        }
        terms[14 + idx] = term;
        offsets[14 + idx] = offset;
    }
    free(prefixed);

    uint32_t swapAcc = 0, swapLast = 0, state = 0, acc = 0;
    for (size_t idx = 0; idx < totalTerms; idx += 2) {
        uint32_t x = terms[idx], y = terms[idx + 1];
        uint32_t t = Rol16(offsets[idx] + x);
        uint32_t q = t * 0x76F50F34U;
        swapAcc += Rol16(q) * 0xC3EFEA97U + q;
        t = Rol16(offsets[idx + 1] + y);
        q = t * 0x1881CE3CU;
        swapLast = Rol16(q) * 0x35BD1EC9U + q;
        swapAcc += swapLast;

        state = state * keyA + x;
        state = Rol16(state) * 0xCF98B111U;
        state = Rol16(state) * 0x87085B9FU;
        state = Rol16(state) * 0x12CEB96DU;
        state = Rol16(state) * 0x257E1D83U;
        acc += state;
        t = state * keyB + y;
        t = Rol16(t) * 0xA27416F5U;
        t = Rol16(t) * 0xD38396FFU;
        state = Rol16(Rol16(t) * 0x7C932B89U) * 0xBFA49F69U;
        acc += state;
    }
    free(terms);
    free(offsets);

    uint32_t w0 = swapLast ^ state;
    uint32_t w1 = swapAcc ^ acc;
    outCs64[0] = (uint8_t)(w0 & 0xFF);
    outCs64[1] = (uint8_t)((w0 >> 8) & 0xFF);
    outCs64[2] = (uint8_t)((w0 >> 16) & 0xFF);
    outCs64[3] = (uint8_t)((w0 >> 24) & 0xFF);
    outCs64[4] = (uint8_t)(w1 & 0xFF);
    outCs64[5] = (uint8_t)((w1 >> 8) & 0xFF);
    outCs64[6] = (uint8_t)((w1 >> 16) & 0xFF);
    outCs64[7] = (uint8_t)((w1 >> 24) & 0xFF);
}

static NSString *GenerateSecMsGec(void) {
    uint64_t WIN_EPOCH = 11644473600ULL;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    uint64_t ticks = (uint64_t)(now + WIN_EPOCH);
    ticks -= (ticks % 300ULL);
    ticks *= 10000000ULL;
    NSString *strToHash = [NSString stringWithFormat:@"%llu%@", ticks, kEdgeTrustedToken];
    const uint8_t *cStr = (const uint8_t *)[strToHash UTF8String];
    size_t len = strlen((const char *)cStr);
    uint8_t digest[32];
    Sha256Digest(cStr, len, digest);
    uint8_t cs64[8];
    Cs64Digest(cStr, len, digest, cs64);
    NSMutableString *hex = [NSMutableString stringWithCapacity:81];
    for (int i = 0; i < 8; i++) [hex appendFormat:@"%02X", cs64[i]];
    [hex appendString:@"-"];
    for (int i = 0; i < 32; i++) [hex appendFormat:@"%02X", digest[i]];
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

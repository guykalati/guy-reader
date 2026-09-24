#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import "speech_engine.h"
#import "reading_origin.h"

NS_ASSUME_NONNULL_BEGIN

// Forward declaration
@interface AppDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, SpeechEngineDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) SpeechEngine *speechEngine;
@property (nonatomic, strong, nullable) NSRunningApplication *lastTargetApp;
@property (nonatomic, strong, nullable) NSTask *speechEngineTask;
@property (nonatomic, copy, nullable) NSString *pendingText;
@property (nonatomic, copy, nullable) NSString *currentReadingText;
@property (nonatomic, assign) BOOL isWebViewReady;
@property (nonatomic, assign) NSInteger readingClipboardChangeCount;
@property (nonatomic, assign) NSUInteger speechRequestId;
@property (nonatomic, assign) BOOL readerIsActive;
@property (nonatomic, assign) NSUInteger captureRevision;
@property (nonatomic, strong, nullable) id sourceClickMonitor;
@property (nonatomic, copy, nullable) NSString *clickedReadingText;
@property (nonatomic, assign) CGPoint clickedPoint;
@property (nonatomic, assign) BOOL hasClickedPoint;
@property (nonatomic, assign) pid_t clickedAppPID;
@property (nonatomic, assign) BOOL browserReading;
@property (nonatomic, strong, nullable) NSTimer *browserStateTimer;
@property (nonatomic, assign) NSUInteger browserSession;
@property (nonatomic, assign) BOOL hasStoppedEngine;
- (void)readSelectionFromActiveApp;
- (void)notifyNoTextCaptured;
- (void)ensureSpeechEngineDaemonRunning;
- (void)stopSpeechEngineDaemon;
- (void)quitApp;
@end

static AppDelegate *g_appDelegate = nil;

static NSString *const kSmartExtractJS =
@"(function() {"
"  var sel = window.getSelection ? window.getSelection().toString() : '';"
"  if (sel && sel.trim().length > 0) {"
"    return '__GUY_READER_EXACT_SEL__' + sel.trim();"
"  }"
"  var host = window.location.hostname || '';"
"  if (host.indexOf('twitter.com') !== -1 || host.indexOf('x.com') !== -1) {"
"    var tweets = document.querySelectorAll('article[data-testid=\"tweet\"]');"
"    if (tweets.length > 0) {"
"      var bestTweet = null;"
"      var bestScore = -1e9;"
"      var vh = window.innerHeight;"
"      for (var i = 0; i < tweets.length; i++) {"
"        var t = tweets[i];"
"        var rect = t.getBoundingClientRect();"
"        var visibleHeight = Math.max(0, Math.min(vh, rect.bottom) - Math.max(0, rect.top));"
"        if (visibleHeight > 30) {"
"          var tweetCenter = (rect.top + rect.bottom) / 2;"
"          var distFromScreenCenter = Math.abs(tweetCenter - vh / 2);"
"          var score = visibleHeight * 2 - distFromScreenCenter;"
"          if (score > bestScore) {"
"            bestScore = score;"
"            bestTweet = t;"
"          }"
"        }"
"      }"
"      if (bestTweet) {"
"        var textEls = bestTweet.querySelectorAll('[data-testid=\"tweetText\"]');"
"        if (textEls.length > 0) {"
"          var tweetTexts = [];"
"          for (var ti = 0; ti < textEls.length; ti++) {"
"            var tt = textEls[ti].innerText ? textEls[ti].innerText.trim() : '';"
"            if (tt.length > 0) tweetTexts.push(tt);"
"          }"
"          if (tweetTexts.length > 0) return tweetTexts.join('\\n\\n');"
"        }"
"        var cloneT = bestTweet.cloneNode(true);"
"        var toRemoveT = cloneT.querySelectorAll('time, svg, [role=\"button\"], [role=\"group\"]');"
"        for (var r = 0; r < toRemoveT.length; r++) { toRemoveT[r].remove(); }"
"        if (cloneT.innerText && cloneT.innerText.trim().length > 0) {"
"          return cloneT.innerText.trim();"
"        }"
"      }"
"    }"
"  }"
"  var candidates = document.querySelectorAll('article, [role=\"main\"], main, .article-body, .post-content, .entry-content, #content, .story-body');"
"  var target = null;"
"  for (var j = 0; j < candidates.length; j++) {"
"    var c = candidates[j];"
"    if (c.offsetHeight > 50 && (!target || c.innerText.length > target.innerText.length)) {"
"      target = c;"
"    }"
"  }"
"  if (!target) target = document.body;"
"  var clone = target.cloneNode(true);"
"  var junk = clone.querySelectorAll('nav, header, footer, aside, .nav, .menu, .sidebar, .comments, .ad, .advertisement, script, style, noscript, svg, [aria-hidden=\"true\"], .timestamp, time');"
"  for (var k = 0; k < junk.length; k++) {"
"    junk[k].remove();"
"  }"
"  var paras = clone.querySelectorAll('p, h1, h2, h3, h4, blockquote, li');"
"  var collected = [];"
"  for (var p = 0; p < paras.length; p++) {"
"    var pt = paras[p].innerText ? paras[p].innerText.trim() : '';"
"    if (pt.length > 5 && /[\\p{L}\\p{N}]/u.test(pt)) {"
"      collected.push(pt);"
"    }"
"  }"
"  if (collected.length > 0) {"
"    return collected.join('\\n\\n');"
"  }"
"  var lines = clone.innerText ? clone.innerText.split('\\n') : [];"
"  var goodLines = [];"
"  for (var l = 0; l < lines.length; l++) {"
"    var line = lines[l].trim();"
"    if (line.length > 10 && /[\\p{L}\\p{N}]/u.test(line)) {"
"      goodLines.push(line);"
"    }"
"  }"
"  return goodLines.join('\\n\\n');"
"})();";

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    g_appDelegate = self;
    self.speechEngine = [SpeechEngine sharedInstance];
    self.speechEngine.delegate = self;

    // Silently check Accessibility trust without triggering an intrusive modal popup on launch
    AXIsProcessTrusted();

    // Ensure speech engine daemon is running in background without blocking UI startup
    [self ensureSpeechEngineDaemonRunning];

    // Track active application changes so clicking "Read" on the floating pill
    // knows which application and window the user was reading
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(handleAppChange:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(handleAppChange:)
                                                               name:NSWorkspaceDidDeactivateApplicationNotification
                                                             object:nil];

    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (front && ![front.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        self.lastTargetApp = front;
        AXUIElementRef frontAppElem = AXUIElementCreateApplication(front.processIdentifier);
        if (frontAppElem) {
            AXUIElementSetAttributeValue(frontAppElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
            CFRelease(frontAppElem);
        }
    }

    // Mouse-only observer: remember source text before clicking our floating controls.
    __weak typeof(self) weakSelf = self;
    self.sourceClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp handler:^(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (!front || front.processIdentifier == NSProcessInfo.processInfo.processIdentifier) return;
        strongSelf.lastTargetApp = front;
        strongSelf.clickedReadingText = nil;
        strongSelf.clickedAppPID = front.processIdentifier;
        NSPoint mouse = NSEvent.mouseLocation;
        CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
        CGPoint point = CGPointMake(mouse.x, top - mouse.y);
        strongSelf.clickedPoint = point;
        strongSelf.hasClickedPoint = YES;

        // Wake up accessibility tree on target process (crucial for Electron and Chromium apps)
        AXUIElementRef frontAppElem = AXUIElementCreateApplication(front.processIdentifier);
        if (frontAppElem) {
            AXUIElementSetAttributeValue(frontAppElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
            CFRelease(frontAppElem);
        }

        AXUIElementRef system = AXUIElementCreateSystemWide(), hit = NULL;
        if (AXUIElementCopyElementAtPosition(system, point.x, point.y, &hit) == kAXErrorSuccess && hit) {
            pid_t pid = 0; AXUIElementGetPid(hit, &pid);
            if (pid > 0 && pid != front.processIdentifier) {
                AXUIElementRef helperElem = AXUIElementCreateApplication(pid);
                if (helperElem) {
                    AXUIElementSetAttributeValue(helperElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
                    CFRelease(helperElem);
                }
            }
            NSRunningApplication *hitApp = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            BOOL belongsToFront = (pid == front.processIdentifier) ||
                                  (hitApp == nil) ||
                                  [hitApp.bundleIdentifier containsString:@"helper"] ||
                                  [hitApp.bundleIdentifier containsString:@"electron"] ||
                                  [hitApp.bundleIdentifier hasPrefix:front.bundleIdentifier] ||
                                  [front.bundleIdentifier hasPrefix:hitApp.bundleIdentifier ?: @""];
            if (belongsToFront) {
                NSString *txt = GRReadingTextAtElement(hit, point);
                if (txt.length) strongSelf.clickedReadingText = txt;
            }
            CFRelease(hit);
        }
        CFRelease(system);
    }];

    [self setupMenuBarItem];
    [self setupFloatingPanel];
}

- (void)ensureSpeechEngineDaemonRunning {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 1. Quick check if daemon is already healthy
        NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5050/health"];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.timeoutInterval = 0.5;

        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (!err && resp && [(NSHTTPURLResponse *)resp statusCode] == 200) {
                NSLog(@"[GuyReader] Local speech engine daemon is already running on port 5050");
                return;
            }

            // 2. Locate speech_engine.py and python in virtualenv
            NSString *appBundlePath = [[NSBundle mainBundle] bundlePath];
            NSString *workspaceDir = [appBundlePath stringByDeletingLastPathComponent];
            NSArray *scriptCandidates = @[
                [workspaceDir stringByAppendingPathComponent:@"speech_engine.py"],
                @"/Users/gyklty/Desktop/Guy/TTS/speech_engine.py"
            ];
            NSString *scriptPath = nil;
            for (NSString *cand in scriptCandidates) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:cand]) {
                    scriptPath = cand;
                    break;
                }
            }
            if (!scriptPath) {
                NSLog(@"[GuyReader] Warning: speech_engine.py not found");
                return;
            }

            NSString *baseDir = [scriptPath stringByDeletingLastPathComponent];
            NSArray *pythonCandidates = @[
                [baseDir stringByAppendingPathComponent:@".venv_guy/bin/python"],
                [baseDir stringByAppendingPathComponent:@"venv/bin/python"],
                @"/usr/bin/python3"
            ];
            NSString *pythonPath = nil;
            for (NSString *cand in pythonCandidates) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:cand]) {
                    pythonPath = cand;
                    break;
                }
            }
            if (!pythonPath) {
                pythonPath = @"/usr/bin/python3";
            }

            NSLog(@"[GuyReader] Auto-launching speech engine daemon in background: %@ %@", pythonPath, scriptPath);
            @try {
                NSTask *proc = [[NSTask alloc] init];
                proc.launchPath = pythonPath;
                proc.currentDirectoryPath = baseDir;
                proc.arguments = @[scriptPath];

                NSString *logPath = [baseDir stringByAppendingPathComponent:@"server.log"];
                if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
                    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
                }
                NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
                if (logHandle) {
                    [logHandle seekToEndOfFile];
                    proc.standardOutput = logHandle;
                    proc.standardError = logHandle;
                } else {
                    proc.standardOutput = [NSFileHandle fileHandleWithNullDevice];
                    proc.standardError = [NSFileHandle fileHandleWithNullDevice];
                }

                NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
                env[@"PYTHONUNBUFFERED"] = @"1";
                proc.environment = env;

                self.speechEngineTask = proc;
                [proc launch];
            } @catch (NSException *ex) {
                NSLog(@"[GuyReader] Error launching speech engine daemon: %@", ex);
            }
        }];
        [task resume];
    });
}

- (void)stopSpeechEngineDaemon {
    if (self.hasStoppedEngine) return;
    self.hasStoppedEngine = YES;

    NSLog(@"[GuyReader] Stopping speech engine daemon...");

    // 1. Send graceful shutdown request to HTTP /shutdown endpoint
    NSURL *shutdownUrl = [NSURL URLWithString:@"http://127.0.0.1:5050/shutdown"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:shutdownUrl];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 0.4;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)));

    // 2. Terminate the launched NSTask process if running
    if (self.speechEngineTask) {
        @try {
            pid_t pid = [self.speechEngineTask processIdentifier];
            if (self.speechEngineTask.isRunning) {
                [self.speechEngineTask terminate];
                for (int i = 0; i < 10 && self.speechEngineTask.isRunning; i++) {
                    usleep(50000); // 50ms * 10 = 500ms max
                }
                if (self.speechEngineTask.isRunning && pid > 0) {
                    kill(pid, SIGKILL);
                }
            }
        } @catch (NSException *ex) {
            NSLog(@"[GuyReader] Exception terminating speechEngineTask: %@", ex);
        }
        self.speechEngineTask = nil;
    }

    // 3. Read PID file(s) and terminate if still alive
    NSString *appBundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *workspaceDir = [appBundlePath stringByDeletingLastPathComponent];
    NSArray *pidPaths = @[
        [workspaceDir stringByAppendingPathComponent:@"speech_engine.pid"],
        @"/Users/gyklty/Desktop/Guy/TTS/speech_engine.pid",
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"guy_reader_speech_engine.pid"],
        @"/tmp/guy_reader_speech_engine.pid"
    ];
    for (NSString *pidPath in pidPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:pidPath]) {
            NSString *pidStr = [NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil];
            if (pidStr) {
                pid_t pid = (pid_t)[pidStr integerValue];
                if (pid > 1) {
                    kill(pid, SIGTERM);
                    usleep(50000);
                    if (kill(pid, 0) == 0) {
                        kill(pid, SIGKILL);
                    }
                }
            }
            [[NSFileManager defaultManager] removeItemAtPath:pidPath error:nil];
        }
    }

    // 4. Fallback pkill to guarantee no orphaned speech_engine.py is running
    @try {
        NSTask *pkillTask = [[NSTask alloc] init];
        pkillTask.launchPath = @"/usr/bin/pkill";
        pkillTask.arguments = @[@"-f", @"speech_engine.py"];
        pkillTask.standardOutput = [NSFileHandle fileHandleWithNullDevice];
        pkillTask.standardError = [NSFileHandle fileHandleWithNullDevice];
        [pkillTask launch];
        [pkillTask waitUntilExit];
    } @catch (NSException *ex) {
        // ignore
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.sourceClickMonitor) [NSEvent removeMonitor:self.sourceClickMonitor];
    [self.speechEngine stop];
    [self stopSpeechEngineDaemon];
}

- (void)handleAppChange:(NSNotification *)note {
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
    if (app && ![app.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        self.lastTargetApp = app;
        AXUIElementRef appElem = AXUIElementCreateApplication(app.processIdentifier);
        if (appElem) {
            AXUIElementSetAttributeValue(appElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
            CFRelease(appElem);
        }
    }
}

#pragma mark - Menu Bar Item

- (void)setupMenuBarItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    if (button) {
        button.title = @"🔊";
        button.toolTip = @"Guy_reader";
        button.target = self;
        button.action = @selector(togglePanelVisibility);
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Guy_reader"];
    [menu addItemWithTitle:@"Read Clicked / Highlighted Text" action:@selector(readSelectionFromActiveApp) keyEquivalent:@""];
    [menu addItemWithTitle:@"Toggle Floating Pill" action:@selector(togglePanelVisibility) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Open Voice Settings..." action:@selector(openVoiceSettings) keyEquivalent:@""];
    [menu addItemWithTitle:@"Open Accessibility Settings..." action:@selector(openAccessibilitySettings) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit Guy_reader" action:@selector(quitApp) keyEquivalent:@"q"];
    
    self.statusItem.menu = menu;
}

- (void)togglePanelVisibility {
    if ([self.panel isVisible]) {
        [self.panel orderOut:nil];
    } else {
        [self.panel makeKeyAndOrderFront:nil];
    }
}

- (void)openVoiceSettings {
    [self.speechEngine openSystemVoiceSettings];
}

- (void)openAccessibilitySettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)quitApp {
    [self.speechEngine stop];
    [self stopSpeechEngineDaemon];
    [NSApp terminate:nil];
}

#pragma mark - Floating Panel (Guy_reader Pill)

- (void)setupFloatingPanel {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenRect = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1440, 900);

    CGFloat initWidth = 520.0;
    CGFloat initHeight = 60.0;
    CGFloat initX = screenRect.origin.x + (screenRect.size.width - initWidth) / 2.0;
    CGFloat initY = screenRect.origin.y + screenRect.size.height - initHeight - 40.0;

    NSRect panelRect = NSMakeRect(initX, initY, initWidth, initHeight);

    self.panel = [[NSPanel alloc] initWithContentRect:panelRect
                                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable | NSWindowStyleMaskNonactivatingPanel
                                              backing:NSBackingStoreBuffered
                                                defer:NO];

    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.backgroundColor = [NSColor clearColor];
    self.panel.opaque = NO;
    self.panel.hasShadow = YES;
    self.panel.movableByWindowBackground = YES;
    self.panel.minSize = NSMakeSize(440, 48);
    self.panel.maxSize = NSMakeSize(1200, 900);

    // Setup WebKit
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *userContent = [[WKUserContentController alloc] init];
    [userContent addScriptMessageHandler:self name:@"app"];
    [userContent addScriptMessageHandler:self name:@"speech"];
    config.userContentController = userContent;

    self.webView = [[WKWebView alloc] initWithFrame:self.panel.contentView.bounds configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.webView setValue:@NO forKey:@"drawsBackground"];

    // Find ui/index.html in bundle or source directory
    NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
    NSString *htmlPath = [bundlePath stringByAppendingPathComponent:@"ui/index.html"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:htmlPath]) {
        NSString *execDir = [[NSBundle mainBundle] bundlePath];
        htmlPath = [execDir stringByAppendingPathComponent:@"src/ui/index.html"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:htmlPath]) {
            htmlPath = @"/Users/gyklty/Desktop/Guy/TTS/src/ui/index.html";
        }
    }

    NSURL *url = [NSURL fileURLWithPath:htmlPath];
    NSURL *readAccessUrl = [url URLByDeletingLastPathComponent];
    [self.webView loadFileURL:url allowingReadAccessToURL:readAccessUrl];

    [self.panel.contentView addSubview:self.webView];
    [self.panel orderFront:nil];
}

#pragma mark - On-Screen Button Actions

- (void)readSelectionFromActiveApp {
    static NSTimeInterval lastTriggerTime = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - lastTriggerTime < 0.35) {
        return;
    }
    lastTriggerTime = now;
    self.captureRevision++;

    NSRunningApplication *frontApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSRunningApplication *targetApp = frontApp;
    if (!targetApp || [targetApp.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        targetApp = self.lastTargetApp;
    }
    if (!targetApp || [targetApp.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if (app.isActive && ![app.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
                targetApp = app;
                break;
            }
        }
    }

    BOOL (^belongsToTarget)(pid_t, NSRunningApplication *) = ^BOOL(pid_t pid, NSRunningApplication *target) {
        if (!target) return NO;
        if (pid == target.processIdentifier) return YES;
        NSRunningApplication *hitApp = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (!hitApp) return NO;
        if ([hitApp.bundleIdentifier containsString:@"helper"] || [hitApp.bundleIdentifier containsString:@"electron"]) {
            if ([hitApp.bundleIdentifier hasPrefix:target.bundleIdentifier] ||
                [target.bundleIdentifier hasPrefix:hitApp.bundleIdentifier] ||
                [target.localizedName isEqualToString:hitApp.localizedName]) {
                return YES;
            }
        }
        if ([hitApp.bundleIdentifier hasPrefix:target.bundleIdentifier] || [target.bundleIdentifier hasPrefix:hitApp.bundleIdentifier ?: @""]) return YES;
        return NO;
    };

    NSString *bundle = targetApp.bundleIdentifier.lowercaseString ?: @"";
    BOOL browser = [bundle containsString:@"chrome"] || [bundle containsString:@"brave"] ||
        [bundle containsString:@"edge"] || [bundle containsString:@"arc"] || [bundle containsString:@"vivaldi"];
    if (browser) {
        NSUInteger captureId = self.captureRevision;
        [self.speechEngine stop];
        [self.webView evaluateJavaScript:@"window.guyReaderApp && window.guyReaderApp.prepareBrowserRead && window.guyReaderApp.prepareBrowserRead()" completionHandler:nil];
        [self triggerBrowserAction:@"read-from-selection" completion:^(BOOL handled) {
            if (captureId != self.captureRevision) return;
            if (handled) {
                self.browserReading = YES;
                NSUInteger browserSession = ++self.browserSession;
                [self.browserStateTimer invalidate];
                __weak typeof(self) weakSelf = self;
                self.browserStateTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *timer) {
                    [weakSelf refreshBrowserStateForSession:browserSession];
                }];
                [self.webView evaluateJavaScript:@"window.guyReaderApp && window.guyReaderApp.browserStarted()" completionHandler:nil];
            } else if (self.clickedReadingText.length && targetApp && belongsToTarget(self.clickedAppPID, targetApp)) {
                [self deliverTextToReader:self.clickedReadingText];
            } else {
                [self captureDesktopAppText:targetApp];
            }
        }];
        return;
    }
    // An explicit highlight is the strongest reading origin. Check it before
    // the remembered click, because mouse-up at the end of a selection also
    // updates the click observer.
    NSString *selection = targetApp ? [self getSelectedTextViaAccessibility:targetApp.processIdentifier] : nil;
    NSString *origin = GRPreferredReadingText(selection, self.clickedReadingText,
        targetApp && belongsToTarget(self.clickedAppPID, targetApp));
    if (origin.length) {
        [self deliverTextToReader:origin];
        return;
    }

    // The webview owns both local audio and native transport state.
    // If text is already loaded or speech is currently active/paused, toggle playback rather than scraping.
    if (self.readerIsActive || [self.speechEngine isSpeaking] || self.speechEngine.isPaused || self.currentReadingText.length > 0) {
        [self.webView evaluateJavaScript:@"var app = window.guyReaderApp || window.glaidoApp; app && app.togglePlayPause();" completionHandler:nil];
        return;
    }

    // If clickedReadingText wasn't available at the instant of mouse-up (e.g. Electron tree was still waking up),
    // perform hit-testing now at the remembered clickedPoint in targetApp:
    if (self.hasClickedPoint && targetApp && belongsToTarget(self.clickedAppPID, targetApp)) {
        if (targetApp) {
            AXUIElementRef appElem = AXUIElementCreateApplication(targetApp.processIdentifier);
            if (appElem) {
                AXUIElementSetAttributeValue(appElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
                CFRelease(appElem);
            }
        }
        AXUIElementRef system = AXUIElementCreateSystemWide(), hit = NULL;
        if (AXUIElementCopyElementAtPosition(system, self.clickedPoint.x, self.clickedPoint.y, &hit) == kAXErrorSuccess && hit) {
            NSString *txt = GRReadingTextAtElement(hit, self.clickedPoint);
            CFRelease(hit);
            if (txt.length) {
                CFRelease(system);
                self.clickedReadingText = txt;
                [self deliverTextToReader:txt];
                return;
            }
        }
        CFRelease(system);
    }

    if (targetApp) {
        AXUIElementRef appElement = AXUIElementCreateApplication(targetApp.processIdentifier);
        CFTypeRef focused = NULL;
        if (AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess && focused) {
            NSString *remaining = GRReadingTextAtElement((AXUIElementRef)focused, CGPointMake(-1, -1));
            CFRelease(focused);
            if (remaining.length) {
                CFRelease(appElement);
                [self deliverTextToReader:remaining];
                return;
            }
        }
        CFRelease(appElement);
    }

    // Hit-test at current mouse location against accessibility hierarchy
    if (targetApp) {
        NSPoint mouse = NSEvent.mouseLocation;
        CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
        CGPoint point = CGPointMake(mouse.x, top - mouse.y);
        AXUIElementRef system = AXUIElementCreateSystemWide(), hit = NULL;
        if (AXUIElementCopyElementAtPosition(system, point.x, point.y, &hit) == kAXErrorSuccess && hit) {
            pid_t hitPid = 0;
            AXUIElementGetPid(hit, &hitPid);
            if (belongsToTarget(hitPid, targetApp)) {
                NSString *hitText = GRReadingTextAtElement(hit, point);
                CFRelease(hit);
                if (hitText.length) {
                    CFRelease(system);
                    [self deliverTextToReader:hitText];
                    return;
                }
            } else {
                CFRelease(hit);
            }
        }
        CFRelease(system);
    }

    // The webview owns both local audio and native transport state.
    if (self.readerIsActive || [self.speechEngine isSpeaking] || self.speechEngine.isPaused) {
        [self.webView evaluateJavaScript:@"var app = window.guyReaderApp || window.glaidoApp; app && app.togglePlayPause();" completionHandler:nil];
        return;
    }

    // Capture text from frontmost app/selection
    [self captureAndSpeak];
}

#pragma mark - Smart Text & Selection Extraction

- (void)notifyNoTextCaptured {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.panel isVisible]) {
            [self.panel orderFront:nil];
        }
        NSString *js = @"var app = window.guyReaderApp || window.glaidoApp; app && app.showHint && app.showHint('⚠️ Click the text you want, then click Read. Use Paste for clipboard text.');";
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)triggerBrowserBridgeWithCompletion:(void(^)(BOOL handled))completion {
    [self triggerBrowserAction:@"read-from-selection" completion:completion];
}

- (void)triggerBrowserAction:(NSString *)action completion:(void(^ _Nullable)(BOOL handled))completion {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5050/trigger"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"action": action} options:0 error:nil];
    req.timeoutInterval = 2.5;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && data.length > 0) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json && [json[@"status"] isEqualToString:@"ok"] && [json[@"dispatched"] intValue] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(YES);
                });
                return;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO);
        });
    }];
    [task resume];
}

- (void)refreshBrowserStateForSession:(NSUInteger)browserSession {
    if (!self.browserReading || browserSession != self.browserSession) { [self.browserStateTimer invalidate]; return; }
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5050/reader-state"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 0.8;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) return;
        NSDictionary *status = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![status isKindOfClass:[NSDictionary class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.browserReading || browserSession != self.browserSession) return;
            NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
            NSString *payload = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            [self.webView evaluateJavaScript:[NSString stringWithFormat:@"window.guyReaderApp && window.guyReaderApp.browserState(%@)",payload] completionHandler:nil];
            if (![status[@"playing"] boolValue] && ![status[@"paused"] boolValue]) {
                self.browserReading = NO;
                [self.browserStateTimer invalidate];
            }
        });
    }] resume];
}

- (void)captureAndSpeak {
    NSRunningApplication *frontApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSRunningApplication *targetApp = frontApp;

    // If frontApp is Guy_reader itself (e.g. user clicked "Read" on the floating pill),
    // target the app the user was previously viewing!
    if (!targetApp || [targetApp.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        targetApp = self.lastTargetApp;
        if (!targetApp || targetApp.isTerminated || [targetApp.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
            for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
                if (app.activationPolicy == NSApplicationActivationPolicyRegular &&
                    ![app.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]] &&
                    !app.isTerminated &&
                    !app.isHidden) {
                    targetApp = app;
                    break;
                }
            }
        }
    }

    if (!targetApp) {
        [self notifyNoTextCaptured];
        return;
    }

    NSString *bundleId = [targetApp.bundleIdentifier lowercaseString] ?: @"";
    BOOL isBrowser = [bundleId containsString:@"chrome"] ||
                     [bundleId containsString:@"brave"] ||
                     [bundleId containsString:@"edge"] ||
                     [bundleId containsString:@"arc"] ||
                     [bundleId containsString:@"thebrowser"] ||
                     [bundleId containsString:@"opera"] ||
                     [bundleId containsString:@"vivaldi"];

    // 1. If active app is a supported browser, attempt in-situ DOM follow-along via extension bridge
    if (isBrowser) {
        NSUInteger captureId = self.captureRevision;
        [self triggerBrowserBridgeWithCompletion:^(BOOL handled) {
            if (captureId != self.captureRevision) return;
            if (handled) {
                NSLog(@"[GuyReader] Dispatched to browser companion extension");
                return;
            }
            // Fallback: browser extension not active or internal tab -> capture via desktop pipeline
            [self captureDesktopAppText:targetApp];
        }];
        return;
    }

    // 2. Active app is native desktop app (Notes, PDF Preview, Word, Slack, etc.)
    [self captureDesktopAppText:targetApp];
}

- (void)captureDesktopAppText:(NSRunningApplication *)targetApp {
    // 1. Quick check via Accessibility API for selected text (system-wide and app-focused)
    AXUIElementRef sysWide = AXUIElementCreateSystemWide();
    if (sysWide) {
        AXUIElementRef focused = NULL;
        if (AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute, (CFTypeRef *)&focused) == kAXErrorSuccess && focused) {
            CFTypeRef sel = NULL;
            if (AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute, (CFTypeRef *)&sel) == kAXErrorSuccess && sel) {
                if (CFGetTypeID(sel) == CFStringGetTypeID()) {
                    NSString *selStr = (__bridge NSString *)sel;
                    if (selStr.length > 0 && [selStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
                        CFRelease(sel);
                        CFRelease(focused);
                        CFRelease(sysWide);
                        [self deliverTextToReader:selStr];
                        return;
                    }
                }
                CFRelease(sel);
            }
            CFRelease(focused);
        }
        CFRelease(sysWide);
    }

    NSString *axSelected = [self getSelectedTextViaAccessibility:targetApp.processIdentifier];
    if (axSelected && [axSelected stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
        [self deliverTextToReader:axSelected];
        return;
    }

    // 2. Universal Selection Copy via WindowServer focus and Session/HID event streams
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSInteger beforeCount = [pb changeCount];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [targetApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
#pragma clang diagnostic pop

    __weak typeof(self) weakSelf = self;
    NSUInteger captureId = self.captureRevision;
    // Wait 0.20s to allow WindowServer to switch focus to targetApp
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (strongSelf.captureRevision != captureId) return;

        // Try AX after focus
        NSString *axPostFocus = [strongSelf getSelectedTextViaAccessibility:targetApp.processIdentifier];
        if (axPostFocus && [axPostFocus stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
            [strongSelf deliverTextToReader:axPostFocus];
            return;
        }

        // Trigger Cmd+C via AppleScript System Events (highly reliable in Electron / Chromium / macOS apps)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NSDictionary *asErr = nil;
            NSAppleScript *as = [[NSAppleScript alloc] initWithSource:@"tell application \"System Events\" to keystroke \"c\" using {command down}"];
            [as executeAndReturnError:&asErr];
        });

        // Also post via CGEventPost to both Session and HID streams
        CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        if (src) {
            CGEventRef keyDown = CGEventCreateKeyboardEvent(src, (CGKeyCode)8, true); // 8 is 'c'
            CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
            CGEventRef keyUp = CGEventCreateKeyboardEvent(src, (CGKeyCode)8, false);
            CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);

            CGEventPost(kCGSessionEventTap, keyDown);
            CGEventPost(kCGSessionEventTap, keyUp);
            CGEventPost(kCGHIDEventTap, keyDown);
            CGEventPost(kCGHIDEventTap, keyUp);

            CFRelease(keyDown);
            CFRelease(keyUp);
            CFRelease(src);
        }

        [strongSelf pollPasteboardForCopiedText:beforeCount attempts:0 targetApp:targetApp captureId:captureId];
    });
}

- (void)pollPasteboardForCopiedText:(NSInteger)beforeCount attempts:(int)attempts targetApp:(NSRunningApplication *)targetApp captureId:(NSUInteger)captureId {
    if (self.captureRevision != captureId) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    if ([pb changeCount] != beforeCount) {
        NSString *copied = [pb stringForType:NSPasteboardTypeString];
        if (copied && [copied stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
            [self deliverTextToReader:copied];
            return;
        }
    }

    if (attempts < 10) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.035 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf pollPasteboardForCopiedText:beforeCount attempts:attempts + 1 targetApp:targetApp captureId:captureId];
        });
    } else {
        // 3. No mouse selection copied -> Intelligently extract foreground article / post if browser, or notify user
        NSString *bundleId = [targetApp.bundleIdentifier lowercaseString] ?: @"";
        BOOL isBrowserApp = [bundleId containsString:@"safari"] || [bundleId containsString:@"chrome"] || [bundleId containsString:@"brave"] || [bundleId containsString:@"edge"] || [bundleId containsString:@"arc"] || [bundleId containsString:@"opera"];
        if (isBrowserApp) {
            [self extractForegroundContentFromApp:targetApp];
        } else {
            NSString *winText = [self extractTextFromAXWindow:targetApp.processIdentifier];
            if (winText && winText.length > 0) {
                NSString *filtered = [self filterBoilerplate:winText];
                if (filtered && filtered.length > 0) {
                    [self deliverTextToReader:filtered];
                    return;
                }
            }
            [self notifyNoTextCaptured];
        }
    }
}

- (NSString *)getSelectedTextViaAccessibility:(pid_t)pid {
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) return nil;

    AXUIElementRef focused = NULL;
    if (AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute, (CFTypeRef *)&focused) == kAXErrorSuccess && focused) {
        CFTypeRef selText = NULL;
        if (AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute, &selText) == kAXErrorSuccess && selText) {
            if (CFGetTypeID(selText) == CFStringGetTypeID()) {
                NSString *text = (__bridge NSString *)selText;
                CFRelease(selText);
                CFRelease(focused);
                CFRelease(app);
                return text;
            }
            CFRelease(selText);
        }
        CFRelease(focused);
    }
    CFRelease(app);
    return nil;
}

- (void)extractForegroundContentFromApp:(NSRunningApplication *)app {
    NSString *bundleId = [app.bundleIdentifier lowercaseString] ?: @"";

    BOOL isSafari = [bundleId containsString:@"safari"];
    BOOL isChromium = [bundleId containsString:@"chrome"] || [bundleId containsString:@"brave"] || [bundleId containsString:@"edge"] || [bundleId containsString:@"arc"] || [bundleId containsString:@"opera"] || [bundleId containsString:@"vivaldi"];

    if (isSafari) {
        [self extractFromSafari:app];
        return;
    } else if (isChromium) {
        [self extractFromChromium:app];
        return;
    }

    // Fallback for native apps (Notes, TextEdit, Preview, etc.) via AX
    NSString *text = [self extractTextFromAXWindow:app.processIdentifier];
    if (text && text.length > 0) {
        NSString *filtered = [self filterBoilerplate:text];
        if (filtered && filtered.length > 0) {
            [self deliverTextToReader:filtered];
            return;
        }
    }
    // Never fall back to general pasteboard here: notify user clearly
    [self notifyNoTextCaptured];
}

- (NSString *)escapeForAppleScript:(NSString *)input {
    NSString *escaped = [input stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    return escaped;
}

- (void)extractFromSafari:(NSRunningApplication *)app {
    NSString *script = [NSString stringWithFormat:
        @"tell application \"Safari\"\n"
        @"    if (count of documents) > 0 then\n"
        @"        try\n"
        @"            set jsResult to (do JavaScript \"%@\" in front document)\n"
        @"            if jsResult is not missing value and jsResult is not \"\" then\n"
        @"                return jsResult\n"
        @"            end if\n"
        @"        end try\n"
        @"        return text of front document\n"
        @"    end if\n"
        @"end tell\n", [self escapeForAppleScript:kSmartExtractJS]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *err = nil;
        NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
        NSAppleEventDescriptor *desc = [appleScript executeAndReturnError:&err];
        NSString *result = [desc stringValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result && result.length > 0) {
                if ([result hasPrefix:@"__GUY_READER_EXACT_SEL__"]) {
                    NSString *exactSel = [result substringFromIndex:24];
                    [self deliverTextToReader:exactSel];
                    return;
                } else if ([result hasPrefix:@"__GLAIDO_EXACT_SEL__"]) {
                    NSString *exactSel = [result substringFromIndex:20];
                    [self deliverTextToReader:exactSel];
                    return;
                } else {
                    NSString *filtered = [self filterBoilerplate:result];
                    if (filtered.length > 0) {
                        [self deliverTextToReader:filtered];
                        return;
                    }
                }
            }
            
            // AX Fallback
            NSString *axText = [self extractTextFromAXWindow:app.processIdentifier];
            if (axText && axText.length > 0) {
                [self deliverTextToReader:[self filterBoilerplate:axText]];
            } else {
                [self notifyNoTextCaptured];
            }
        });
    });
}

- (void)extractFromChromium:(NSRunningApplication *)app {
    NSString *appName = app.localizedName ?: @"Google Chrome";
    NSString *safeAppName = [appName stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *script = [NSString stringWithFormat:
        @"tell application \"%@\"\n"
        @"    if (count of windows) > 0 then\n"
        @"        try\n"
        @"            set jsResult to (execute active tab of window 1 javascript \"%@\")\n"
        @"            if jsResult is not missing value and jsResult is not \"\" then\n"
        @"                return jsResult\n"
        @"            end if\n"
        @"        end try\n"
        @"    end if\n"
        @"end tell\n", safeAppName, [self escapeForAppleScript:kSmartExtractJS]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *err = nil;
        NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
        NSAppleEventDescriptor *desc = [appleScript executeAndReturnError:&err];
        NSString *result = [desc stringValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result && result.length > 0) {
                if ([result hasPrefix:@"__GUY_READER_EXACT_SEL__"]) {
                    NSString *exactSel = [result substringFromIndex:24];
                    [self deliverTextToReader:exactSel];
                    return;
                } else if ([result hasPrefix:@"__GLAIDO_EXACT_SEL__"]) {
                    NSString *exactSel = [result substringFromIndex:20];
                    [self deliverTextToReader:exactSel];
                    return;
                } else {
                    NSString *filtered = [self filterBoilerplate:result];
                    if (filtered.length > 0) {
                        [self deliverTextToReader:filtered];
                        return;
                    }
                }
            }
            
            // If Chrome AppleScript didn't return text (e.g. JS Apple Events disabled), try AX
            NSString *axText = [self getSelectedTextViaAccessibility:app.processIdentifier];
            if (axText && axText.length > 0) {
                [self deliverTextToReader:axText];
                return;
            }

            NSString *winText = [self extractTextFromAXWindow:app.processIdentifier];
            if (winText && winText.length > 0) {
                [self deliverTextToReader:[self filterBoilerplate:winText]];
            } else {
                [self notifyNoTextCaptured];
            }
        });
    });
}

- (NSString *)filterBoilerplate:(NSString *)rawText {
    if (!rawText || rawText.length == 0) return @"";
    NSArray *lines = [rawText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *cleanLines = [NSMutableArray array];

    NSRegularExpression *alphaNumRegex = [NSRegularExpression regularExpressionWithPattern:@"[\\p{L}\\p{N}]" options:0 error:nil];
    NSRegularExpression *timestampRegex = [NSRegularExpression regularExpressionWithPattern:@"^[·\\s]*[0-9]+[smhdwy](?:\\s+ago)?$" options:NSRegularExpressionCaseInsensitive error:nil];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;

        // Skip lines that have no letters or numbers
        if ([alphaNumRegex numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)] == 0) {
            continue;
        }

        // Twitter action words and UI noise
        if ([trimmed isEqualToString:@"Follow"] || [trimmed isEqualToString:@"Share"] ||
            [trimmed isEqualToString:@"Reply"] || [trimmed isEqualToString:@"Like"] ||
            [trimmed isEqualToString:@"Repost"] || [trimmed isEqualToString:@"Subscribe"] ||
            [trimmed isEqualToString:@"Promoted"] || [trimmed isEqualToString:@"Show more"] ||
            [trimmed isEqualToString:@"Show this thread"] || [trimmed isEqualToString:@"Pinned Tweet"] ||
            [trimmed isEqualToString:@"Bookmark"] || [trimmed isEqualToString:@"Translate post"] ||
            [trimmed isEqualToString:@"View quotes"]) {
            continue;
        }

        // Twitter metrics
        if ([trimmed hasSuffix:@"Retweets"] || [trimmed hasSuffix:@"Reposts"] ||
            [trimmed hasSuffix:@"Likes"] || [trimmed hasSuffix:@"Views"] ||
            [trimmed hasSuffix:@"Quotes"] || [trimmed hasSuffix:@"Replies"]) {
            continue;
        }

        // Timestamp
        if ([timestampRegex numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)] > 0) {
            continue;
        }

        [cleanLines addObject:trimmed];
    }

    if (cleanLines.count == 0) {
        return @"";
    }

    return [cleanLines componentsJoinedByString:@"\n\n"];
}

- (NSString *)extractTextFromAXWindow:(pid_t)pid {
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) return nil;

    AXUIElementRef window = NULL;
    if (AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess || !window) {
        AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute, (CFTypeRef *)&window);
    }

    if (!window) {
        CFRelease(app);
        return nil;
    }

    NSMutableArray<NSString *> *fragments = [NSMutableArray array];
    [self collectTextFromAXElement:window depth:0 intoArray:fragments];
    CFRelease(window);
    CFRelease(app);

    if (fragments.count == 0) return nil;
    return [fragments componentsJoinedByString:@"\n\n"];
}

- (void)collectTextFromAXElement:(AXUIElementRef)elem depth:(int)depth intoArray:(NSMutableArray<NSString *> *)fragments {
    if (depth > 10 || fragments.count > 60) return;

    CFTypeRef role = NULL;
    BOOL isControl = NO;
    if (AXUIElementCopyAttributeValue(elem, kAXRoleAttribute, (CFTypeRef *)&role) == kAXErrorSuccess && role) {
        if (CFGetTypeID(role) == CFStringGetTypeID()) {
            NSString *roleStr = (__bridge NSString *)role;
            if ([roleStr isEqualToString:NSAccessibilityButtonRole] ||
                [roleStr isEqualToString:NSAccessibilityPopUpButtonRole] ||
                [roleStr isEqualToString:NSAccessibilityMenuButtonRole] ||
                [roleStr isEqualToString:NSAccessibilityScrollBarRole]) {
                isControl = YES;
            }
        }
        CFRelease(role);
    }
    if (isControl) return;

    CFTypeRef val = NULL;
    if (AXUIElementCopyAttributeValue(elem, kAXValueAttribute, (CFTypeRef *)&val) == kAXErrorSuccess && val) {
        if (CFGetTypeID(val) == CFStringGetTypeID()) {
            NSString *str = [(__bridge NSString *)val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (str.length > 0 && ![fragments containsObject:str]) {
                [fragments addObject:str];
            }
        }
        CFRelease(val);
    }

    CFTypeRef title = NULL;
    if (AXUIElementCopyAttributeValue(elem, kAXTitleAttribute, (CFTypeRef *)&title) == kAXErrorSuccess && title) {
        if (CFGetTypeID(title) == CFStringGetTypeID()) {
            NSString *str = [(__bridge NSString *)title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (str.length > 0 && ![fragments containsObject:str]) {
                [fragments addObject:str];
            }
        }
        CFRelease(title);
    }

    CFArrayRef children = NULL;
    if (AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute, (CFTypeRef *)&children) == kAXErrorSuccess && children) {
        CFIndex count = CFArrayGetCount(children);
        for (CFIndex i = 0; i < count; i++) {
            AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
            [self collectTextFromAXElement:child depth:depth + 1 intoArray:fragments];
        }
        CFRelease(children);
    }
}

- (void)deliverTextToReader:(NSString *)text {
    if (!text || text.length == 0) return;

    NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length == 0) return;

    self.captureRevision++;
    if (self.browserReading) [self triggerBrowserAction:@"stop" completion:nil];
    self.browserReading = NO;
    [self.speechEngine stop];
    self.speechRequestId = 0;
    self.currentReadingText = clean;
    self.readingClipboardChangeCount = [NSPasteboard generalPasteboard].changeCount;

    if (![self.panel isVisible]) {
        [self.panel orderFront:nil];
    }

    [self sendTextToWebView:clean];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation * _Null_unspecified)navigation {
    self.isWebViewReady = YES;
    if (self.pendingText) {
        [self sendTextToWebView:self.pendingText];
        self.pendingText = nil;
    }
}

- (void)sendTextToWebView:(NSString *)text {
    if (!text || text.length == 0) return;
    if (!self.isWebViewReady) {
        self.pendingText = text;
        return;
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@[text] options:0 error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    NSString *js = [NSString stringWithFormat:@"var app = window.guyReaderApp || window.glaidoApp; app && app.receiveText(%@[0]);", jsonString];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *body = [message.body isKindOfClass:[NSDictionary class]] ? (NSDictionary *)message.body : @{};
    NSString *action = body[@"action"];
    if (body[@"requestId"]) self.speechRequestId = [body[@"requestId"] unsignedIntegerValue];

    if ([action isEqualToString:@"readSelection"] || [action isEqualToString:@"playButtonClicked"]) {
        [self readSelectionFromActiveApp];
    } else if ([action isEqualToString:@"playbackState"]) {
        self.readerIsActive = [body[@"active"] boolValue];
    } else if ([action isEqualToString:@"textLoaded"]) {
        self.captureRevision++;
        self.currentReadingText = body[@"text"];
        self.readingClipboardChangeCount = [NSPasteboard generalPasteboard].changeCount;
    } else if ([action isEqualToString:@"pasteClipboard"]) {
        NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        if (clip && [clip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
            [self deliverTextToReader:clip];
        }
    } else if ([action isEqualToString:@"minimize"]) {
        [self.speechEngine pause];
        [self.panel orderOut:nil];
    } else if ([action isEqualToString:@"exit"]) {
        [self quitApp];
    } else if ([action isEqualToString:@"close"]) {
        // Safe close: pause speech and hide panel without terminating the app
        [self.speechEngine pause];
        [self.panel orderOut:nil];
    } else if ([action isEqualToString:@"dragWindow"] || [action isEqualToString:@"moveWindowDelta"]) {
        if (body[@"dx"] != nil || body[@"dy"] != nil) {
            CGFloat dx = [body[@"dx"] doubleValue];
            CGFloat dy = [body[@"dy"] doubleValue];
            NSRect frame = self.panel.frame;
            frame.origin.x += dx;
            frame.origin.y -= dy; // In screen coordinates Y increases downward; in Cocoa Y increases upward

            NSScreen *screen = self.panel.screen ?: [NSScreen mainScreen];
            if (screen) {
                NSRect screenRect = screen.visibleFrame;
                CGFloat minX = screenRect.origin.x - frame.size.width + 60.0;
                CGFloat maxX = screenRect.origin.x + screenRect.size.width - 60.0;
                CGFloat minY = screenRect.origin.y;
                CGFloat maxY = screenRect.origin.y + screenRect.size.height - 30.0;

                if (frame.origin.x < minX) frame.origin.x = minX;
                if (frame.origin.x > maxX) frame.origin.x = maxX;
                if (frame.origin.y < minY) frame.origin.y = minY;
                if (frame.origin.y > maxY) frame.origin.y = maxY;
            }
            [self.panel setFrameOrigin:frame.origin];
        } else {
            NSEvent *currentEvent = [NSApp currentEvent];
            if (currentEvent) {
                [self.panel performWindowDragWithEvent:currentEvent];
            }
        }
    } else if ([action isEqualToString:@"resizeWindow"]) {
        CGFloat height = [body[@"height"] doubleValue];
        CGFloat width = [body[@"width"] doubleValue];
        if (height <= 0) height = 60.0;
        if (width <= 0) width = 460.0;

        NSRect frame = self.panel.frame;
        CGFloat diffY = height - frame.size.height;
        frame.size.height = height;
        frame.size.width = width;
        frame.origin.y -= diffY; // Expand downwards

        // Prevent expanding off the bottom or top edge of the visible screen
        NSScreen *screen = self.panel.screen ?: [NSScreen mainScreen];
        if (screen) {
            NSRect screenRect = screen.visibleFrame;
            if (frame.size.height > screenRect.size.height) {
                frame.size.height = screenRect.size.height;
            }
            if (frame.origin.y < screenRect.origin.y) {
                frame.origin.y = screenRect.origin.y;
            }
            if (frame.origin.y + frame.size.height > screenRect.origin.y + screenRect.size.height) {
                frame.origin.y = screenRect.origin.y + screenRect.size.height - frame.size.height;
            }
        }
        [self.panel setFrame:frame display:YES animate:YES];
    } else if ([action isEqualToString:@"resizeWindowDelta"]) {
        CGFloat dw = [body[@"dw"] doubleValue];
        CGFloat dh = [body[@"dh"] doubleValue];
        NSRect frame = self.panel.frame;
        CGFloat newWidth = MAX(360.0, MIN(1200.0, frame.size.width + dw));
        CGFloat newHeight = MAX(48.0, MIN(900.0, frame.size.height + dh));
        CGFloat diffY = newHeight - frame.size.height;
        frame.size.width = newWidth;
        frame.size.height = newHeight;
        frame.origin.y -= diffY;

        NSScreen *screen = self.panel.screen ?: [NSScreen mainScreen];
        if (screen) {
            NSRect screenRect = screen.visibleFrame;
            if (frame.size.height > screenRect.size.height) {
                frame.size.height = screenRect.size.height;
            }
            if (frame.origin.y < screenRect.origin.y) {
                frame.origin.y = screenRect.origin.y;
            }
            if (frame.origin.y + frame.size.height > screenRect.origin.y + screenRect.size.height) {
                frame.origin.y = screenRect.origin.y + screenRect.size.height - frame.size.height;
            }
        }
        [self.panel setFrame:frame display:YES animate:NO];
    } else if ([action isEqualToString:@"voiceChanged"]) {
        NSString *voice = body[@"voice"];
        if (voice) {
            self.speechEngine.currentVoice = voice;
            NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5050/trigger"];
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            req.HTTPMethod = @"POST";
            [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"action": @"set-voice", @"voice": voice} options:0 error:nil];
            req.timeoutInterval = 1.0;
            [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
        }
    } else if ([action isEqualToString:@"setSpeed"]) {
        float speed = [body[@"speed"] floatValue];
        self.speechEngine.speedRate = speed;
    } else if ([action isEqualToString:@"openSystemVoiceSettings"]) {
        [self.speechEngine openSystemVoiceSettings];
    } else if ([action isEqualToString:@"pause"]) {
        if (self.browserReading) [self triggerBrowserAction:@"pause" completion:nil];
        [self.speechEngine pause];
    } else if ([action isEqualToString:@"resume"]) {
        if (self.browserReading) [self triggerBrowserAction:@"resume" completion:nil];
        [self.speechEngine resume];
    } else if ([action isEqualToString:@"stop"]) {
        self.captureRevision++;
        self.browserSession++;
        [self triggerBrowserAction:@"stop" completion:nil];
        self.browserReading = NO;
        [self.browserStateTimer invalidate];
        self.speechRequestId = 0;
        [self.speechEngine stop];
    } else if ([action isEqualToString:@"speak"]) {
        NSString *text = body[@"text"];
        NSString *voice = body[@"voice"];
        float rate = [body[@"rate"] floatValue];
        [self.speechEngine speakText:text voice:voice rate:rate];
    } else if ([action isEqualToString:@"speakEdge"] || [action isEqualToString:@"edgeTTS"]) {
        NSString *text = body[@"text"];
        NSString *voice = body[@"voice"];
        float rate = [body[@"rate"] floatValue];
        [self.speechEngine speakEdgeTTS:text voice:voice rate:rate];
    } else if ([action isEqualToString:@"elevenTTS"]) {
        NSString *text = body[@"text"];
        NSString *voiceId = body[@"voiceId"];
        NSString *apiKey = body[@"key"];
        float rate = [body[@"rate"] floatValue];
        [self.speechEngine speakElevenLabs:text voiceId:voiceId apiKey:apiKey rate:rate];
    } else if ([action isEqualToString:@"googleTTS"]) {
        NSString *text = body[@"text"];
        NSString *voice = body[@"voice"];
        NSString *apiKey = body[@"key"];
        float rate = [body[@"rate"] floatValue];
        [self.speechEngine speakGoogleTTS:text voice:voice apiKey:apiKey rate:rate];
    }
}

#pragma mark - SpeechEngineDelegate

- (void)speechWillSpeakRange:(NSRange)range {
    NSUInteger requestId = self.speechRequestId;
    if (!requestId) return;
    NSString *js = [NSString stringWithFormat:@"window.guyReaderApp && window.guyReaderApp.onWordBoundary(%lu,%lu,%lu)",
        (unsigned long)requestId, (unsigned long)range.location, (unsigned long)range.length];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)speechDidFinishSentence {
    NSUInteger requestId = self.speechRequestId;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!requestId || requestId != self.speechRequestId) return;
        NSString *js = [NSString stringWithFormat:@"var app = window.guyReaderApp || window.glaidoApp; app && app.onSentenceComplete(%lu);", (unsigned long)requestId];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)speechDidStartSpeaking {
    NSUInteger requestId = self.speechRequestId;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!requestId || requestId != self.speechRequestId) return;
        NSString *js = [NSString stringWithFormat:@"var app = window.guyReaderApp || window.glaidoApp; app && app.onSpeechStart(%lu);", (unsigned long)requestId];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)speechDidPause {
    NSUInteger requestId = self.speechRequestId;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!requestId || requestId != self.speechRequestId) return;
        NSString *js = [NSString stringWithFormat:@"var app = window.guyReaderApp || window.glaidoApp; app && app.onNativePause(%lu);", (unsigned long)requestId];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

@end

#pragma mark - Main Entry Point

int main(int argc, const char * _Nonnull argv[_Nonnull]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}

NS_ASSUME_NONNULL_END

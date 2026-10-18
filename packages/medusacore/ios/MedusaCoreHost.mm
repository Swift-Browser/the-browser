#import <Security/Security.h>
#import <objc/runtime.h>

#import "MedusaCoreEarlyWindow.h"
#import "MedusaCoreInternal.h"
#import "MedusaCoreServices.h"
#import "MedusaCoreNavigationDownloads.h"
#import "MedusaCoreStartup.h"
#import "MedusaCoreWebView.h"
#import "MedusaCoreWebViewInternal.h"

#include <cctype>
#include <cstring>
#include <string>
#include <vector>

namespace {

id<NSApplicationDelegate> (^gMakeDelegate)(void);
id<NSApplicationDelegate> gAppDelegate;
BOOL gStarted;
NSString *gDataDirectory;

BOOL gMenuShortcutsReady;

void SendReservedShortcuts() {
  if (!gStarted || !gMenuShortcutsReady || ![MedusaCoreEngine respondsToSelector:@selector(reservedShortcutsChanged)]) return;
  [MedusaCoreEngine reservedShortcutsChanged];
}

void WatchReservedShortcuts() {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:@"MedusaMenuShortcutsChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
      gMenuShortcutsReady = YES;
      SendReservedShortcuts();
    }];
    [center addObserverForName:NSTextInputContextKeyboardSelectionDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *) { SendReservedShortcuts(); }];
  });
  SendReservedShortcuts();
}

NSMutableDictionary<NSString *, MedusaCoreProfile *> *Profiles() {
  static NSMutableDictionary *profiles = [NSMutableDictionary dictionary];
  return profiles;
}

NSMutableDictionary<NSString *, NSMutableArray *> *ProfileWaiters() {
  static NSMutableDictionary *waiters = [NSMutableDictionary dictionary];
  return waiters;
}

NSMutableSet<NSString *> *DeletedProfiles() {
  static NSMutableSet *deleted = [NSMutableSet set];
  return deleted;
}

NSMutableSet<NSString *> *ReleasedPrivateNames() {
  static NSMutableSet *released = [NSMutableSet set];
  return released;
}

NSMutableDictionary<NSString *, void (^)(MedusaCoreProfile *)> *DeletionsAfterLoad() {
  static NSMutableDictionary *deletions = [NSMutableDictionary dictionary];
  return deletions;
}

NSString *DirectoryName(NSString *name) {
  return name.length ? [@"Profile " stringByAppendingString:name] : @"Default";
}

NSString *InstalledDataDirectory() {
  NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
  NSString *bundleId = NSBundle.mainBundle.bundleIdentifier ?: @"com.medusa.browser";
  return [[support stringByAppendingPathComponent:bundleId] stringByAppendingPathComponent:@"Chromium"];
}

bool IsTeamSigned() {
  SecCodeRef code = nullptr;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess) return false;
  CFDictionaryRef info = nullptr;
  OSStatus status = SecCodeCopySigningInformation((SecStaticCodeRef)code, kSecCSSigningInformation, &info);
  CFRelease(code);
  if (status != errSecSuccess || !info) return false;
  bool team = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier) != nullptr;
  CFRelease(info);
  return team;
}

}

@interface MedusaCoreBootstrapDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, readonly) NSMutableArray<NSURL *> *urls;
@end

@implementation MedusaCoreBootstrapDelegate
- (instancetype)init {
  if ((self = [super init])) _urls = [NSMutableArray array];
  return self;
}
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
  [_urls addObjectsFromArray:urls];
}
@end

namespace {
MedusaCoreBootstrapDelegate *gBootstrap;
bool gScratchDataDir = false;
bool gAppKitWillFinish = false;
bool gAppKitDidFinish = false;
NSArray<NSURL *> *gPendingLaunchURLs;
NSArray<NSURL *> *gLaunchLinks;
bool gLinksHandled = false;
bool gJSStarted = false;
void (^gEventHandler)(NSString *, NSDictionary *);
void (^gChromeUIHandler)(NSString *, NSDictionary *);
void (^gExtensionsEventHandler)(NSString *, NSDictionary *);
NSMutableDictionary<NSString *, NSDictionary *> *gInstallPrompts = [NSMutableDictionary dictionary];
}

static bool LaunchTabSwitchedOff(NSString *dir) {
  if (const char *env = getenv("MEDUSA_SWITCHES") ?: getenv("MEDUSA_SWITCHES")) {
    NSNumber *said = nil;
    for (NSString *part in [@(env) componentsSeparatedByString:@","]) {
      NSArray<NSString *> *pair = [part componentsSeparatedByString:@"="];
      if (pair.count != 2) continue;
      NSString *name = [pair[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      NSString *value = [pair[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      if (![name isEqualToString:@"launchTab"]) continue;
      if ([@[ @"off", @"0", @"false" ] containsObject:value]) said = @NO;
      else if ([@[ @"on", @"1", @"true" ] containsObject:value]) said = @YES;
    }
    if (said) return !said.boolValue;
  }
  NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"switches-cache.json"]];
  NSDictionary *cache = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  NSDictionary *switches = [cache isKindOfClass:NSDictionary.class] && [cache[@"switches"] isKindOfClass:NSDictionary.class] ? cache[@"switches"] : nil;
  return [switches[@"launchTab"] isEqual:@NO];
}

static NSString *AppDataDirectory() {
  NSString *dir = gScratchDataDir ? [gDataDirectory stringByDeletingLastPathComponent] : nil;
  if (dir) return dir;
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  return [support URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier ?: @"Medusa"].path;
}

static NSDictionary *SavedSession(NSString *dir) {
  NSData *data = dir ? [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"session.json"]] : nil;
  NSDictionary *session = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  return [session isKindOfClass:NSDictionary.class] ? session : nil;
}

static void ParkLaunchLinks(NSArray<NSURL *> *links, NSString *dir, NSDictionary *session) {
  NSString *linkProfile = [session[@"linkProfile"] isKindOfClass:NSString.class] ? session[@"linkProfile"] : nil;
  if (!links.count || !linkProfile || LaunchTabSwitchedOff(dir)) return;
  NSMutableArray<NSString *> *urls = [NSMutableArray array];
  for (NSURL *link in links)
    if (!link.isFileURL && link.absoluteString.length) [urls addObject:link.absoluteString];
  [MedusaCoreWebView startLinkTabs:urls profile:linkProfile];
}

static void LinksArrived(NSArray<NSURL *> *urls) {
  if (gLinksHandled || !urls.count) return;
  gLinksHandled = true;
  if (!gJSStarted) {
    gLaunchLinks = [urls copy];
    return;
  }
  NSString *dir = AppDataDirectory();
  ParkLaunchLinks(urls, dir, SavedSession(dir));
}

static void ReportLoweredWindowOcclusion() {
  void (^report)(NSWindow *) = ^(NSWindow *window) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidChangeOcclusionStateNotification object:window];
    });
  };
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  for (NSNotificationName name in @[ NSWindowDidMiniaturizeNotification, NSWindowDidDeminiaturizeNotification ])
    [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) { report(note.object); }];
}

static void StartLaunchTab() {
  gJSStarted = true;
  NSString *dir = AppDataDirectory();
  NSDictionary *session = SavedSession(dir);
  NSArray<NSURL *> *links = gLaunchLinks;
  gLaunchLinks = nil;
  ParkLaunchLinks(links, dir, session);
  NSDictionary *hint = session[@"launchTab"];
  if (![hint isKindOfClass:NSDictionary.class]) return;
  NSString *key = hint[@"id"], *url = hint[@"url"], *profile = hint[@"profile"];
  if (![key isKindOfClass:NSString.class] || ![url isKindOfClass:NSString.class] || ![profile isKindOfClass:NSString.class]) return;
  [MedusaCoreWebView startLaunchTab:key url:url profile:profile];
  if (MedusaCoreTab *tab = MedusaCoreWebView.launchTab) [MedusaCoreEarlyWindow attachPage:tab key:key];
}

static bool gLaunchedHidden;
static bool gEarlyWindowPending;
static bool gLaunchedForDocuments;

static bool OnboardingPending(NSString *dir) {
  NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"onboarding.json"]];
  NSDictionary *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![saved isKindOfClass:NSDictionary.class]) return false;
  const bool completed = [saved[@"completedAt"] isKindOfClass:NSNumber.class] && [saved[@"completedAt"] doubleValue] > 0;
  return !completed && [saved[@"startedAt"] isKindOfClass:NSNumber.class];
}

static void TryEarlyWindow() {
  if (MedusaCoreEarlyWindow.switchedOff) return;
  NSString *dir = AppDataDirectory();
  if (gLaunchedHidden || gLaunchedForDocuments || NSApp.isHidden || gBootstrap.urls.count || LaunchTabSwitchedOff(dir) || OnboardingPending(dir)) return;
  NSDictionary *session = SavedSession(dir);
  NSDictionary *hint = session[@"launchTab"];
  NSString *focused = session[@"focusedWindowId"];
  if (![hint isKindOfClass:NSDictionary.class] || ![focused isKindOfClass:NSString.class]) return;
  NSString *key = hint[@"id"], *url = hint[@"url"], *profile = hint[@"profile"];
  if (![key isKindOfClass:NSString.class] || ![url isKindOfClass:NSString.class] || ![profile isKindOfClass:NSString.class]) return;
  NSDictionary *window = nil;
  for (NSDictionary *w in [session[@"windows"] isKindOfClass:NSArray.class] ? session[@"windows"] : @[])
    if ([w isKindOfClass:NSDictionary.class] && [w[@"id"] isEqual:focused]) window = w;
  if (!window || [window[@"incognito"] boolValue] || window[@"kind"] || ![window[@"frame"] isKindOfClass:NSArray.class]) return;
  if (![window[@"tabIds"] isKindOfClass:NSArray.class] || ![window[@"tabIds"] containsObject:key]) return;
  for (NSDictionary *split in [session[@"splits"] isKindOfClass:NSArray.class] ? session[@"splits"] : @[])
    if ([split isKindOfClass:NSDictionary.class] && [split[@"tabIds"] isKindOfClass:NSArray.class] && [split[@"tabIds"] containsObject:key]) return;
  NSDictionary *backdrop = [session[@"launchBackdrop"] isKindOfClass:NSDictionary.class] ? session[@"launchBackdrop"] : nil;
  const bool dark = [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameDarkAqua, NSAppearanceNameAqua ]]
      isEqualToString:NSAppearanceNameDarkAqua];
  if (!backdrop || ![backdrop[@"dark"] isKindOfClass:NSNumber.class] || [backdrop[@"dark"] boolValue] != dark) return;
  if (![MedusaCoreEarlyWindow canShowWindow:focused session:session]) return;
  if (!medusacore_host::LoadedProfile(profile)) return;
  [MedusaCoreWebView startLaunchTab:key url:url profile:profile];
  if (![MedusaCoreEarlyWindow showWindow:focused frame:window[@"frame"] key:key profile:profile backdrop:backdrop]) return;
  if (MedusaCoreTab *tab = MedusaCoreWebView.launchTab) [MedusaCoreEarlyWindow attachPage:tab key:key];
}

static void StartEarlyWindow() {
  @autoreleasepool {
    TryEarlyWindow();
    [MedusaCoreEarlyWindow discardPrefetch];
  }
}

@interface MedusaCoreHostEngineDelegate : NSObject <MedusaCoreEngineDelegate>
@end

@implementation MedusaCoreHostEngineDelegate

- (void)engineDidStart {
  NSLog(@"[medusacore] engine started (Chromium %@)", MedusaCoreEngine.sharedEngine.chromiumVersion);
  gStarted = YES;
  WatchReservedShortcuts();
  medusacore_host::InstallActivationGuardsLate();
  if (gScratchDataDir && medusacore_host::Background())
    medusacore_host::InstallTestCrashGuard([gDataDirectory stringByDeletingLastPathComponent]);
  MedusaCoreEngine *engine = MedusaCoreEngine.sharedEngine;
  if (MedusaCoreProfile *profile = medusacore_host::PersonalIfLoaded(engine)) Profiles()[@""] = profile;
  medusacore_host::LoadContentBlocker(@"");
  [MedusaCoreWebView installScrollZoom];
  [MedusaCoreWebView installSwitchPrewarm];
  [MedusaCoreServices watchDownloads:@""];

  NSBundle *bundle = [NSBundle bundleForClass:MedusaCoreHostEngineDelegate.class];
  NSString *path = [bundle pathForResource:@"page_script" ofType:@"js"];
  NSString *script = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
  if (script && [engine respondsToSelector:@selector(setPageScript:)]) engine.pageScript = script;
  if (gAppKitDidFinish) StartEarlyWindow();
  else gEarlyWindowPending = true;

  CFRunLoopObserverRef idle = CFRunLoopObserverCreateWithHandler(
      nullptr, kCFRunLoopBeforeWaiting, false, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity) {
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
        __block id started = [NSNotificationCenter.defaultCenter
            addObserverForName:@"RCTJavaScriptWillStartExecutingNotification"
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *) {
                      [NSNotificationCenter.defaultCenter removeObserver:started];
                      started = nil;
                      dispatch_async(dispatch_get_main_queue(), ^{ StartLaunchTab(); });
                    }];
        [self launchApp];
      });
  CFRunLoopAddObserver(CFRunLoopGetMain(), idle, kCFRunLoopCommonModes);
  CFRelease(idle);
}

- (void)launchApp {
  NSArray<NSURL *> *launchURLs = gBootstrap.urls.copy;
  LinksArrived(launchURLs);
  gAppDelegate = gMakeDelegate();
  const SEL openURLs = @selector(application:openURLs:);
  if (Method open = class_getInstanceMethod([gAppDelegate class], openURLs)) {
    IMP original = method_getImplementation(open);
    method_setImplementation(open, imp_implementationWithBlock(^(id delegate, NSApplication *app, NSArray<NSURL *> *urls) {
      LinksArrived(urls);
      ((void (*)(id, SEL, NSApplication *, NSArray<NSURL *> *))original)(delegate, openURLs, app, urls);
    }));
  }
  NSApp.delegate = gAppDelegate;
  gBootstrap = nil;
  NSNotification *note = [NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:NSApp];
  if (gAppKitWillFinish && [gAppDelegate respondsToSelector:@selector(applicationWillFinishLaunching:)])
    [gAppDelegate applicationWillFinishLaunching:note];
  if (!gAppKitDidFinish) {
    NSLog(@"[medusacore] app delegate %@ set before AppKit finished launching", NSStringFromClass([gAppDelegate class]));
    gPendingLaunchURLs = launchURLs;
    return;
  }
  note = [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp];
  if ([gAppDelegate respondsToSelector:@selector(applicationDidFinishLaunching:)])
    [gAppDelegate applicationDidFinishLaunching:note];
  NSLog(@"[medusacore] app delegate %@ launched", NSStringFromClass([gAppDelegate class]));
  if (launchURLs.count && [gAppDelegate respondsToSelector:@selector(application:openURLs:)])
    [gAppDelegate application:NSApp openURLs:launchURLs];
}

- (void)engineWillShutDown {
  gStarted = NO;
}

- (void)engineQuitCancelled {
  NSLog(@"[medusacore] quit cancelled");
  [NSNotificationCenter.defaultCenter postNotificationName:@"MedusaCoreQuitCancelled" object:nil];
}

- (void)engine:(MedusaCoreEngine *)engine permissionRequest:(NSDictionary *)request tab:(MedusaCoreTab *)tab {
  NSMutableDictionary *payload = [request mutableCopy];
  payload[@"browserId"] = @(tab ? medusacore_host::BrowserId(tab) : 0);
  if (gEventHandler) gEventHandler(@"permission", payload);
}

- (void)engine:(MedusaCoreEngine *)engine deviceChooser:(NSDictionary *)chooser tab:(MedusaCoreTab *)tab {
  NSMutableDictionary *payload = [chooser mutableCopy];
  payload[@"browserId"] = @(tab ? medusacore_host::BrowserId(tab) : 0);
  if (auto handler = MedusaCoreHost.chromeUIHandler) handler(@"deviceChooser", payload);
  else if ([payload[@"open"] boolValue] && [MedusaCoreEngine respondsToSelector:@selector(cancelDeviceChooser:)])
    [MedusaCoreEngine cancelDeviceChooser:[payload[@"id"] intValue]];
}

- (void)engine:(MedusaCoreEngine *)engine castDialog:(NSDictionary *)dialog tab:(MedusaCoreTab *)tab {
  NSMutableDictionary *payload = [dialog mutableCopy];
  payload[@"browserId"] = @(tab ? medusacore_host::BrowserId(tab) : 0);
  if (gChromeUIHandler) gChromeUIHandler(@"castDialog", payload);
  else if ([payload[@"open"] boolValue] && [MedusaCoreEngine respondsToSelector:@selector(closeCastDialog:)])
    [MedusaCoreEngine closeCastDialog:[payload[@"id"] intValue]];
}

- (void)engine:(MedusaCoreEngine *)engine castRoutes:(NSArray *)routes profile:(MedusaCoreProfile *)profile {
  if (!gChromeUIHandler) return;
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  if (profile.offTheRecord)
    for (NSString *name in medusacore_host::LoadedProfileNames())
      if (medusacore_host::LoadedProfile(name) == profile) [names addObject:name];
  if (!names.count) [names addObject:medusacore_host::ProfileName(profile)];
  for (NSString *name in names) gChromeUIHandler(@"castRoutes", @{@"profile" : name, @"routes" : routes ?: @[]});
}

- (void)engine:(MedusaCoreEngine *)engine extensionSidePanel:(NSDictionary *)panel tab:(MedusaCoreTab *)tab {
  NSMutableDictionary *payload = [panel mutableCopy];
  payload[@"browserId"] = @(tab ? medusacore_host::BrowserId(tab) : 0);
  if (gChromeUIHandler) gChromeUIHandler(@"sidePanel", payload);
}

- (BOOL)engine:(MedusaCoreEngine *)engine extensionActionPopup:(NSDictionary *)popup tab:(MedusaCoreTab *)tab {
  if (!gChromeUIHandler || !tab) {
    NSLog(@"[medusacore] action.openPopup for %@: %@", popup[@"extensionId"], tab ? @"the app isn't listening yet" : @"no tab");
    return NO;
  }
  NSMutableDictionary *payload = [popup mutableCopy];
  payload[@"browserId"] = @(medusacore_host::BrowserId(tab));
  gChromeUIHandler(@"actionPopup", payload);
  return YES;
}

- (BOOL)engineIsReservedKey:(NSString *)key unshiftedKey:(NSString *)unshiftedKey modifiers:(NSEventModifierFlags)modifiers {
  return medusacore_host::IsReservedBinding(key, unshiftedKey, modifiers);
}

- (BOOL)engineIsReservedKeyEvent:(NSEvent *)event {
  return event.type == NSEventTypeKeyDown && medusacore_host::IsReservedKeyEvent(event);
}

- (BOOL)engine:(MedusaCoreEngine *)engine extensionActionShortcut:(NSDictionary *)shortcut tab:(MedusaCoreTab *)tab {
  if (!gChromeUIHandler || !tab) return NO;
  NSMutableDictionary *payload = [shortcut mutableCopy];
  payload[@"browserId"] = @(medusacore_host::BrowserId(tab));
  gChromeUIHandler(@"actionShortcut", payload);
  return YES;
}

- (void)engine:(MedusaCoreEngine *)engine extensionInstallPrompt:(NSDictionary *)prompt tab:(MedusaCoreTab *)tab {
  NSMutableDictionary *payload = [prompt mutableCopy];
  payload[@"browserId"] = @(tab ? medusacore_host::BrowserId(tab) : 0);
  gInstallPrompts[payload[@"requestId"] ?: @""] = payload;
  if (gExtensionsEventHandler) gExtensionsEventHandler(@"installPrompt", payload);
}

- (void)engine:(MedusaCoreEngine *)engine permissionRequestDismissed:(NSString *)requestId {
  if (gEventHandler) gEventHandler(@"permissionDismissed", @{@"id" : requestId ?: @""});
}

- (MedusaCoreWindow *)engineWindowForNewBrowserOfProfile:(MedusaCoreProfile *)profile type:(NSString *)type {
  if (![type isEqualToString:@"normal"] && ![type isEqualToString:@"popup"]) return nil;
  if ([type isEqualToString:@"normal"] && !profile.offTheRecord)
    if (MedusaCoreWindowController *made = [MedusaCoreWindowController chromeMadeWindowForProfile:profile]) return made.coreWindow;
  return [MedusaCoreWindowController strayWindowForProfile:profile].coreWindow;
}

@end

@implementation MedusaCoreHost

+ (int)runWithArgc:(int)argc argv:(char **)argv delegate:(id<NSApplicationDelegate> (^)(void))makeDelegate {
  const char *dataDir = getenv("MEDUSA_DATA_DIR") ?: getenv("MEDUSA_DATA_DIR");
  gScratchDataDir = dataDir && *dataDir;
#if DEBUG
  if (!gScratchDataDir) {
    fprintf(stderr, "[medusacore] set MEDUSA_DATA_DIR to a scratch directory\n");
    return 1;
  }
#endif
  gMakeDelegate = [makeDelegate copy];
  NSString *scratch = gScratchDataDir ? @(dataDir) : nil;
  if (scratch && !scratch.absolutePath)
    scratch = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:scratch];
  gDataDirectory = scratch ? [scratch.stringByStandardizingPath stringByAppendingPathComponent:@"Chromium"] : InstalledDataDirectory();
  NSError *dirError;
  if (![NSFileManager.defaultManager createDirectoryAtPath:gDataDirectory withIntermediateDirectories:YES attributes:nil error:&dirError]) {
    fprintf(stderr, "[medusacore] can't use the data dir %s: %s\n", gDataDirectory.fileSystemRepresentation,
            dirError.localizedDescription.UTF8String ?: "");
    return 1;
  }
  medusacore_host::InstallTestCrashGuard(scratch && medusacore_host::Background() ? scratch.stringByStandardizingPath : nil);
  medusacore_host::InstallActivationGuardsEarly();
  medusacore_host::PrepareContentBlocker();
  Method finishLaunching = class_getInstanceMethod(NSApplication.class, @selector(finishLaunching));
  IMP appKitFinishLaunching = method_getImplementation(finishLaunching);
  method_setImplementation(finishLaunching, imp_implementationWithBlock(^(NSApplication *app) {
    if (!gAppDelegate && !app.delegate) {
      gBootstrap = [MedusaCoreBootstrapDelegate new];
      app.delegate = gBootstrap;
    }
    ((void (*)(id, SEL))appKitFinishLaunching)(app, @selector(finishLaunching));
  }));
  [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillFinishLaunchingNotification
                                                  object:nil
                                                   queue:nil
                                              usingBlock:^(NSNotification *) {
                                                gAppKitWillFinish = true;
                                              }];
  if (getenv("MEDUSA_TRACE_VISIBILITY")) {
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidChangeOcclusionStateNotification
                                                    object:nil
                                                     queue:nil
                                                usingBlock:^(NSNotification *note) {
                                                  NSWindow *w = note.object;
                                                  id chrome = [w respondsToSelector:NSSelectorFromString(@"isOccluded")]
                                                                  ? [w valueForKey:@"occluded"] : nil;
                                                  NSLog(@"[medusacore-vis] window %ld occlusion macOSVisible=%d chromeOccluded=%@ fromChecker=%d",
                                                        (long)w.windowNumber, (w.occlusionState & NSWindowOcclusionStateVisible) != 0,
                                                        chrome, note.userInfo.count > 0);
                                                }];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSNotificationName name in @[ NSWorkspaceScreensDidSleepNotification, NSWorkspaceScreensDidWakeNotification,
                                        NSWorkspaceSessionDidResignActiveNotification, NSWorkspaceSessionDidBecomeActiveNotification ])
      [workspace addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSLog(@"[medusacore-vis] workspace %@", note.name);
      }];
  }
  [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification
                                                  object:nil
                                                   queue:nil
                                              usingBlock:^(NSNotification *) {
                                                gAppKitDidFinish = true;
                                                NSAppleEventDescriptor *event = NSAppleEventManager.sharedAppleEventManager.currentAppleEvent;
                                                if (event.eventID == kAEOpenApplication &&
                                                    [event paramDescriptorForKeyword:keyAEPropData].enumCodeValue == keyAELaunchedAsLogInItem)
                                                  gLaunchedHidden = true;
                                                if (event && !(event.eventClass == kCoreEventClass && event.eventID == kAEOpenApplication))
                                                  gLaunchedForDocuments = true;
                                                if (gEarlyWindowPending) {
                                                  gEarlyWindowPending = false;
                                                  StartEarlyWindow();
                                                }
                                                if (!gPendingLaunchURLs.count) return;
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                  NSArray<NSURL *> *urls = gPendingLaunchURLs;
                                                  gPendingLaunchURLs = nil;
                                                  if (urls.count && [gAppDelegate respondsToSelector:@selector(application:openURLs:)])
                                                    [gAppDelegate application:NSApp openURLs:urls];
                                                });
                                              }];

  const char *tabFreezing = getenv("MEDUSA_TAB_FREEZING");
  const bool freezeLeastRecentTabs = !(tabFreezing && !strcmp(tabFreezing, "off"));
  std::vector<std::string> extra = {
      "--user-data-dir=" + std::string(gDataDirectory.UTF8String),
      "--enable-smooth-scrolling",
      "--disable-stack-profiler",
      "--disable-features=MacAppCodeSignClone,DevToolsAcceptDebuggingConnections",
      std::string("--enable-features=WebContentsDiscard,ImprovedStartupBestEffortDelay:StartupDelayStopOnLoadingTimedOut/true,"
                  "CPUMeasurementInFreezingPolicy:freezing_visible_protection_time/0s") +
          (freezeLeastRecentTabs ? ",InfiniteTabsFreezing" : ""),
      "--profile-directory=Default",
      "--js-flags=--no-memory-reducer",
  };
  const bool mockKeychain = gScratchDataDir || !IsTeamSigned();
  if (mockKeychain) extra.push_back("--use-mock-keychain");
  medusacore_host::PrepareStartup(gDataDirectory, extra);
  @autoreleasepool {
    [MedusaCoreEarlyWindow setDataDirectory:AppDataDirectory()];
    [MedusaCoreEarlyWindow prefetchForSession:SavedSession(AppDataDirectory()) ?: @{}];
  }
  const bool isBackground = (getenv("MEDUSA_BACKGROUND") != nullptr || getenv("MEDUSA_BACKGROUND") != nullptr);
  const bool allowOcclusion = (getenv("MEDUSA_ALLOW_OCCLUSION") != nullptr || getenv("MEDUSA_ALLOW_OCCLUSION") != nullptr);
  const bool allowAudio = (getenv("MEDUSA_ALLOW_AUDIO") != nullptr || getenv("MEDUSA_ALLOW_AUDIO") != nullptr);
  if (isBackground && !allowOcclusion) {
    extra.push_back("--disable-backgrounding-occluded-windows");
    if (Method occluded = class_getInstanceMethod(NSWindow.class, NSSelectorFromString(@"isOccluded")))
      method_setImplementation(occluded, imp_implementationWithBlock(^BOOL(id) { return NO; }));
  }
  if (isBackground && allowOcclusion) ReportLoweredWindowOcclusion();
  if (isBackground && !allowAudio) extra.push_back("--mute-audio");
  if (isBackground) extra.push_back("--use-fake-device-for-media-stream");
  if (isBackground) extra.push_back("--disable-modal-animations");
  auto autoAccepts = [isBackground](const char *sw) {
    return isBackground && (!strncmp(sw, "--use-fake-ui-for-media-stream", 30) ||
                            !strncmp(sw, "--auto-accept-camera-and-microphone-capture", 43));
  };
  if (const char *port = getenv("MEDUSA_REMOTE_DEBUGGING_PORT") ?: getenv("MEDUSA_REMOTE_DEBUGGING_PORT"); port && mockKeychain) {
    extra.push_back(std::string("--remote-debugging-port=") + port);
    extra.push_back("--remote-allow-origins=*");
  }
  if (const char *switches = getenv("MEDUSA_CHROMIUM_SWITCHES") ?: getenv("MEDUSA_CHROMIUM_SWITCHES"); switches && mockKeychain) {
    NSString *all = [@" " stringByAppendingString:@(switches)];
    for (NSString *item in [all componentsSeparatedByString:@" --"]) {
      NSString *sw = [item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      std::string full = std::string("--") + sw.UTF8String;
      if (sw.length && !autoAccepts(full.c_str())) extra.push_back(full);
    }
  }
  std::vector<const char *> args = {argc > 0 && argv[0] ? argv[0] : "Medusa"};
  for (const std::string &s : extra) args.push_back(s.c_str());
  for (int i = 1; mockKeychain && i < argc; i++) {
    const char *arg = argv[i];
    if (!arg) break;
    const bool cocoaDefault = arg[0] == '-' && arg[1] != '-' && isalpha((unsigned char)arg[1]) &&
                              strncmp(arg, "-psn_", 5) != 0 && i + 1 < argc;
    if (cocoaDefault) {
      i++;
      continue;
    }
    if (autoAccepts(arg)) continue;
    args.push_back(arg);
  }
  static MedusaCoreHostEngineDelegate *engineDelegate = [MedusaCoreHostEngineDelegate new];
  return [MedusaCoreEngine runWithArgc:(int)args.size() argv:args.data() delegate:engineDelegate];
}

+ (void (^)(NSString *, NSDictionary *))eventHandler {
  return gEventHandler;
}

+ (void)setEventHandler:(void (^)(NSString *, NSDictionary *))handler {
  gEventHandler = [handler copy];
}

+ (void (^)(NSString *, NSDictionary *))extensionsEventHandler {
  return gExtensionsEventHandler;
}

+ (void)setExtensionsEventHandler:(void (^)(NSString *, NSDictionary *))handler {
  gExtensionsEventHandler = [handler copy];
  if (handler)
    for (NSDictionary *prompt in gInstallPrompts.allValues) handler(@"installPrompt", prompt);
}

+ (void)resolveExtensionInstallPrompt:(NSString *)requestId accepted:(BOOL)accepted {
  [gInstallPrompts removeObjectForKey:requestId ?: @""];
  if ([MedusaCoreEngine respondsToSelector:@selector(resolveExtensionInstallPrompt:accepted:)])
    [MedusaCoreEngine resolveExtensionInstallPrompt:requestId accepted:accepted];
}

+ (void)beginTracing:(void (^)(BOOL))completion {
  if (![MedusaCoreEngine respondsToSelector:@selector(beginTracing:)]) return completion(NO);
  [MedusaCoreEngine beginTracing:completion];
}

+ (void)endTracing:(BOOL)keep completion:(void (^)(NSString *))completion {
  if (![MedusaCoreEngine respondsToSelector:@selector(endTracing:completion:)]) return completion(nil);
  [MedusaCoreEngine endTracing:keep completion:completion];
}

+ (BOOL)isTracing {
  return [MedusaCoreEngine respondsToSelector:@selector(isTracing)] && MedusaCoreEngine.isTracing;
}

+ (void)deleteProfileData:(NSString *)profile completion:(void (^)(NSArray<NSString *> *))completion {
  if (medusacore_host::IsIncognito(profile)) return completion(@[]);
  MedusaCoreEngine *engine = MedusaCoreEngine.sharedEngine;
  MedusaCoreProfile *p = medusacore_host::LoadedProfile(profile);
  if (!profile.length || ![engine respondsToSelector:@selector(deleteProfile:completion:)]) return completion(@[ @"data" ]);
  [DeletedProfiles() addObject:profile];
  void (^remove)(MedusaCoreProfile *) = ^(MedusaCoreProfile *loaded) {
    if (!loaded) {
      NSString *path = [gDataDirectory stringByAppendingPathComponent:[@"Profile " stringByAppendingString:profile]];
      [NSFileManager.defaultManager removeItemAtPath:path error:nil];
      return completion([NSFileManager.defaultManager fileExistsAtPath:path] ? @[ @"files" ] : @[]);
    }
    [engine deleteProfile:loaded completion:^(BOOL deleted) {
      if (deleted) [Profiles() removeObjectForKey:profile];
      else [DeletedProfiles() removeObject:profile];
      completion(deleted ? @[] : @[ @"data" ]);
    }];
  };
  if (!p && ProfileWaiters()[profile]) {
    DeletionsAfterLoad()[profile] = [remove copy];
    return;
  }
  remove(p);
}

+ (void)releaseProfile:(NSString *)profile {
  MedusaCoreEngine *engine = MedusaCoreEngine.sharedEngine;
  MedusaCoreProfile *p = medusacore_host::LoadedProfile(profile);
  if (medusacore_host::IsIncognito(profile)) {
    if (profile) [ReleasedPrivateNames() addObject:profile];
    [Profiles() removeObjectForKey:profile];
    NSArray *waiting = ProfileWaiters()[profile];
    [ProfileWaiters() removeObjectForKey:profile];
    for (void (^waiter)(MedusaCoreProfile *) in waiting) waiter(nil);
    medusacore_host::ForgetPrivateNavigationDownloads(profile);
    if ([Profiles().allValues containsObject:p]) return;
  }
  if (p && [engine respondsToSelector:@selector(releaseProfile:)]) [engine releaseProfile:p];
}

+ (BOOL)stopCapture:(int)browserId {
  MedusaCoreTab *tab = medusacore_host::TabWithBrowserId(browserId);
  return [tab respondsToSelector:@selector(stopCapture)] && [tab stopCapture];
}

+ (BOOL)showAutofillSuggestions:(int)browserId passwords:(BOOL)passwords {
  MedusaCoreTab *tab = medusacore_host::TabWithBrowserId(browserId);
  return [tab respondsToSelector:@selector(showAutofillSuggestions:)] && [tab showAutofillSuggestions:passwords];
}

+ (void (^)(NSString *, NSDictionary *))chromeUIHandler {
  return gChromeUIHandler;
}

+ (void)setChromeUIHandler:(void (^)(NSString *, NSDictionary *))handler {
  gChromeUIHandler = [handler copy];
}

+ (void)deviceChooser:(int)chooserId select:(int)index {
  if ([MedusaCoreEngine respondsToSelector:@selector(selectDevice:index:)]) [MedusaCoreEngine selectDevice:chooserId index:index];
}

+ (void)deviceChooser:(int)chooserId action:(NSString *)action {
  if ([action isEqualToString:@"cancel"] && [MedusaCoreEngine respondsToSelector:@selector(cancelDeviceChooser:)])
    [MedusaCoreEngine cancelDeviceChooser:chooserId];
  else if ([action isEqualToString:@"refresh"] && [MedusaCoreEngine respondsToSelector:@selector(refreshDeviceChooser:)])
    [MedusaCoreEngine refreshDeviceChooser:chooserId];
  else if ([action isEqualToString:@"settings"] && [MedusaCoreEngine respondsToSelector:@selector(openDeviceChooserSettings:)])
    [MedusaCoreEngine openDeviceChooserSettings:chooserId];
}

+ (NSArray<NSDictionary *> *)testExternalLaunches {
  return MedusaCoreEngine.testExternalLaunches ?: @[];
}

+ (BOOL)devReservedGlobalShortcut:(NSString *)shortcut {
  return [MedusaCoreEngine respondsToSelector:@selector(isReservedGlobalShortcut:)] && [MedusaCoreEngine isReservedGlobalShortcut:shortcut];
}

+ (BOOL)devShowBluetoothChooser:(int)browserId unauthorized:(BOOL)unauthorized {
  MedusaCoreTab *tab = medusacore_host::TabWithBrowserId(browserId);
  return [tab respondsToSelector:@selector(devShowBluetoothChooser:)] && [tab devShowBluetoothChooser:unauthorized];
}

+ (NSArray<NSDictionary *> *)testChooserEvents {
  return [MedusaCoreEngine respondsToSelector:@selector(testChooserEvents)] ? MedusaCoreEngine.testChooserEvents ?: @[] : @[];
}

+ (BOOL)shareTabInstead:(int)capturerBrowserId target:(int)targetBrowserId {
  MedusaCoreTab *capturer = medusacore_host::TabWithBrowserId(capturerBrowserId);
  MedusaCoreTab *tab = medusacore_host::TabWithBrowserId(targetBrowserId);
  return capturer && [tab respondsToSelector:@selector(shareThisTabInsteadFor:)] && [tab shareThisTabInsteadFor:capturer];
}

+ (BOOL)showCastDialog:(int)browserId {
  MedusaCoreTab *tab = medusacore_host::TabWithBrowserId(browserId);
  return [tab respondsToSelector:@selector(showCastDialog)] && [tab showCastDialog];
}

+ (void)castDialog:(int)dialogId start:(NSString *)sink mode:(int)mode {
  if ([MedusaCoreEngine respondsToSelector:@selector(startCasting:sink:mode:)]) [MedusaCoreEngine startCasting:dialogId sink:sink mode:mode];
}

+ (void)castDialog:(int)dialogId stop:(NSString *)route {
  if ([MedusaCoreEngine respondsToSelector:@selector(stopCasting:route:)]) [MedusaCoreEngine stopCasting:dialogId route:route];
}

+ (void)closeCastDialog:(int)dialogId {
  if ([MedusaCoreEngine respondsToSelector:@selector(closeCastDialog:)]) [MedusaCoreEngine closeCastDialog:dialogId];
}

+ (void)watchCastRoutes:(NSString *)profileName {
  medusacore_host::WithProfile(profileName, ^(MedusaCoreProfile *profile) {
    if ([profile respondsToSelector:@selector(watchCastRoutes)]) [profile watchCastRoutes];
  });
}

+ (void)terminateCastRoute:(NSString *)route {
  if ([MedusaCoreEngine respondsToSelector:@selector(terminateCastRoute:)]) [MedusaCoreEngine terminateCastRoute:route];
}

+ (void)resolveExternalApp:(NSString *)requestId open:(BOOL)open remember:(BOOL)remember {
  if ([MedusaCoreEngine respondsToSelector:@selector(resolveExternalApp:open:remember:)])
    [MedusaCoreEngine resolveExternalApp:requestId open:open remember:remember];
}

+ (NSDictionary *)actionStates:(int)browserId extensions:(NSArray<NSString *> *)ids {
  MedusaCoreTab *tab = medusacore_host::TabWithBrowserId(browserId);
  return [tab respondsToSelector:@selector(actionStatesForExtensions:)] ? [tab actionStatesForExtensions:ids] ?: @{} : @{};
}

+ (NSString *)sidePanelURL:(int)browserId extension:(NSString *)extensionId {
  MedusaCoreTab *tab = medusacore_host::TabWithBrowserId(browserId);
  return [tab respondsToSelector:@selector(sidePanelURLForExtension:)] ? [tab sidePanelURLForExtension:extensionId] : nil;
}

+ (void)resolvePermission:(NSString *)requestId result:(NSString *)result remember:(BOOL)remember {
  MedusaCoreEngine *engine = MedusaCoreEngine.sharedEngine;
  if ([engine respondsToSelector:@selector(resolvePermission:result:remember:)])
    [engine resolvePermission:requestId result:result remember:remember];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)displayMediaSources {
  NSMutableArray *sources = [NSMutableArray array];
  NSUInteger index = 0;
  for (NSScreen *screen in NSScreen.screens) {
    NSNumber *display = screen.deviceDescription[@"NSScreenNumber"];
    index++;
    [sources addObject:@{
      @"id" : [NSString stringWithFormat:@"screen:%u:0", display.unsignedIntValue],
      @"kind" : @"screen",
      @"name" : screen.localizedName ?: [NSString stringWithFormat:@"Screen %lu", (unsigned long)index],
      @"width" : @(screen.frame.size.width),
      @"height" : @(screen.frame.size.height),
    }];
  }
  NSArray *windows = CFBridgingRelease(
      CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
  const pid_t me = getpid();
  for (NSDictionary *w in windows) {
    if ([w[(id)kCGWindowLayer] intValue] != 0 || [w[(id)kCGWindowOwnerPID] intValue] == me) continue;
    NSDictionary *bounds = w[(id)kCGWindowBounds];
    const CGFloat width = [bounds[@"Width"] doubleValue], height = [bounds[@"Height"] doubleValue];
    if (width < 50 || height < 50) continue;
    NSString *app = w[(id)kCGWindowOwnerName] ?: @"";
    NSString *title = w[(id)kCGWindowName];
    [sources addObject:@{
      @"id" : [NSString stringWithFormat:@"window:%u:0", [w[(id)kCGWindowNumber] unsignedIntValue]],
      @"kind" : @"window",
      @"name" : title.length ? title : app,
      @"app" : app,
      @"pid" : w[(id)kCGWindowOwnerPID] ?: @0,
      @"width" : @(width),
      @"height" : @(height),
    }];
  }
  return sources;
}

+ (BOOL)isStarted {
  return gStarted;
}

+ (NSString *)dataDirectory {
  return gDataDirectory ?: @"";
}

+ (NSDictionary<NSString *, id> *)engineInfo {
  MedusaCoreEngine *engine = MedusaCoreEngine.sharedEngine;
  NSInteger chromeWindows = 0;
  for (MedusaCoreWindowController *c in MedusaCoreWindowController.all) chromeWindows += c.coreWindow ? 1 : 0;
  return @{
    @"pid" : @(NSProcessInfo.processInfo.processIdentifier),
    @"dataDirectory" : gDataDirectory ?: @"",
    @"engine" : @"medusacore",
    @"chromiumVersion" : engine.chromiumVersion ?: @"",
    @"liveBrowsers" : @0,
    @"popupWindows" : @(medusacore_host::PopupWindowCount()),
    @"chromeWindows" : @(chromeWindows),
    @"keepAlive" : engine.keepAliveState ?: @"",
    @"lastUsedProfile" : engine.defaultProfile.name ?: @"",
  };
}

+ (NSArray<NSDictionary<NSString *, id> *> *)chromeWindows {
  NSMutableArray *list = [NSMutableArray array];
  for (MedusaCoreWindowController *c in MedusaCoreWindowController.all) {
    NSWindow *w = c.coreWindow.window;
    if (!w) continue;
    MedusaCoreProfile *active = c.coreWindow.activeProfile;
    [list addObject:@{
      @"profile" : medusacore_host::ProfileName(active),
      @"window" : @(w.windowNumber),
      @"frame" : NSStringFromRect(w.frame),
      @"alpha" : @(w.alphaValue),
      @"key" : @(w.isKeyWindow),
      @"canBecomeKey" : @(w.canBecomeKeyWindow),
      @"visible" : @(w.isVisible),
      @"occlusionVisible" : @((w.occlusionState & NSWindowOcclusionStateVisible) != 0),
      @"chromeOccluded" : [w respondsToSelector:NSSelectorFromString(@"isOccluded")] ? [w valueForKey:@"occluded"] : NSNull.null,
      @"parentWindow" : @(w.parentWindow.windowNumber),
      @"chromeWindows" : @1,
      @"anchorBrowserId" : @0,
      @"anyTabBrowserId" : @0,
      @"ready" : @YES,
      @"active" : @(w.isMainWindow),
      @"pageInsets" : @[ @0, @0, @0, @0 ],
      @"hosting" : @(c.root != nil),
      @"group" : @"",
      @"hasRoot" : @(c.root != nil),
      @"translucent" : @(!w.opaque),
    }];
  }
  return list;
}

@end

namespace medusacore_host {

void ForgetDestroyedProfiles() {
  for (NSString *name in Profiles().allKeys)
    if (Profiles()[name].destroyed) [Profiles() removeObjectForKey:name];
}

NSArray<NSString *> *LoadedProfileNames() {
  ForgetDestroyedProfiles();
  return Profiles().allKeys;
}

NSArray<MedusaCoreProfile *> *LoadedProfiles() {
  ForgetDestroyedProfiles();
  NSMutableArray *profiles = [NSMutableArray array];
  for (MedusaCoreProfile *profile in Profiles().allValues)
    if (![profiles containsObject:profile]) [profiles addObject:profile];
  return profiles;
}

bool IsIncognito(NSString *name) {
  return [name hasPrefix:@"incognito"];
}

NSString *OriginalProfileName(NSString *name) {
  if (!IsIncognito(name)) return name ?: @"";
  NSRange at = [name rangeOfString:@"@"];
  return at.location == NSNotFound ? @"" : [name substringFromIndex:NSMaxRange(at)];
}

NSString *OriginalProfileNameOf(MedusaCoreProfile *profile) {
  if (!profile.offTheRecord) return ProfileName(profile);
  NSString *dir = profile.name;
  return [dir hasPrefix:@"Profile "] ? [dir substringFromIndex:8] : @"";
}

bool IsOffTheRecordOf(MedusaCoreProfile *profile, NSString *name) {
  return profile.offTheRecord && IsIncognito(name) &&
         [profile.name isEqualToString:DirectoryName(OriginalProfileName(name))];
}

bool IsDeletedProfile(NSString *name) {
  return [DeletedProfiles() containsObject:name ?: @""];
}

MedusaCoreProfile *LoadedProfile(NSString *name) {
  MedusaCoreProfile *profile = Profiles()[name ?: @""];
  if (!profile.destroyed) return profile;
  [Profiles() removeObjectForKey:name ?: @""];
  return nil;
}

namespace {

void WithPrivateProfile(NSString *name, void (^completion)(MedusaCoreProfile *)) {
  if ([ReleasedPrivateNames() containsObject:name]) return completion(nil);
  if (NSMutableArray *waiters = ProfileWaiters()[name]) return (void)[waiters addObject:completion];
  ProfileWaiters()[name] = [NSMutableArray arrayWithObject:completion];
  NSString *original = OriginalProfileName(name);
  WithProfile(original, ^(MedusaCoreProfile *base) {
    MedusaCoreEngine *engine = MedusaCoreEngine.sharedEngine;
    void (^answer)(MedusaCoreProfile *, NSString *) = ^(MedusaCoreProfile *otr, NSString *error) {
      NSArray *pending = ProfileWaiters()[name];
      [ProfileWaiters() removeObjectForKey:name];
      if (IsDeletedProfile(original)) {
        if (otr && ![Profiles().allValues containsObject:otr]) [engine releaseProfile:otr];
        if (pending) NSLog(@"[medusacore] no private profile for %@: its profile was deleted", name);
        for (void (^waiter)(MedusaCoreProfile *) in pending) waiter(nil);
        return;
      }
      if (!pending) {
        if (otr && ![Profiles().allValues containsObject:otr]) [engine releaseProfile:otr];
        return;
      }
      if (otr && !otr.destroyed) Profiles()[name] = otr;
      else NSLog(@"[medusacore] no private profile for %@: %@", name, error ?: @"it went");
      for (void (^waiter)(MedusaCoreProfile *) in pending) waiter(Profiles()[name]);
    };
    if (!base) return answer(nil, [NSString stringWithFormat:@"profile \"%@\" isn't loaded", original]);
    if (![engine respondsToSelector:@selector(offTheRecordProfileFor:completion:)]) return answer(nil, @"the engine is too old");
    [engine offTheRecordProfileFor:base completion:answer];
  });
}

}

void WithProfile(NSString *name, void (^completion)(MedusaCoreProfile *)) {
  name = name ?: @"";
  if ([DeletedProfiles() containsObject:name]) return completion(nil);
  if (MedusaCoreProfile *profile = LoadedProfile(name)) return completion(profile);
  MedusaCoreEngine *engine = MedusaCoreEngine.sharedEngine;
  if (!engine) return completion(nil);
  if (IsIncognito(name)) return WithPrivateProfile(name, [completion copy]);
  if (name.length == 0) {
    if (MedusaCoreProfile *personal = PersonalIfLoaded(engine)) {
      Profiles()[@""] = personal;
      return completion(personal);
    }
  }
  NSMutableArray *waiters = ProfileWaiters()[name];
  if (waiters) return (void)[waiters addObject:[completion copy]];
  ProfileWaiters()[name] = [NSMutableArray arrayWithObject:[completion copy]];
  [engine loadProfile:DirectoryName(name)
           completion:^(MedusaCoreProfile *loaded) {
             NSArray *pending = ProfileWaiters()[name];
             [ProfileWaiters() removeObjectForKey:name];
             if (void (^deletion)(MedusaCoreProfile *) = DeletionsAfterLoad()[name]) {
               [DeletionsAfterLoad() removeObjectForKey:name];
               deletion(loaded);
             }
             MedusaCoreProfile *profile = [DeletedProfiles() containsObject:name] ? nil : loaded;
             if (profile) Profiles()[name] = profile;
             if (profile) medusacore_host::LoadContentBlocker(name);
             if (profile) [MedusaCoreServices watchDownloads:name];
             for (void (^waiter)(MedusaCoreProfile *) in pending) waiter(profile);
           }];
}

MedusaCoreProfile *PersonalIfLoaded(MedusaCoreEngine *engine) {
  MedusaCoreProfile *profile = engine.defaultProfile;
  return [profile.name isEqualToString:@"Default"] ? profile : nil;
}

NSString *ProfileName(MedusaCoreProfile *profile) {
  if (!profile) return @"";
  for (NSString *name in Profiles())
    if (Profiles()[name] == profile) return name;
  NSString *dir = profile.name;
  if ([dir hasPrefix:@"Profile "]) return [dir substringFromIndex:8];
  return @"";
}

NSString *AppDisposition(NSString *chrome) {
  static NSDictionary *map = @{
    @"foreground_tab" : @"foreground",
    @"background_tab" : @"background",
    @"popup" : @"popup",
    @"window" : @"window",
    @"off_the_record" : @"incognito",
    @"current_tab" : @"current",
    @"split_view" : @"split",
    @"singleton_tab" : @"foreground",
  };
  return map[chrome] ?: @"foreground";
}

}

#import "MedusaCoreEarlyWindow.h"

#import "ACChromeWindow.h"
#import "MedusaCoreEngineBridge.h"
#import "MedusaCoreInternal.h"
#import "MedusaCoreWebView.h"
#import "MedusaCoreWebViewInternal.h"

#import <ImageIO/ImageIO.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cmath>
#include <mach/mach.h>
#include <os/lock.h>

@interface ACEarlyShown : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *appWindow;
@property(nonatomic, copy) NSString *profile;
@property(nonatomic, strong) NSView *cover;
@property(nonatomic, strong) NSView *picture;
@property(nonatomic, strong) NSView *backdrop;
@property(nonatomic, strong) MedusaCoreTab *tab;
@property(nonatomic, copy) NSString *key;
@property(nonatomic) NSRect pageRect;
@property(nonatomic) BOOL claimed;
@property(nonatomic) BOOL expired;
@property(nonatomic) BOOL shielded;
@property(nonatomic, strong) id inputBlock;
@property(nonatomic, strong) id contentObserver;
@property(nonatomic, strong) id closeObserver;
@end

@implementation ACEarlyShown
@end

@interface ACEarlyVeil : NSObject
@property(nonatomic, strong) NSView *view;
@property(nonatomic, strong) id inputBlock;
@property(nonatomic) BOOL restoreFocus;
@property(nonatomic, copy) NSString *lastShown;
@property(nonatomic) CFTimeInterval changedAt;
@end

@implementation ACEarlyVeil
@end

namespace {

constexpr int kLayoutVersion = 2;
constexpr double kRecordDelay = 1.0;
constexpr double kUnclaimedSeconds = 15;
constexpr double kClaimedSeconds = 5;
constexpr double kUntakenAfterContentSeconds = 2;
constexpr double kPictureAfterContentSeconds = 0.5;
constexpr CGFloat kMinPage = 100;
constexpr double kTrimAfterHandoffSeconds = 2;
constexpr double kWatchAfterAdoptionSeconds = 10;
constexpr double kVeilFailSafeSeconds = 2;

NSString *gLayoutPath;
NSString *gDirectory;
BOOL gRecordQueued;
NSData *gScheduled;
NSMutableDictionary<NSString *, NSDictionary *> *gLayouts;
os_unfair_lock gPrefetchLock = OS_UNFAIR_LOCK_INIT;
CGImageRef gPrefetched;
BOOL gPrefetchDiscarded;
NSString *gPrefetchedWindow;
dispatch_group_t gPrefetch;
BOOL gPictureCurrent;
NSString *gLaunchURL;

NSMapTable<MedusaCoreTab *, ACEarlyVeil *> *Veils() {
  static NSMapTable *veils = [NSMapTable weakToStrongObjectsMapTable];
  return veils;
}

NSHashTable<MedusaCoreTab *> *Watched() {
  static NSHashTable *watched = [NSHashTable weakObjectsHashTable];
  return watched;
}

NSMutableSet<NSString *> *Dismissed() {
  static NSMutableSet *dismissed = [NSMutableSet set];
  return dismissed;
}

dispatch_queue_t Writer() {
  static dispatch_queue_t queue = dispatch_queue_create("medusa.early-window.writer", DISPATCH_QUEUE_SERIAL);
  return queue;
}

NSMutableArray<ACEarlyShown *> *Shown() {
  static NSMutableArray *shown = [NSMutableArray array];
  return shown;
}

ACEarlyShown *ShownForWindow(NSWindow *window) {
  if (!window) return nil;
  for (ACEarlyShown *s in Shown())
    if (s.window == window) return s;
  return nil;
}

bool SwitchedOffByEnvironment() {
  const char *env = getenv("MEDUSA_EARLY_WINDOW");
  if (env && (!strcmp(env, "off") || !strcmp(env, "0") || !strcmp(env, "false"))) return true;
  const char *switches = getenv("MEDUSA_SWITCHES");
  if (!switches) return false;
  for (NSString *part in [@(switches) componentsSeparatedByString:@","]) {
    NSArray<NSString *> *pair = [part componentsSeparatedByString:@"="];
    if (pair.count != 2) continue;
    NSString *name = [pair[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *value = [pair[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([name isEqualToString:@"earlyWindow"] && [@[ @"off", @"0", @"false" ] containsObject:value]) return true;
  }
  return false;
}

NSDictionary *SessionAt(NSString *directory) {
  NSData *data = directory ? [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"session.json"]] : nil;
  NSDictionary *session = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  return [session isKindOfClass:NSDictionary.class] ? session : nil;
}

NSString *StateOf(NSDictionary *session, NSString *windowId) {
  NSDictionary *settings = [session[@"settings"] isKindOfClass:NSDictionary.class] ? session[@"settings"] : @{};
  NSDictionary *window = nil;
  for (NSDictionary *w in [session[@"windows"] isKindOfClass:NSArray.class] ? session[@"windows"] : @[])
    if ([w isKindOfClass:NSDictionary.class] && [w[@"id"] isEqual:windowId]) window = w;
  if (!window) return nil;
  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  for (NSString *key in @[ @"tabLayout", @"addressBar", @"sidebarWidth", @"bookmarksBar", @"appearance", @"hideToolbarWhileScrolling", @"showFullUrl" ])
    if (settings[key]) state[[@"s." stringByAppendingString:key]] = settings[key];
  for (NSString *key in @[ @"sidebarOpen", @"tabLayout", @"profileId", @"incognito" ])
    if (window[key]) state[[@"w." stringByAppendingString:key]] = window[key];
  NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingSortedKeys error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

NSString *ContentOf(NSDictionary *session, NSString *windowId) {
  NSDictionary *window = nil;
  for (NSDictionary *w in [session[@"windows"] isKindOfClass:NSArray.class] ? session[@"windows"] : @[])
    if ([w isKindOfClass:NSDictionary.class] && [w[@"id"] isEqual:windowId]) window = w;
  if (!window) return nil;
  NSMutableDictionary *tabs = [NSMutableDictionary dictionary];
  for (NSDictionary *t in [session[@"tabs"] isKindOfClass:NSArray.class] ? session[@"tabs"] : @[])
    if ([t isKindOfClass:NSDictionary.class] && [t[@"windowId"] isEqual:windowId] && [t[@"id"] isKindOfClass:NSString.class])
      tabs[t[@"id"]] = @[ t[@"title"] ?: NSNull.null, t[@"customTitle"] ?: NSNull.null, t[@"url"] ?: NSNull.null, t[@"favicon"] ?: NSNull.null,
                          t[@"customIcon"] ?: NSNull.null, t[@"pinned"] ?: NSNull.null, t[@"muted"] ?: NSNull.null ];
  NSMutableArray *groups = [NSMutableArray array];
  for (NSDictionary *g in [session[@"groups"] isKindOfClass:NSArray.class] ? session[@"groups"] : @[])
    if ([g isKindOfClass:NSDictionary.class] && [g[@"windowId"] isEqual:windowId]) [groups addObject:g];
  NSDictionary *content = @{
    @"window" : window,
    @"tabs" : tabs,
    @"groups" : groups,
    @"profiles" : session[@"profiles"] ?: NSNull.null,
    @"settings" : session[@"settings"] ?: NSNull.null,
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:content options:NSJSONWritingSortedKeys error:nil];
  if (!data) return nil;
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString string];
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
  return hex;
}

NSArray<NSNumber *> *Insets(NSRect rect, NSView *host) {
  const NSRect bounds = host.bounds;
  const CGFloat top = host.isFlipped ? NSMinY(rect) : NSMaxY(bounds) - NSMaxY(rect);
  const CGFloat bottom = host.isFlipped ? NSMaxY(bounds) - NSMaxY(rect) : NSMinY(rect);
  return @[ @(round(NSMinX(rect) * 2) / 2), @(round(top * 2) / 2), @(round((NSMaxX(bounds) - NSMaxX(rect)) * 2) / 2), @(round(bottom * 2) / 2) ];
}

bool ReadInsets(id value, CGFloat out[4]) {
  if (![value isKindOfClass:NSArray.class] || [value count] != 4) return false;
  for (int i = 0; i < 4; i++) {
    id n = value[i];
    if (![n isKindOfClass:NSNumber.class] || !std::isfinite([n doubleValue]) || [n doubleValue] < 0) return false;
    out[i] = [n doubleValue];
  }
  return true;
}

bool Fits(const CGFloat insets[4], NSView *host) {
  return NSWidth(host.bounds) - insets[0] - insets[2] >= kMinPage && NSHeight(host.bounds) - insets[1] - insets[3] >= kMinPage;
}

NSRect RectFromInsets(const CGFloat insets[4], NSView *host) {
  const NSRect bounds = host.bounds;
  const CGFloat width = NSWidth(bounds) - insets[0] - insets[2], height = NSHeight(bounds) - insets[1] - insets[3];
  const CGFloat y = host.isFlipped ? insets[1] : insets[3];
  return NSMakeRect(insets[0], y, MAX(0, width), MAX(0, height));
}

NSString *PictureName(NSString *windowId) {
  NSMutableString *safe = [NSMutableString string];
  for (NSUInteger i = 0; i < windowId.length && i < 80; i++) {
    const unichar c = [windowId characterAtIndex:i];
    [safe appendString:(isalnum(c) || c == '-' || c == '_') ? [NSString stringWithCharacters:&c length:1] : @"_"];
  }
  return [NSString stringWithFormat:@"launch-picture-%@.png", safe];
}

NSData *EncodePNG(CGImageRef image) {
  NSMutableData *png = [NSMutableData data];
  CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, (__bridge CFStringRef)UTTypePNG.identifier, 1, nullptr);
  if (!dest) return nil;
  CGImageDestinationAddImage(dest, image, nullptr);
  const bool ok = CGImageDestinationFinalize(dest);
  CFRelease(dest);
  return ok ? png : nil;
}

NSString *PicturePath(NSString *windowId) {
  return [gDirectory stringByAppendingPathComponent:PictureName(windowId)];
}

NSView *DrawnContent(NSView *root) {
  NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:root];
  for (NSUInteger i = 0; i < pending.count && i < 64; i++) {
    NSView *view = pending[i];
    if (![NSStringFromClass(view.class) hasPrefix:@"RCT"]) {
      [pending addObjectsFromArray:view.subviews];
      continue;
    }
    for (NSView *child in view.subviews)
      if (child.layer && NSEqualRects([child convertRect:child.bounds toView:root], root.bounds)) return child;
    return root;
  }
  return root;
}

BOOL CapturePicture(MedusaCoreWindowController *controller, NSString *windowId, NSDictionary *layout) {
  NSWindow *window = controller.coreWindow.window;
  NSView *root = controller.root;
  CALayer *layer = root.layer;
  NSArray<NSNumber *> *page = layout[@"page"];
  if (!gLayoutPath || !layer || !window.visible || window.miniaturized || ![page isKindOfClass:NSArray.class] || page.count != 4) return NO;
  const NSSize size = root.bounds.size;
  const CGFloat scale = window.backingScaleFactor ?: 2;
  const size_t w = (size_t)ceil(size.width * scale), h = (size_t)ceil(size.height * scale);
  if (w < 64 || h < 64) return NO;
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(nullptr, w, h, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(space);
  if (!context) return NO;
  CGContextSaveGState(context);
  CGContextScaleCTM(context, scale, scale);
  NSView *source = DrawnContent(root);
  CALayer *drawnLayer = source.layer ?: layer;
  if (source.isFlipped || drawnLayer.geometryFlipped) {
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
  }
  NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:source];
  NSMutableArray<CALayer *> *backdrops = [NSMutableArray array];
  NSMutableArray<CALayer *> *fills = [NSMutableArray array];
  NSMutableArray *fillColors = [NSMutableArray array];
  const NSRect whole = root.bounds;
  for (NSUInteger i = 0; i < pending.count && i < 4000; i++) {
    NSView *view = pending[i];
    if ([NSStringFromClass(view.class) hasSuffix:@"WindowBackdropView"] || [view isKindOfClass:NSVisualEffectView.class]) {
      if (view.layer && !view.layer.hidden) [backdrops addObject:view.layer];
      continue;
    }
    if (NSEqualSizes([view convertRect:view.bounds toView:root].size, whole.size)) {
      if (view.layer.backgroundColor) {
        [fills addObject:view.layer];
        [fillColors addObject:(__bridge id)view.layer.backgroundColor];
      }
    }
    [pending addObjectsFromArray:view.subviews];
  }
  NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:drawnLayer];
  NSMutableArray<CALayer *> *effected = [NSMutableArray array];
  NSMutableArray<NSArray *> *effects = [NSMutableArray array];
  for (NSUInteger i = 0; i < layers.count && i < 20000; i++) {
    CALayer *each = layers[i];
    if ([backdrops containsObject:each]) continue;
    if (each.mask || each.filters.count || each.compositingFilter || each.backgroundFilters.count) {
      [effected addObject:each];
      [effects addObject:@[ each.mask ?: NSNull.null, each.filters ?: @[], each.compositingFilter ?: NSNull.null, each.backgroundFilters ?: @[] ]];
    }
    if (each.sublayers) [layers addObjectsFromArray:each.sublayers];
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (CALayer *backdrop in backdrops) backdrop.hidden = YES;
  for (CALayer *fill in fills) fill.backgroundColor = nil;
  for (CALayer *each in effected) {
    each.mask = nil;
    each.filters = nil;
    each.compositingFilter = nil;
    each.backgroundFilters = nil;
  }
  [drawnLayer renderInContext:context];
  for (NSUInteger i = 0; i < effected.count; i++) {
    NSArray *saved = effects[i];
    effected[i].mask = saved[0] == NSNull.null ? nil : saved[0];
    effected[i].filters = [saved[1] count] ? saved[1] : nil;
    effected[i].compositingFilter = saved[2] == NSNull.null ? nil : saved[2];
    effected[i].backgroundFilters = [saved[3] count] ? saved[3] : nil;
  }
  for (CALayer *backdrop in backdrops) backdrop.hidden = NO;
  for (NSUInteger i = 0; i < fills.count; i++) fills[i].backgroundColor = (__bridge CGColorRef)fillColors[i];
  [CATransaction commit];
  CGContextRestoreGState(context);
  const CGRect hole = CGRectMake(page[0].doubleValue * scale, page[3].doubleValue * scale,
                                 w - (page[0].doubleValue + page[2].doubleValue) * scale, h - (page[1].doubleValue + page[3].doubleValue) * scale);
  if (hole.size.width > 0 && hole.size.height > 0) CGContextClearRect(context, hole);
  CGImageRef image = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  if (!image) return NO;
  NSString *path = PicturePath(windowId);
  __block BOOL written = NO;
  dispatch_sync(Writer(), ^{
    NSData *png = EncodePNG(image);
    written = png && [png writeToFile:path atomically:YES];
    CGImageRelease(image);
  });
  return written;
}

void DropPictureFile(NSString *windowId) {
  NSString *path = PicturePath(windowId);
  dispatch_async(Writer(), ^{ [NSFileManager.defaultManager removeItemAtPath:path error:nil]; });
}

NSDictionary *WindowLayout(MedusaCoreWindowController *controller, NSDictionary *session) {
  NSWindow *window = controller.coreWindow.window;
  NSView *host = controller.coreWindow.hostView;
  if (!window.visible || !host || !controller.root || (window.styleMask & NSWindowStyleMaskFullScreen)) return nil;
  if ([window.identifier isEqualToString:@"medusa.window.small"] || ShownForWindow(window)) return nil;
  NSString *state = StateOf(session, controller.appWindowId);
  if (!state) return nil;
  NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:controller.root];
  NSMutableArray<MedusaCoreWebView *> *shown = [NSMutableArray array];
  for (NSUInteger i = 0; i < pending.count && i < 4000; i++) {
    NSView *view = pending[i];
    if ([view isKindOfClass:MedusaCoreWebView.class]) {
      MedusaCoreWebView *web = (MedusaCoreWebView *)view;
      if (web.visible && web.browserId && !web.hiddenOrHasHiddenAncestor && web.alphaValue > 0) [shown addObject:web];
      continue;
    }
    [pending addObjectsFromArray:view.subviews];
  }
  if (shown.count != 1) return nil;
  MedusaCoreWebView *web = shown[0];
  if (NSWidth(web.bounds) < kMinPage || NSHeight(web.bounds) < kMinPage) return nil;
  NSView *clip = nil;
  for (NSView *v = web; v && v != host; v = v.superview)
    if (v.layer.masksToBounds && v.layer.cornerRadius > 0) {
      clip = v;
      break;
    }
  NSView *card = clip ?: web;
  NSMutableDictionary *layout = [@{
    @"page" : Insets([web convertRect:web.bounds toView:host], host),
    @"card" : Insets([card convertRect:card.bounds toView:host], host),
    @"radius" : @(clip ? clip.layer.cornerRadius : 0),
    @"curve" : clip.layer.cornerCurve ?: kCACornerCurveCircular,
    @"size" : @[ @(NSWidth(window.frame)), @(NSHeight(window.frame)) ],
    @"state" : state,
    @"content" : ContentOf(session, controller.appWindowId) ?: @"",
  } mutableCopy];
  if (web.transferKey.length) layout[@"tab"] = web.transferKey;
  if (NSValue *lights = ACTrafficLightsCenter(window)) layout[@"lights"] = @[ @(lights.pointValue.x), @(lights.pointValue.y) ];
  if (window.appearance.name) layout[@"appearance"] = window.appearance.name;
  if (NSColor *color = [web.pageBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace])
    layout[@"pageColor"] = @[ @(color.redComponent), @(color.greenComponent), @(color.blueComponent), @(color.alphaComponent) ];
  return layout;
}

void LoadLayouts() {
  if (gLayouts || !gLayoutPath) return;
  gLayouts = [NSMutableDictionary dictionary];
  NSData *data = [NSData dataWithContentsOfFile:gLayoutPath];
  NSDictionary *file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![file isKindOfClass:NSDictionary.class] || ![file[@"version"] isEqual:@(kLayoutVersion)]) return;
  if ([file[@"windows"] isKindOfClass:NSDictionary.class])
    for (NSString *key in file[@"windows"])
      if ([key isKindOfClass:NSString.class] && [file[@"windows"][key] isKindOfClass:NSDictionary.class]) gLayouts[key] = file[@"windows"][key];
  gScheduled = data;
}

void Write(NSData *data) {
  if (!data || [data isEqual:gScheduled]) return;
  gScheduled = data;
  NSString *path = gLayoutPath;
  dispatch_async(Writer(), ^{
    if ([data writeToFile:path atomically:YES]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (gScheduled == data) gScheduled = nil;
    });
  });
}

void RecordLayouts(NSDictionary *session, BOOL wait);
NSString *ActiveTabOf(NSDictionary *session, NSString *windowId);

void Record(BOOL wait) {
  gRecordQueued = NO;
  if (!gDirectory.length) return;
  NSDictionary *session = SessionAt(gDirectory);
  if ([session[@"settings"] isKindOfClass:NSDictionary.class] && [session[@"settings"][@"restoreSession"] isEqual:@NO])
    [MedusaCoreEarlyWindow forgetPictures];
  else if (gLayoutPath && session)
    RecordLayouts(session, wait);
  if (wait) dispatch_sync(Writer(), ^{});
}

NSString *ActiveTabOf(NSDictionary *session, NSString *windowId) {
  for (NSDictionary *w in [session[@"windows"] isKindOfClass:NSArray.class] ? session[@"windows"] : @[]) {
    if (![w isKindOfClass:NSDictionary.class] || ![w[@"id"] isEqual:windowId]) continue;
    NSDictionary *active = [w[@"activeTabIds"] isKindOfClass:NSDictionary.class] ? w[@"activeTabIds"] : nil;
    id tab = [w[@"profileId"] isKindOfClass:NSString.class] ? active[w[@"profileId"]] : nil;
    return [tab isKindOfClass:NSString.class] ? tab : nil;
  }
  return nil;
}

void RecordLayouts(NSDictionary *session, BOOL wait) {
  LoadLayouts();
  NSMutableSet *saved = [NSMutableSet set];
  for (NSDictionary *w in [session[@"windows"] isKindOfClass:NSArray.class] ? session[@"windows"] : @[])
    if ([w isKindOfClass:NSDictionary.class] && [w[@"id"] isKindOfClass:NSString.class]) [saved addObject:w[@"id"]];
  NSMutableSet *live = [NSMutableSet set];
  for (MedusaCoreWindowController *controller in MedusaCoreWindowController.all) {
    NSString *windowId = controller.appWindowId;
    if (!windowId.length || controller.stray || controller.standalone) continue;
    [live addObject:windowId];
    NSMutableDictionary *layout = [WindowLayout(controller, session) mutableCopy];
    if (!layout) continue;
    if (wait) {
      NSString *active = ActiveTabOf(session, windowId);
      if (active && [layout[@"tab"] isEqual:active] && CapturePicture(controller, windowId, layout)) layout[@"pictureContent"] = layout[@"content"];
      else DropPictureFile(windowId);
    } else if ([gLayouts[windowId][@"pictureContent"] isKindOfClass:NSString.class]) {
      layout[@"pictureContent"] = gLayouts[windowId][@"pictureContent"];
    }
    gLayouts[windowId] = layout;
  }
  for (NSString *key in gLayouts.allKeys)
    if (![saved containsObject:key] && ![live containsObject:key]) {
      [gLayouts removeObjectForKey:key];
      DropPictureFile(key);
    }
  while (gLayouts.count > 16) {
    NSString *drop = nil;
    for (NSString *key in gLayouts)
      if (![live containsObject:key]) drop = key;
    if (!drop) break;
    [gLayouts removeObjectForKey:drop];
    DropPictureFile(drop);
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version" : @(kLayoutVersion), @"windows" : gLayouts}
                                                 options:NSJSONWritingSortedKeys
                                                   error:nil];
  Write(data);
}

NSString *OriginOfURL(NSString *url) {
  if ([url.lowercaseString hasPrefix:@"view-source:"]) url = [url substringFromIndex:12];
  const NSRange separator = [url rangeOfString:@"://"];
  if (separator.location == NSNotFound || separator.location == 0) return nil;
  NSString *scheme = [url substringToIndex:separator.location].lowercaseString;
  NSString *rest = [url substringFromIndex:NSMaxRange(separator)];
  const NSRange end = [rest rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]];
  NSString *authority = end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
  const NSRange user = [authority rangeOfString:@"@" options:NSBackwardsSearch];
  if (user.location != NSNotFound) authority = [authority substringFromIndex:NSMaxRange(user)];
  return [NSString stringWithFormat:@"%@://%@", scheme, authority.lowercaseString];
}

id TabCall(MedusaCoreTab *tab, NSString *name, BOOL *answered) {
  const SEL selector = NSSelectorFromString(name);
  *answered = [tab respondsToSelector:selector];
  return *answered ? ((id (*)(id, SEL))objc_msgSend)(tab, selector) : nil;
}

NSString *LiveOrigin(MedusaCoreTab *tab) {
  BOOL answered = NO;
  NSString *committed = TabCall(tab, @"committedOrigin", &answered);
  if (answered && committed) return committed.length ? committed : nil;
  return OriginOfURL(tab.url);
}

BOOL Untitled(NSString *url) {
  return !url.length || [url isEqualToString:@"about:blank"];
}

BOOL ShownMatches(NSString *shownURL, MedusaCoreTab *tab) {
  NSString *shown = OriginOfURL(shownURL);
  if (shown) {
    NSString *live = LiveOrigin(tab);
    return live && [shown isEqualToString:live];
  }
  NSString *url = tab.url;
  return Untitled(shownURL) ? Untitled(url) : [shownURL isEqualToString:url];
}

bool PageVeilOff() {
  static const bool off = [@(getenv("MEDUSA_PAGE_VEIL") ?: "") isEqualToString:@"off"];
  return off;
}

BOOL ShowsLaunchOrigin(MedusaCoreTab *tab, NSString *launchURL) {
  NSString *launch = OriginOfURL(launchURL);
  if (!launch) return NO;
  BOOL engineKnows = NO;
  NSString *committed = TabCall(tab, @"committedOrigin", &engineKnows);
  if (committed && ![committed isEqualToString:launch]) return NO;
  NSString *url = tab.url;
  if (!url.length) return YES;
  if ([url isEqualToString:@"about:blank"]) return engineKnows;
  NSString *live = OriginOfURL(url);
  if (![live isEqualToString:launch]) return NO;
  if (![live hasPrefix:@"https:"] || ![tab respondsToSelector:@selector(securityInfo)]) return YES;
  return ![tab.securityInfo[@"level"] isEqual:@"certificateError"];
}

BOOL ReleaseFocusFrom(NSView *page) {
  NSWindow *window = page.window;
  NSResponder *focused = window.firstResponder;
  if (!page || ![focused isKindOfClass:NSView.class] || ![(NSView *)focused isDescendantOf:page]) return NO;
  [window makeFirstResponder:nil];
  return YES;
}

void PlaceVeil(MedusaCoreTab *tab, ACEarlyVeil *veil) {
  NSView *page = tab.view, *host = page.superview;
  if (!host || host == veil.view.superview) return;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (!veil.view) {
    veil.view = [[NSView alloc] initWithFrame:host.bounds];
    veil.view.wantsLayer = YES;
    veil.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  NSColor *fill = [host isKindOfClass:MedusaCoreWebView.class] ? ((MedusaCoreWebView *)host).pageBackgroundColor : nil;
  veil.view.layer.backgroundColor = (fill ?: NSColor.windowBackgroundColor).CGColor;
  veil.view.frame = host.bounds;
  [host addSubview:veil.view positioned:NSWindowAbove relativeTo:page];
  [CATransaction commit];
  if (ReleaseFocusFrom(page)) veil.restoreFocus = YES;
}

void Unveil(MedusaCoreTab *tab) {
  ACEarlyVeil *veil = [Veils() objectForKey:tab];
  if (!veil) return;
  [Veils() removeObjectForKey:tab];
  NSView *host = veil.view.superview;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [veil.view removeFromSuperview];
  [CATransaction commit];
  if (!veil.restoreFocus || tab.closed || tab.view.superview != host || ![host isKindOfClass:MedusaCoreWebView.class]) return;
  MedusaCoreWebView *web = (MedusaCoreWebView *)host;
  NSWindow *window = web.window;
  NSResponder *focused = window.firstResponder;
  if (web.visible && !web.isHiddenOrHasHiddenAncestor && (!focused || focused == window)) [tab focus];
}

void Reconcile(MedusaCoreTab *tab) {
  NSView *host = tab.view.superview;
  if ([host isKindOfClass:MedusaCoreWebView.class]) [MedusaCoreEarlyWindow page:tab shownURL:((MedusaCoreWebView *)host).shownURL];
}

void WatchVeil(MedusaCoreTab *tab, ACEarlyVeil *veil, double after) {
  __weak MedusaCoreTab *weakTab = tab;
  __weak ACEarlyVeil *weakVeil = veil;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    MedusaCoreTab *page = weakTab;
    ACEarlyVeil *still = weakVeil;
    if (!page || !still || [Veils() objectForKey:page] != still) return;
    const double left = still.changedAt + kVeilFailSafeSeconds - CACurrentMediaTime();
    if (left > 0.05) return WatchVeil(page, still, left);
    BOOL answered = NO;
    NSLog(@"[medusacore] page veil lifted after %.1f s without a match: shown %@, committed %@, visible %@", kVeilFailSafeSeconds,
          still.lastShown ?: @"(none)", TabCall(page, @"committedOrigin", &answered) ?: @"(none)", page.url ?: @"(none)");
    Unveil(page);
  });
}

void CarryShield(MedusaCoreTab *tab, id inputBlock) {
  if (!tab || tab.closed) return;
  ACEarlyVeil *veil = [Veils() objectForKey:tab];
  if (!veil) {
    veil = [ACEarlyVeil new];
    veil.changedAt = CACurrentMediaTime();
    [Veils() setObject:veil forKey:tab];
    WatchVeil(tab, veil, kVeilFailSafeSeconds);
  }
  if (!veil.inputBlock) {
    BOOL answered = NO;
    veil.inputBlock = inputBlock ?: TabCall(tab, @"suppressInput", &answered);
  }
  PlaceVeil(tab, veil);
  Reconcile(tab);
}

void DropCover(ACEarlyShown *s) {
  if (s.contentObserver) [NSNotificationCenter.defaultCenter removeObserver:s.contentObserver];
  s.contentObserver = nil;
  MedusaCoreTab *tab = s.tab;
  NSView *cover = s.cover;
  id inputBlock = s.inputBlock;
  s.tab = nil;
  s.cover = nil;
  s.inputBlock = nil;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (tab && tab.view.superview == cover) [tab.view removeFromSuperview];
  [cover removeFromSuperview];
  [CATransaction commit];
  if (s.shielded) CarryShield(tab, inputBlock);
  else if (tab && !tab.closed && [tab.view.superview isKindOfClass:MedusaCoreWebView.class]) {
    [Watched() addObject:tab];
    __weak MedusaCoreTab *watched = tab;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWatchAfterAdoptionSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (MedusaCoreTab *still = watched) [Watched() removeObject:still];
    });
    [MedusaCoreEarlyWindow page:tab shownURL:((MedusaCoreWebView *)tab.view.superview).shownURL];
  }
}

bool EnvOff(const char *name) {
  const char *value = getenv(name);
  return value && (!strcmp(value, "off") || !strcmp(value, "0") || !strcmp(value, "false"));
}

void TrimAfterHandoff() {
  static bool trimmed;
  if (trimmed || EnvOff("MEDUSA_MEMORY_TRIM") || EnvOff("MEDUSA_MEMORY_TRIM_ENGINE")) return;
  trimmed = true;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTrimAfterHandoffSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [MedusaCoreEngineBridge call:@"ac_memory_trim" profile:@"" args:nil completion:^(NSString *) {}];
  });
}

void RemovePicture(NSView *picture) {
  picture.layer.contents = nil;
  [picture removeFromSuperview];
}

void DropPictures(ACEarlyShown *s) {
  RemovePicture(s.picture);
  [s.backdrop removeFromSuperview];
  s.picture = nil;
  s.backdrop = nil;
}

void Forget(ACEarlyShown *s) {
  DropCover(s);
  if (s.closeObserver) [NSNotificationCenter.defaultCenter removeObserver:s.closeObserver];
  s.closeObserver = nil;
  NSView *picture = s.picture, *backdrop = s.backdrop;
  s.picture = nil;
  s.backdrop = nil;
  if (picture || backdrop)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPictureAfterContentSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      RemovePicture(picture);
      [backdrop removeFromSuperview];
    });
  [Shown() removeObject:s];
  if (!Shown().count) TrimAfterHandoff();
}

void Abandon(ACEarlyShown *s) {
  NSWindow *window = s.window;
  const BOOL unclaimed = !s.claimed;
  DropPictures(s);
  Forget(s);
  if (!unclaimed || !window) return;
  [window orderOut:nil];
  [ACChromeWindowHost closeWindow:window];
}

NSView *Cover(NSView *host, NSDictionary *layout, NSRect *pageRect) {
  CGFloat page[4], card[4];
  if (!ReadInsets(layout[@"page"], page) || !ReadInsets(layout[@"card"], card) || !Fits(page, host) || !Fits(card, host)) return nil;
  NSView *cover = [[NSView alloc] initWithFrame:RectFromInsets(card, host)];
  cover.wantsLayer = YES;
  cover.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  const double radius = [layout[@"radius"] isKindOfClass:NSNumber.class] ? [layout[@"radius"] doubleValue] : 0;
  if (radius > 0 && std::isfinite(radius)) {
    cover.layer.cornerRadius = MIN(radius, 64);
    if ([layout[@"curve"] isKindOfClass:NSString.class]) cover.layer.cornerCurve = layout[@"curve"];
    cover.layer.masksToBounds = YES;
  }
  [host addSubview:cover];
  *pageRect = [cover convertRect:RectFromInsets(page, host) fromView:host];
  NSArray *color = layout[@"pageColor"];
  if ([color isKindOfClass:NSArray.class] && color.count == 4) {
    CALayer *fill = [CALayer layer];
    fill.frame = *pageRect;
    fill.backgroundColor = [NSColor colorWithSRGBRed:[color[0] doubleValue] green:[color[1] doubleValue] blue:[color[2] doubleValue] alpha:[color[3] doubleValue]].CGColor;
    [cover.layer addSublayer:fill];
  }
  return cover;
}

void Shield(ACEarlyShown *s) {
  s.shielded = YES;
  BOOL answered = NO;
  s.inputBlock = TabCall(s.tab, @"suppressInput", &answered);
  ReleaseFocusFrom(s.tab.view);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  s.cover.hidden = YES;
  [CATransaction commit];
}

void ApplyLights(NSWindow *window, NSDictionary *layout) {
  NSArray *lights = layout[@"lights"];
  if ([lights isKindOfClass:NSArray.class] && lights.count == 2 && [lights[0] isKindOfClass:NSNumber.class] && [lights[1] isKindOfClass:NSNumber.class])
    [ACChromeWindowHost setTrafficLightsCenter:[NSValue valueWithPoint:NSMakePoint([lights[0] doubleValue], [lights[1] doubleValue])] inWindow:window];
}

void FreePages(void *, const void *data, size_t size) {
  vm_deallocate(mach_task_self(), (vm_address_t)data, size);
}

CGImageRef DecodeOutsideHeap(CGImageRef encoded) {
  const size_t w = CGImageGetWidth(encoded), h = CGImageGetHeight(encoded), stride = w * 4;
  if (!w || !h || w > 16384 || h > 16384) return nullptr;
  const size_t size = round_page(stride * h);
  vm_address_t pages = 0;
  if (vm_allocate(mach_task_self(), &pages, size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) return nullptr;
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  const CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
  CGContextRef context = CGBitmapContextCreate((void *)pages, w, h, 8, stride, space, info);
  if (!context) {
    CGColorSpaceRelease(space);
    vm_deallocate(mach_task_self(), pages, size);
    return nullptr;
  }
  CGContextDrawImage(context, CGRectMake(0, 0, w, h), encoded);
  CGContextRelease(context);
  CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, (const void *)pages, size, FreePages);
  if (!provider) {
    CGColorSpaceRelease(space);
    vm_deallocate(mach_task_self(), pages, size);
    return nullptr;
  }
  CGImageRef image = CGImageCreate(w, h, 8, 32, stride, space, info, provider, nullptr, false, kCGRenderingIntentDefault);
  CGDataProviderRelease(provider);
  CGColorSpaceRelease(space);
  return image;
}

CGImageRef TakePrefetched(NSString *windowId) {
  CGImageRef picture = nullptr;
  if (gPrefetch && [gPrefetchedWindow isEqualToString:windowId] &&
      dispatch_group_wait(gPrefetch, dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC)) == 0) {
    os_unfair_lock_lock(&gPrefetchLock);
    picture = gPrefetched;
    gPrefetched = nullptr;
    os_unfair_lock_unlock(&gPrefetchLock);
  }
  [MedusaCoreEarlyWindow discardPrefetch];
  return picture;
}

}

@implementation MedusaCoreEarlyWindow

+ (void)setDataDirectory:(NSString *)directory {
  gDirectory = [directory copy];
  gLayoutPath = directory.length && !SwitchedOffByEnvironment() ? [directory stringByAppendingPathComponent:@"launch-layout.json"] : nil;
}

+ (BOOL)switchedOff {
  return SwitchedOffByEnvironment();
}

+ (void)noteLayoutChangeIn:(NSWindow *)window {
  if (!gLayoutPath || gRecordQueued || !window) return;
  MedusaCoreWindowController *controller = [MedusaCoreWindowController forNSWindow:window];
  if (!controller.appWindowId.length || controller.stray || controller.standalone) return;
  gRecordQueued = YES;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRecordDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Record(NO); });
}

+ (void)recordNow {
  Record(YES);
}

+ (void)prefetchForSession:(NSDictionary *)session {
  NSString *focused = [session[@"focusedWindowId"] isKindOfClass:NSString.class] ? session[@"focusedWindowId"] : nil;
  if (!focused.length || !gLayoutPath || gPrefetch) return;
  gPrefetch = dispatch_group_create();
  gPrefetchedWindow = [focused copy];
  NSString *path = PicturePath(focused);
  dispatch_group_async(gPrefetch, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], nullptr);
    if (!source) return;
    CGImageRef encoded = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    if (!encoded) return;
    CGImageRef decoded = DecodeOutsideHeap(encoded);
    CGImageRelease(encoded);
    os_unfair_lock_lock(&gPrefetchLock);
    const BOOL keep = !gPrefetchDiscarded;
    if (keep) gPrefetched = decoded;
    os_unfair_lock_unlock(&gPrefetchLock);
    if (!keep) CGImageRelease(decoded);
  });
}

+ (void)discardPrefetch {
  os_unfair_lock_lock(&gPrefetchLock);
  gPrefetchDiscarded = YES;
  CGImageRef image = gPrefetched;
  gPrefetched = nullptr;
  os_unfair_lock_unlock(&gPrefetchLock);
  CGImageRelease(image);
}

+ (BOOL)canShowWindow:(NSString *)windowId session:(NSDictionary *)session {
  if (!gLayoutPath || !windowId.length || Shown().count) return NO;
  LoadLayouts();
  NSDictionary *layout = gLayouts[windowId];
  NSString *state = StateOf(session, windowId);
  if (![layout isKindOfClass:NSDictionary.class] || !state || ![layout[@"state"] isEqual:state]) return NO;
  NSString *content = ContentOf(session, windowId);
  gPictureCurrent = content.length && [layout[@"pictureContent"] isEqual:content];
  NSDictionary *hint = [session[@"launchTab"] isKindOfClass:NSDictionary.class] ? session[@"launchTab"] : nil;
  gLaunchURL = [hint[@"url"] isKindOfClass:NSString.class] ? [hint[@"url"] copy] : nil;
  return YES;
}

+ (void)forgetPicturesNow {
  [self forgetPictures];
  dispatch_sync(Writer(), ^{});
}

+ (BOOL)holdsPage:(MedusaCoreTab *)tab {
  if (!tab) return NO;
  for (ACEarlyShown *s in Shown())
    if (s.tab == tab && !s.claimed && tab.view.superview == s.cover) return YES;
  return NO;
}

+ (void)forgetPictures {
  NSString *directory = gDirectory;
  if (!directory.length) return;
  gLayouts = [NSMutableDictionary dictionary];
  gScheduled = nil;
  [self discardPrefetch];
  dispatch_async(Writer(), ^{
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in [fm contentsOfDirectoryAtPath:directory error:nil])
      if (([name hasPrefix:@"launch-picture-"] && [name hasSuffix:@".png"]) || [name isEqualToString:@"launch-layout.json"])
        [fm removeItemAtPath:[directory stringByAppendingPathComponent:name] error:nil];
  });
}

+ (BOOL)showWindow:(NSString *)windowId
             frame:(NSArray<NSNumber *> *)frame
               key:(NSString *)key
           profile:(NSString *)profile
          backdrop:(NSDictionary *)backdrop {
  CGImageRef picture = TakePrefetched(windowId);
  BOOL shown = [self showWindow:windowId frame:frame key:key profile:profile backdrop:backdrop picture:picture];
  if (picture) CGImageRelease(picture);
  return shown;
}

+ (BOOL)showWindow:(NSString *)windowId
             frame:(NSArray<NSNumber *> *)frame
               key:(NSString *)key
           profile:(NSString *)profile
          backdrop:(NSDictionary *)backdrop
           picture:(CGImageRef)picture {
  if (!gLayoutPath || !windowId.length || !key.length || frame.count != 4 || Shown().count) return NO;
  Class backdropClass = NSClassFromString(@"MedusaEarlyBackdrop");
  const SEL make = NSSelectorFromString(@"make:");
  if (![backdropClass respondsToSelector:make]) return NO;
  NSDictionary *layout = gLayouts[windowId];
  if (![layout isKindOfClass:NSDictionary.class]) return NO;
  for (int i = 0; i < 4; i++)
    if (![frame[i] isKindOfClass:NSNumber.class] || !std::isfinite(frame[i].doubleValue)) return NO;
  const NSRect rect = NSMakeRect(frame[0].doubleValue, frame[1].doubleValue, frame[2].doubleValue, frame[3].doubleValue);
  if (NSWidth(rect) < 300 || NSHeight(rect) < 200) return NO;
  NSWindow *window = [ACChromeWindowHost makeWindowForProfile:profile ?: @""];
  MedusaCoreWindowController *controller = [MedusaCoreWindowController forNSWindow:window];
  NSView *host = controller.coreWindow.hostView;
  if (!window || !host) {
    if (window) [ACChromeWindowHost closeWindow:window];
    return NO;
  }
  controller.appWindowId = windowId;
  [window setFrame:rect display:NO];
  if (NSScreen *screen = window.screen ?: NSScreen.mainScreen) [window setFrame:[window constrainFrameRect:window.frame toScreen:screen] display:NO];
  if ([layout[@"appearance"] isKindOfClass:NSString.class]) window.appearance = [NSAppearance appearanceNamed:layout[@"appearance"]];
  [host layoutSubtreeIfNeeded];
  NSView *backdropView = ((NSView * (*)(id, SEL, NSDictionary *)) objc_msgSend)(backdropClass, make, backdrop);
  NSRect pageRect = NSZeroRect;
  NSView *cover = backdropView ? Cover(host, layout, &pageRect) : nil;
  if (!cover) {
    [ACChromeWindowHost closeWindow:window];
    return NO;
  }
  backdropView.frame = host.bounds;
  backdropView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [host addSubview:backdropView positioned:NSWindowBelow relativeTo:cover];
  ApplyLights(window, layout);
  ACEarlyShown *s = [ACEarlyShown new];
  s.window = window;
  s.appWindow = windowId;
  s.profile = profile ?: @"";
  s.cover = cover;
  s.key = key;
  s.pageRect = pageRect;
  s.backdrop = backdropView;
  NSArray *size = layout[@"size"];
  const BOOL sameSize = [size isKindOfClass:NSArray.class] && size.count == 2 && fabs([size[0] doubleValue] - NSWidth(window.frame)) < 0.5 &&
                        fabs([size[1] doubleValue] - NSHeight(window.frame)) < 0.5;
  if (picture && sameSize && gPictureCurrent) {
    NSView *view = [[NSView alloc] initWithFrame:host.bounds];
    view.wantsLayer = YES;
    view.layer.contents = (__bridge id)picture;
    view.layer.contentsGravity = kCAGravityResize;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [host addSubview:view positioned:NSWindowBelow relativeTo:cover];
    s.picture = view;
  }
  [Shown() addObject:s];
  __weak ACEarlyShown *weakShown = s;
  s.closeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
                                                                     object:window
                                                                      queue:nil
                                                                 usingBlock:^(NSNotification *) {
                                                                   ACEarlyShown *closing = weakShown;
                                                                   if (!closing) return;
                                                                   if (!closing.claimed) {
                                                                     [Dismissed() addObject:closing.appWindow];
                                                                     MedusaCoreTab *page = closing.tab;
                                                                     if (page && page == MedusaCoreWebView.launchTab)
                                                                       [MedusaCoreWebView claimLaunchTab:@"" url:@"" profile:@""];
                                                                     else if (page)
                                                                       [MedusaCoreWebView releaseTransfer:closing.key];
                                                                   }
                                                                   DropPictures(closing);
                                                                   Forget(closing);
                                                                 }];
  [window makeKeyAndOrderFront:nil];
  [window displayIfNeeded];
  [CATransaction flush];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kUnclaimedSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    ACEarlyShown *still = weakShown;
    if (!still || still.claimed || ![Shown() containsObject:still]) return;
    if (still.tab) still.expired = YES;
    else Abandon(still);
  });
  return YES;
}

+ (void)attachPage:(MedusaCoreTab *)tab key:(NSString *)key {
  if (!tab || tab.closed || !key.length) return;
  for (ACEarlyShown *s in Shown()) {
    if (!s.cover || s.tab || ![s.key isEqualToString:key]) continue;
    NSView *page = tab.view;
    if (!page) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [page removeFromSuperview];
    page.frame = s.pageRect;
    [s.cover addSubview:page];
    [CATransaction commit];
    s.tab = tab;
    if (!ShowsLaunchOrigin(tab, gLaunchURL)) Shield(s);
    return;
  }
}

+ (NSWindow *)claimForAppWindow:(NSString *)windowId profile:(NSString *)profile {
  if (!windowId.length) return nil;
  for (ACEarlyShown *s in [Shown() copy]) {
    if (s.claimed || ![s.appWindow isEqualToString:windowId]) continue;
    NSWindow *window = s.window;
    if (!window || ![MedusaCoreWindowController forNSWindow:window]) {
      Abandon(s);
      return nil;
    }
    s.claimed = YES;
    window.appearance = nil;
    if (![s.profile isEqualToString:profile ?: @""] || !s.cover) {
      DropPictures(s);
      Forget(s);
      return window;
    }
    __weak ACEarlyShown *weakShown = s;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kClaimedSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      ACEarlyShown *late = weakShown;
      if (late && [Shown() containsObject:late]) Forget(late);
    });
    return window;
  }
  return nil;
}

+ (BOOL)takeDismissed:(NSString *)windowId {
  if (!windowId.length || ![Dismissed() containsObject:windowId]) return NO;
  [Dismissed() removeObject:windowId];
  return YES;
}

+ (NSView *)coverInWindow:(NSWindow *)window {
  return ShownForWindow(window).cover;
}

+ (void)rootEmbedded:(NSView *)root inWindow:(NSWindow *)window {
  ACEarlyShown *s = ShownForWindow(window);
  if (!root || !s) return;
  if (s.contentObserver) [NSNotificationCenter.defaultCenter removeObserver:s.contentObserver];
  __weak ACEarlyShown *weakShown = s;
  s.contentObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:@"RCTContentDidAppearNotification"
                  object:root
                   queue:nil
              usingBlock:^(NSNotification *) {
                ACEarlyShown *shown = weakShown;
                if (!shown) return;
                [NSNotificationCenter.defaultCenter removeObserver:shown.contentObserver];
                shown.contentObserver = nil;
                if (!shown.tab) DropCover(shown);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPictureAfterContentSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                  ACEarlyShown *drawn = weakShown;
                  RemovePicture(drawn.picture);
                  [drawn.backdrop removeFromSuperview];
                  drawn.picture = nil;
                  drawn.backdrop = nil;
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kUntakenAfterContentSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                  ACEarlyShown *later = weakShown;
                  if (later && [Shown() containsObject:later]) Forget(later);
                });
              }];
}

+ (void)pageMoved:(MedusaCoreTab *)tab {
  if (!tab) return;
  if (ACEarlyVeil *veil = [Veils() objectForKey:tab]) {
    PlaceVeil(tab, veil);
    Reconcile(tab);
  }
  for (ACEarlyShown *s in [Shown() copy]) {
    if (s.tab != tab || tab.view.superview == s.cover) continue;
    if (s.claimed) Forget(s);
    else if (s.expired) Abandon(s);
    else DropCover(s);
  }
}

+ (BOOL)veils:(MedusaCoreTab *)tab {
  return tab && [Veils() objectForKey:tab] != nil;
}

+ (void)requestFocus:(MedusaCoreTab *)tab {
  if (tab) [Veils() objectForKey:tab].restoreFocus = YES;
}

+ (void)page:(MedusaCoreTab *)tab shownURL:(NSString *)url {
  if (!tab) return;
  ACEarlyVeil *veil = [Veils() objectForKey:tab];
  if (veil && ![veil.lastShown ?: @"" isEqualToString:url ?: @""]) {
    veil.lastShown = url;
    veil.changedAt = CACurrentMediaTime();
  }
  const BOOL veiled = veil != nil;
  if (!veiled && ![Watched() containsObject:tab]) return;
  if (tab.closed) {
    [Watched() removeObject:tab];
    return Unveil(tab);
  }
  const BOOL matches = ShownMatches(url, tab);
  if (veiled) {
    if (matches) Unveil(tab);
    return;
  }
  if (!url.length) return;
  if (!matches) {
    [Watched() removeObject:tab];
    return CarryShield(tab, nil);
  }
  if (!tab.loading) [Watched() removeObject:tab];
}

+ (void)pageCommitted:(MedusaCoreTab *)tab shownURL:(NSString *)url {
  if (!tab || !url.length || PageVeilOff() || [Veils() objectForKey:tab] || ShownMatches(url, tab)) return;
  CarryShield(tab, nil);
}

+ (void)pageNavigated:(MedusaCoreTab *)tab launchURL:(NSString *)launchURL {
  if (!tab) return;
  for (ACEarlyShown *s in Shown())
    if (s.tab == tab && !s.shielded && tab.view.superview == s.cover && !ShowsLaunchOrigin(tab, launchURL)) Shield(s);
}

+ (void)dropPage:(MedusaCoreTab *)tab {
  if (!tab) return;
  [Watched() removeObject:tab];
  Unveil(tab);
  for (ACEarlyShown *s in [Shown() copy])
    if (s.tab == tab) {
      if (s.claimed) Forget(s);
      else if (s.expired) Abandon(s);
      else DropCover(s);
    }
}

@end

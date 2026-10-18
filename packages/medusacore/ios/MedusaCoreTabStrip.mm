#import "MedusaCoreTabStrip.h"

#import "MedusaCoreInternal.h"
#import "MedusaCoreWebView.h"
#import "MedusaCoreEngineBridge.h"
#import "MedusaCoreServices.h"

namespace {

void (^gHandler)(NSDictionary *);
int64_t gRev = 0;

NSMapTable<MedusaCoreWindowController *, NSMutableDictionary<NSNumber *, NSString *> *> *KnownStrips() {
  static NSMapTable *known = [NSMapTable weakToStrongObjectsMapTable];
  return known;
}

void Remember(MedusaCoreWindowController *controller, int strip, NSString *profile) {
  if (strip < 0) return;
  NSMutableDictionary *strips = [KnownStrips() objectForKey:controller];
  if (!strips) {
    strips = [NSMutableDictionary dictionary];
    [KnownStrips() setObject:strips forKey:controller];
  }
  strips[@(strip)] = profile;
}
NSNumber *gCommand;
__weak MedusaCoreWindowController *gCommandWindow;
__weak MedusaCoreProfile *gCommandProfile;

NSMutableDictionary<NSNumber *, NSDictionary *> *Sent() {
  static NSMutableDictionary *sent = [NSMutableDictionary dictionary];
  return sent;
}

void Send(NSDictionary *tx) {
  for (NSDictionary *strip in tx[@"strips"]) {
    if ([strip[@"closed"] boolValue]) [Sent() removeObjectForKey:strip[@"strip"]];
    else Sent()[strip[@"strip"]] = strip;
  }
  gHandler(tx);
}

NSMutableDictionary<NSNumber *, NSDictionary *> *Groups() {
  static NSMutableDictionary *groups = [NSMutableDictionary dictionary];
  return groups;
}

bool ReportsGroups() {
  static bool reports = [MedusaCoreEngineBridge exports:@"ac_tabs_watch"];
  return reports;
}

NSMapTable<MedusaCoreTab *, NSNumber *> *Pinned() {
  static NSMapTable *pinned = [NSMapTable weakToStrongObjectsMapTable];
  return pinned;
}

NSMapTable<MedusaCoreProfile *, MedusaCoreTab *> *ActiveTabs(MedusaCoreWindowController *controller) {
  static NSMapTable *byWindow = [NSMapTable weakToStrongObjectsMapTable];
  NSMapTable *active = [byWindow objectForKey:controller];
  if (!active) {
    active = [NSMapTable weakToWeakObjectsMapTable];
    [byWindow setObject:active forKey:controller];
  }
  return active;
}

NSString *AppWindowOf(MedusaCoreWindowController *controller) {
  NSMutableArray<NSView *> *views = [NSMutableArray array];
  if (controller.root) [views addObject:controller.root];
  for (NSUInteger i = 0; i < views.count && i < 16; i++) {
    NSView *view = views[i];
    if ([view respondsToSelector:NSSelectorFromString(@"appProperties")]) {
      id properties = [view valueForKey:@"appProperties"];
      id windowId = [properties isKindOfClass:NSDictionary.class] ? properties[@"windowId"] : nil;
      if ([windowId isKindOfClass:NSString.class]) return windowId;
    }
    [views addObjectsFromArray:view.subviews];
  }
  return nil;
}

NSDictionary *Strip(MedusaCoreWindowController *controller, MedusaCoreProfile *profile) {
  MedusaCoreWindow *window = controller.coreWindow;
  NSMutableArray *tabs = [NSMutableArray array];
  NSArray<MedusaCoreTab *> *live = [window tabsForProfile:profile];
  MedusaCoreTab *active = [ActiveTabs(controller) objectForKey:profile];
  for (NSUInteger i = 0; i < live.count; i++) {
    MedusaCoreTab *tab = live[i];
    NSString *key = [MedusaCoreTabs viewForTab:tab].transferKey;
    [tabs addObject:@{
      @"key" : key.length ? key : NSNull.null,
      @"browser" : @(medusacore_host::BrowserId(tab)),
      @"index" : @(i),
      @"active" : @(tab == active || (!active && i == 0)),
      @"pinned" : @([[Pinned() objectForKey:tab] boolValue]),
    }];
    if (ReportsGroups()) {
      NSMutableDictionary *last = [tabs.lastObject mutableCopy];
      id group = Groups()[@([window chromeWindowIdForProfile:profile])][@"tabs"][@(tab.tabId)];
      last[@"group"] = group ?: NSNull.null;
      tabs[tabs.count - 1] = last;
    }
  }
  const int strip = [window chromeWindowIdForProfile:profile];
  NSString *name = medusacore_host::ProfileName(profile);
  Remember(controller, strip, name);
  NSMutableDictionary *state = [@{
    @"strip" : @(strip),
    @"window" : @(window.window.windowNumber),
    @"profile" : name,
    @"tabs" : tabs,
  } mutableCopy];
  if (ReportsGroups()) {
    state[@"groups"] = Groups()[@(strip)][@"groups"] ?: @[];
    if ([Groups()[@(strip)][@"activePickedOnClose"] boolValue]) state[@"activePickedOnClose"] = @YES;
  }
  if (NSString *appWindow = AppWindowOf(controller)) state[@"appWindow"] = appWindow;
  return state;
}

NSArray<MedusaCoreProfile *> *ProfilesWithTabs(MedusaCoreWindowController *controller) {
  NSMutableArray *profiles = [NSMutableArray array];
  for (MedusaCoreProfile *profile in medusacore_host::LoadedProfiles())
    if ([controller.coreWindow chromeWindowIdForProfile:profile] >= 0) [profiles addObject:profile];
  return profiles;
}

}

@implementation MedusaCoreTabStrip

+ (void)setHandler:(void (^)(NSDictionary<NSString *, id> *))handler {
  gHandler = [handler copy];
  static bool watching = false;
  if (watching || !ReportsGroups()) return;
  watching = true;
  [MedusaCoreEngineBridge observe:@"tabs.strip"
                      handler:^(NSDictionary *strip) {
                        NSNumber *window = [strip[@"window"] isKindOfClass:NSNumber.class] ? strip[@"window"] : nil;
                        if (!window) return;
                        if ([strip[@"closed"] boolValue]) return (void)[Groups() removeObjectForKey:window];
                        NSMutableDictionary *byTab = [NSMutableDictionary dictionary];
                        for (NSDictionary *tab in strip[@"tabs"])
                          if ([tab isKindOfClass:NSDictionary.class] && tab[@"tab"]) byTab[tab[@"tab"]] = tab[@"group"] ?: NSNull.null;
                        NSDictionary *before = Groups()[window];
                        NSDictionary *now = @{
                          @"groups" : strip[@"groups"] ?: @[],
                          @"tabs" : byTab,
                          @"activePickedOnClose" : @([strip[@"activePickedOnClose"] boolValue]),
                        };
                        Groups()[window] = now;
                        if ([before isEqualToDictionary:now] || gCommand) return;
                        for (MedusaCoreWindowController *c in MedusaCoreWindowController.all)
                          for (MedusaCoreProfile *p in medusacore_host::LoadedProfiles())
                            if ([c.coreWindow chromeWindowIdForProfile:p] == window.intValue)
                              [MedusaCoreTabStrip changedInWindow:c profile:p cause:c.hostChanges > 0 ? @(-1) : NSNull.null];
                      }];
  [MedusaCoreServices call:@"ac_tabs_watch" profile:@"" args:nil completion:^(NSDictionary *) {}];
}

+ (void)changedInWindow:(MedusaCoreWindowController *)controller profile:(MedusaCoreProfile *)profile {
  [self changedInWindow:controller profile:profile cause:nil];
}

+ (void)changedInWindow:(MedusaCoreWindowController *)controller profile:(MedusaCoreProfile *)profile cause:(id)cause {
  if (!gHandler || !controller || !profile || controller.standalone) return;
  if (gCommand && controller == gCommandWindow && profile == gCommandProfile) return;
  cause = cause ?: (gCommand ?: (controller.hostChanges > 0 ? @(-1) : NSNull.null));
  NSDictionary *strip = Strip(controller, profile);
  if ((cause == NSNull.null || [cause isEqual:@(-1)]) && [Sent()[strip[@"strip"]] isEqualToDictionary:strip]) return;
  Send(@{@"rev" : @(++gRev), @"cmd" : cause, @"strips" : @[ strip ]});
}

+ (void)windowClosed:(MedusaCoreWindowController *)controller {
  NSDictionary<NSNumber *, NSString *> *strips = [KnownStrips() objectForKey:controller];
  [KnownStrips() removeObjectForKey:controller];
  if (!gHandler || !strips.count) return;
  NSMutableArray *closed = [NSMutableArray array];
  const NSInteger window = controller.coreWindow.window.windowNumber;
  for (NSNumber *strip in strips)
    [closed addObject:@{@"strip" : strip, @"window" : @(window), @"profile" : strips[strip], @"tabs" : @[], @"closed" : @YES}];
  Send(@{@"rev" : @(++gRev), @"cmd" : NSNull.null, @"strips" : closed});
}

+ (void)activated:(MedusaCoreTab *)tab inWindow:(MedusaCoreWindowController *)controller {
  MedusaCoreProfile *profile = tab.profile;
  if (profile) [ActiveTabs(controller) setObject:tab forKey:profile];
}

+ (MedusaCoreTab *)activeTabInWindow:(MedusaCoreWindowController *)controller profile:(MedusaCoreProfile *)profile {
  return profile ? [ActiveTabs(controller) objectForKey:profile] : nil;
}

+ (void)removed:(MedusaCoreTab *)tab fromWindow:(MedusaCoreWindowController *)controller {
  MedusaCoreProfile *profile = tab.profile;
  if (profile && [ActiveTabs(controller) objectForKey:profile] == tab) [ActiveTabs(controller) removeObjectForKey:profile];
}

+ (void)setPinned:(BOOL)pinned tab:(MedusaCoreTab *)tab {
  [Pinned() setObject:@(pinned) forKey:tab];
}

+ (NSDictionary<NSString *, id> *)allStrips {
  NSMutableArray *strips = [NSMutableArray array];
  for (MedusaCoreWindowController *controller in MedusaCoreWindowController.all)
    if (!controller.standalone)
      for (MedusaCoreProfile *profile in ProfilesWithTabs(controller)) [strips addObject:Strip(controller, profile)];
  for (NSDictionary *strip in strips) Sent()[strip[@"strip"]] = strip;
  return @{@"rev" : @(gRev), @"cmd" : NSNull.null, @"strips" : strips};
}

+ (void)command:(NSInteger)commandId command:(NSDictionary<NSString *, id> *)command {
  NSString *op = command[@"op"];
  const int stripId = [command[@"strip"] intValue];
  MedusaCoreWindowController *found = nil;
  MedusaCoreProfile *profile = nil;
  for (MedusaCoreWindowController *controller in MedusaCoreWindowController.all)
    for (MedusaCoreProfile *p in ProfilesWithTabs(controller))
      if ([controller.coreWindow chromeWindowIdForProfile:p] == stripId) found = controller, profile = p;
  NSMutableDictionary<NSString *, MedusaCoreTab *> *byKey = [NSMutableDictionary dictionary];
  for (MedusaCoreTab *tab in found ? [found.coreWindow tabsForProfile:profile] : @[]) {
    NSString *key = [MedusaCoreTabs viewForTab:tab].transferKey;
    if (key.length) byKey[key] = tab;
  }
  BOOL rejected = !found;
  gCommand = @(commandId);
  gCommandWindow = found;
  gCommandProfile = profile;
  if (found && [op isEqualToString:@"activate"]) {
    MedusaCoreTab *tab = byKey[command[@"key"]];
    if (tab) {
      [found.coreWindow activateTab:tab];
    } else {
      rejected = YES;
    }
  } else if (found && [op isEqualToString:@"arrange"]) {
    NSArray<NSString *> *keys = [command[@"keys"] isKindOfClass:NSArray.class] ? command[@"keys"] : @[];
    const NSInteger pinned = [command[@"pinned"] integerValue];
    int index = 0;
    rejected = keys.count > 0;
    for (NSString *key in keys)
      if (byKey[key]) rejected = NO;
    for (NSUInteger i = 0; i < keys.count; i++) {
      MedusaCoreTab *tab = byKey[keys[i]];
      if (!tab) continue;
      [self setPinned:(NSInteger)i < pinned tab:tab];
      if ([found.coreWindow respondsToSelector:@selector(placeTab:index:pinned:)])
        [found.coreWindow placeTab:tab index:index pinned:(NSInteger)i < pinned];
      index++;
    }
  }
  if (found && [op isEqualToString:@"group"]) {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *key in [command[@"keys"] isKindOfClass:NSArray.class] ? command[@"keys"] : @[])
      if (MedusaCoreTab *tab = byKey[key]) [ids addObject:@(tab.tabId)];
    if (!ids.count) rejected = YES;
    else {
      NSMutableDictionary *args = [@{@"window" : @(stripId), @"tabs" : ids} mutableCopy];
      id group = command[@"group"];
      args[@"group"] = [group isKindOfClass:NSString.class] ? group : @"";
      for (NSString *key in @[ @"title", @"color" ])
        if ([command[key] isKindOfClass:NSString.class]) args[key] = command[key];
      if ([command[@"collapsed"] isKindOfClass:NSNumber.class]) args[@"collapsed"] = command[@"collapsed"];
      gCommand = nil;
      MedusaCoreWindowController *controller = found;
      MedusaCoreProfile *p = profile;
      [MedusaCoreServices call:@"ac_tabs_group" profile:medusacore_host::ProfileName(profile) args:args completion:^(NSDictionary *result) {
        NSMutableDictionary *tx = [@{@"rev" : @(++gRev), @"cmd" : @(commandId), @"strips" : @[ Strip(controller, p) ]} mutableCopy];
        if (result[@"error"]) tx[@"rejected"] = @YES;
        if (gHandler) Send(tx);
      }];
      return;
    }
  }
  gCommand = nil;
  NSMutableDictionary *tx = [@{@"rev" : @(++gRev), @"cmd" : @(commandId), @"strips" : found ? @[ Strip(found, profile) ] : @[]} mutableCopy];
  if (rejected) tx[@"rejected"] = @YES;
  if (gHandler) Send(tx);
}

@end

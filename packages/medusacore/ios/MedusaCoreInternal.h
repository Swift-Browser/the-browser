#import <AppKit/AppKit.h>

#import "MedusaCore.h"
#import "MedusaCoreHost.h"
#import "MedusaCoreTabStrip.h"

@class MedusaCoreWebView;

NS_ASSUME_NONNULL_BEGIN

namespace medusacore_host {

MedusaCoreProfile *_Nullable LoadedProfile(NSString *name);
bool IsDeletedProfile(NSString *name);
void WithProfile(NSString *name, void (^completion)(MedusaCoreProfile *_Nullable profile));
NSString *ProfileName(MedusaCoreProfile *_Nullable profile);
MedusaCoreProfile *_Nullable PersonalIfLoaded(MedusaCoreEngine *engine);
bool IsIncognito(NSString *name);
NSString *OriginalProfileName(NSString *_Nullable name);
NSString *OriginalProfileNameOf(MedusaCoreProfile *_Nullable profile);
bool IsOffTheRecordOf(MedusaCoreProfile *_Nullable profile, NSString *_Nullable name);
NSArray<NSString *> *LoadedProfileNames();

int BrowserId(MedusaCoreTab *tab);
MedusaCoreTab *_Nullable TabWithBrowserId(int browserId);

NSString *AppDisposition(NSString *chromeDisposition);

void InstallActivationGuardsEarly();
void InstallActivationGuardsLate();
bool Background();
void LogActivation(NSString *what);
void SetAppActive(bool active);
void ActToggleFullScreen(NSWindow *window);
void InstallTestCrashGuard(NSString *_Nullable dataDir);

void OpenPopupWindow(MedusaCoreTab *tab, MedusaCoreWebView *_Nullable opener);
bool IsReservedKeyEvent(NSEvent *event);
bool IsReservedBinding(NSString *key, NSString *unshiftedKey, NSEventModifierFlags modifiers);
NSUInteger PopupWindowCount();

}

@interface MedusaCoreWindowController : NSObject <MedusaCoreWindowDelegate>
+ (nullable MedusaCoreWindowController *)forNSWindow:(nullable NSWindow *)window;
+ (NSArray<MedusaCoreWindowController *> *)all;
@property(nonatomic, readonly) MedusaCoreWindow *coreWindow;
@property(nonatomic, strong, nullable) NSView *root;
@property(nonatomic) NSInteger hostChanges;
@property(nonatomic, copy, nullable) NSString *appWindowId;
+ (MedusaCoreWindowController *)strayWindowForProfile:(MedusaCoreProfile *)profile;
+ (nullable MedusaCoreWindowController *)chromeMadeWindowForProfile:(MedusaCoreProfile *)profile;
@property(nonatomic, readonly) BOOL stray;
+ (MedusaCoreWindowController *)standaloneWindowForProfile:(MedusaCoreProfile *)profile;
@property(nonatomic, readonly) BOOL standalone;
- (void)noteClosing:(MedusaCoreTab *)tab;
+ (nullable MedusaCoreWindowController *)holding:(MedusaCoreTab *)tab;
+ (nullable MedusaCoreWebView *)hostingViewForProfile:(nullable MedusaCoreProfile *)profile;
+ (BOOL)userSees:(nullable NSWindow *)window;
@end
extern NSNotificationName const MedusaCoreWindowSeenDidChange;

@interface MedusaCoreTabStrip (Engine)
+ (void)changedInWindow:(MedusaCoreWindowController *)controller profile:(MedusaCoreProfile *)profile;
+ (void)changedInWindow:(MedusaCoreWindowController *)controller profile:(MedusaCoreProfile *)profile cause:(nullable id)cause;
+ (void)windowClosed:(MedusaCoreWindowController *)controller;
+ (void)activated:(MedusaCoreTab *)tab inWindow:(MedusaCoreWindowController *)controller;
+ (nullable MedusaCoreTab *)activeTabInWindow:(MedusaCoreWindowController *)controller profile:(MedusaCoreProfile *)profile;
+ (void)removed:(MedusaCoreTab *)tab fromWindow:(MedusaCoreWindowController *)controller;
+ (void)setPinned:(BOOL)pinned tab:(MedusaCoreTab *)tab;
@end

@interface MedusaCoreProfile (Pending)
- (nullable NSString *)loadComponentExtension:(NSString *)path;
- (void)releaseNavigationHoldReady;
- (void)unloadComponentExtension:(NSString *)extensionId;
@end

namespace medusacore_host {
NSArray<MedusaCoreProfile *> *LoadedProfiles();
void LoadContentBlocker(NSString *profile);
void PrepareContentBlocker();
bool EngineHasTabModel();
}

@interface MedusaCoreTabs : NSObject
+ (void)setView:(nullable MedusaCoreWebView *)view forTab:(MedusaCoreTab *)tab;
+ (nullable MedusaCoreWebView *)viewForTab:(MedusaCoreTab *)tab;
+ (NSString *)offerTab:(MedusaCoreTab *)tab;
+ (NSString *)offerTab:(MedusaCoreTab *)tab prefix:(NSString *)prefix;
+ (nullable MedusaCoreTab *)takeOffered:(NSString *)adoptId;
+ (nullable MedusaCoreTab *)offeredTab:(NSString *)adoptId;
+ (void)forget:(MedusaCoreTab *)tab;
@end

@interface MedusaCoreFavicons (Tabs)
+ (void)noteImage:(nullable NSImage *)image forURL:(nullable NSString *)url profile:(nullable NSString *)profile;
@end

NS_ASSUME_NONNULL_END

#import "MedusaCoreInternal.h"
#import "MedusaCoreWebView.h"

NS_ASSUME_NONNULL_BEGIN

@interface MedusaCoreWebView ()
- (void)openedTab:(MedusaCoreTab *)tab adoptId:(NSString *)adoptId disposition:(NSString *)disposition;
- (void)tabRemovedFromWindow:(MedusaCoreWindow *)window;
- (void)tabActivatedByChrome:(BOOL)chromes;
- (void)requestFocusRestore;
- (void)requestFocusRestoreIn:(NSWindow *)window;
- (void)devToolsChanged:(nullable NSView *)devToolsView;
- (void)emit:(NSString *)name payload:(NSDictionary<NSString *, id> *)payload;
- (void)exitPictureInPictureInFrame:(nullable NSString *)frameId;
+ (void)keepTransfersOfWindow:(NSWindow *)window;
@property(class, nonatomic, readonly, nullable) MedusaCoreTab *launchTab;
@end

NS_ASSUME_NONNULL_END

#import <AppKit/AppKit.h>

@class MedusaCoreTab;

NS_ASSUME_NONNULL_BEGIN

@interface MedusaCoreEarlyWindow : NSObject
@property(class, nonatomic, readonly) BOOL switchedOff;
+ (void)setDataDirectory:(nullable NSString *)directory;
+ (void)noteLayoutChangeIn:(nullable NSWindow *)window;
+ (void)recordNow;
+ (void)prefetchForSession:(NSDictionary *)session;
+ (void)discardPrefetch;
+ (BOOL)canShowWindow:(NSString *)windowId session:(NSDictionary *)session;
+ (BOOL)showWindow:(NSString *)windowId
             frame:(NSArray<NSNumber *> *)frame
               key:(NSString *)key
           profile:(NSString *)profile
          backdrop:(NSDictionary *)backdrop;
+ (void)attachPage:(MedusaCoreTab *)tab key:(NSString *)key;
+ (void)forgetPictures;
+ (void)forgetPicturesNow;
+ (BOOL)holdsPage:(MedusaCoreTab *)tab;
+ (nullable NSWindow *)claimForAppWindow:(nullable NSString *)windowId profile:(nullable NSString *)profile;
+ (BOOL)takeDismissed:(nullable NSString *)windowId;
+ (nullable NSView *)coverInWindow:(nullable NSWindow *)window;
+ (void)rootEmbedded:(NSView *)root inWindow:(NSWindow *)window;
+ (void)pageMoved:(MedusaCoreTab *)tab;
+ (void)pageNavigated:(nullable MedusaCoreTab *)tab launchURL:(nullable NSString *)launchURL;
+ (BOOL)veils:(nullable MedusaCoreTab *)tab;
+ (void)requestFocus:(nullable MedusaCoreTab *)tab;
+ (void)page:(nullable MedusaCoreTab *)tab shownURL:(nullable NSString *)url;
+ (void)pageCommitted:(nullable MedusaCoreTab *)tab shownURL:(nullable NSString *)url;
+ (void)dropPage:(nullable MedusaCoreTab *)tab;
@end

NS_ASSUME_NONNULL_END

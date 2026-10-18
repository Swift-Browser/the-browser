#import <AppKit/AppKit.h>

#define MEDUSACORE_EXPORT __attribute__((visibility("default")))

NS_ASSUME_NONNULL_BEGIN

@class MedusaCoreEngine;
@class MedusaCoreProfile;
@class MedusaCoreTab;
@class MedusaCoreWindow;

@protocol MedusaCoreEngineDelegate <NSObject>
- (void)engineDidStart;
@optional
- (void)engineWillShutDown;
- (void)engineQuitCancelled;
- (nullable MedusaCoreWindow*)engineWindowForNewBrowserOfProfile:(MedusaCoreProfile*)profile
                                                        type:(NSString*)type;
- (void)engine:(MedusaCoreEngine*)engine
    permissionRequest:(NSDictionary<NSString*, id>*)request
                  tab:(MedusaCoreTab*)tab;
- (void)engine:(MedusaCoreEngine*)engine permissionRequestDismissed:(NSString*)requestId;
- (void)engine:(MedusaCoreEngine*)engine
    extensionSidePanel:(NSDictionary<NSString*, id>*)panel
                   tab:(MedusaCoreTab*)tab;
- (BOOL)engine:(MedusaCoreEngine*)engine
    extensionActionPopup:(NSDictionary<NSString*, id>*)popup
                     tab:(MedusaCoreTab*)tab;
- (BOOL)engine:(MedusaCoreEngine*)engine
    extensionActionShortcut:(NSDictionary<NSString*, id>*)shortcut
                        tab:(MedusaCoreTab*)tab;
- (BOOL)engineIsReservedKeyEvent:(NSEvent*)event;
- (BOOL)engineIsReservedKey:(NSString*)key
               unshiftedKey:(NSString*)unshiftedKey
                  modifiers:(NSEventModifierFlags)modifiers;
- (void)engine:(MedusaCoreEngine*)engine
    extensionInstallPrompt:(NSDictionary<NSString*, id>*)prompt
                       tab:(nullable MedusaCoreTab*)tab;
- (void)engine:(MedusaCoreEngine*)engine
    deviceChooser:(NSDictionary<NSString*, id>*)chooser
              tab:(MedusaCoreTab*)tab;
- (void)engine:(MedusaCoreEngine*)engine
    castDialog:(NSDictionary<NSString*, id>*)dialog
           tab:(MedusaCoreTab*)tab;
- (void)engine:(MedusaCoreEngine*)engine
    castRoutes:(NSArray<NSDictionary<NSString*, NSString*>*>*)routes
       profile:(MedusaCoreProfile*)profile;
@end

MEDUSACORE_EXPORT
@interface MedusaCoreEngine : NSObject
+ (int)runWithArgc:(int)argc
              argv:(const char* _Nonnull* _Nonnull)argv
          delegate:(id<MedusaCoreEngineDelegate>)delegate;
@property(class, readonly, nullable) MedusaCoreEngine* sharedEngine;

@property(readonly) MedusaCoreProfile* defaultProfile;
- (void)loadProfile:(NSString*)directoryName
         completion:(void (^)(MedusaCoreProfile* _Nullable profile))completion;
- (void)quit;
@property(nonatomic, copy, nullable) NSString* pageScript;
- (void)resolvePermission:(NSString*)requestId
                   result:(NSString*)result
                 remember:(BOOL)remember;
+ (void)resolveExtensionInstallPrompt:(NSString*)requestId accepted:(BOOL)accepted;
+ (void)startCasting:(int)dialogId sink:(NSString*)sinkId mode:(int)castMode;
+ (void)stopCasting:(int)dialogId route:(NSString*)routeId;
+ (void)closeCastDialog:(int)dialogId;
+ (void)terminateCastRoute:(NSString*)routeId;
+ (void)setAutoPictureInPicture:(BOOL)enabled;
+ (void)setVideoUpscaling:(BOOL)enabled;
+ (void)setVideoUpscalingTestConditions:(NSDictionary<NSString*, NSNumber*>*)conditions;
@property(class, readonly) NSDictionary<NSString*, id>* videoUpscalingState;
+ (void)reservedShortcutsChanged;
+ (BOOL)isReservedGlobalShortcut:(NSString*)shortcut;
+ (void)selectDevice:(int)chooserId index:(int)index;
+ (void)cancelDeviceChooser:(int)chooserId;
+ (void)refreshDeviceChooser:(int)chooserId;
+ (void)openDeviceChooserSettings:(int)chooserId;
+ (void)beginTracing:(void (^)(BOOL started))completion;
+ (void)endTracing:(BOOL)keep completion:(void (^)(NSString* _Nullable path))completion;
@property(class, readonly) BOOL isTracing;
- (void)deleteProfile:(MedusaCoreProfile*)profile
           completion:(nullable void (^)(BOOL deleted))completion;
- (void)releaseProfile:(MedusaCoreProfile*)profile;
+ (void)resolveExternalApp:(NSString*)requestId open:(BOOL)open remember:(BOOL)remember;
@property(class, readonly) NSArray<NSDictionary*>* testExternalLaunches;
@property(class, readonly) NSArray<NSDictionary*>* testChooserEvents;
+ (void)allowDesktopCapture:(NSString*)sourceId
                        tab:(MedusaCoreTab*)tab
                      frame:(nullable NSString*)frameId
                     origin:(nullable NSString*)origin;
- (void)offTheRecordProfileFor:(MedusaCoreProfile*)profile
                    completion:(void (^)(MedusaCoreProfile* _Nullable offTheRecord,
                                         NSString* _Nullable error))completion;
@property(readonly) NSString* chromiumVersion;
@property(readonly) NSString* keepAliveState;
@end

MEDUSACORE_EXPORT
@interface MedusaCoreProfile : NSObject
@property(readonly) NSString* name;
@property(readonly) NSString* path;
@property(readonly) BOOL offTheRecord;
@property(readonly) BOOL destroyed;
- (nullable NSString*)loadComponentExtension:(NSString*)path;
- (void)unloadComponentExtension:(NSString*)extensionId;
- (void)holdNavigationsUntilRulesetsOf:(NSString*)extensionId;
- (void)releaseNavigationHold:(NSString*)reason;
- (void)releaseNavigationHoldReady;
- (void)watchCastRoutes;
@property(readonly) NSArray<NSDictionary<NSString*, id>*>* extensions;
- (nullable NSNumber*)boolPreference:(NSString*)name;
- (void)setBoolPreference:(NSString*)name value:(BOOL)value;
- (void)clearBrowsingData:(NSArray<NSString*>*)types
                    since:(nullable NSDate*)since
               completion:(nullable void (^)(void))completion;
@end

@interface MedusaCoreProfile (Icons)
- (void)fetchIcon:(NSString*)url
         maxBytes:(NSUInteger)maxBytes
       completion:(void (^)(NSData* _Nullable body))completion;
@end

@protocol MedusaCoreWindowDelegate <NSObject>
@optional
- (void)window:(MedusaCoreWindow*)window
    didInsertTab:(MedusaCoreTab*)tab
          opener:(nullable MedusaCoreTab*)opener
     disposition:(NSString*)disposition;
- (void)window:(MedusaCoreWindow*)window didRemoveTab:(MedusaCoreTab*)tab;
- (void)window:(MedusaCoreWindow*)window didActivateTab:(MedusaCoreTab*)tab;
- (void)window:(MedusaCoreWindow*)window
    devToolsDidChangeForTab:(MedusaCoreTab*)tab
                       view:(nullable NSView*)devToolsView;
- (void)window:(MedusaCoreWindow*)window
                    tab:(MedusaCoreTab*)tab
    didChangeFullscreen:(BOOL)fullscreen;
- (void)window:(MedusaCoreWindow*)window
    passwordPrompt:(NSDictionary<NSString*, id>*)prompt
            forTab:(MedusaCoreTab*)tab;
- (void)window:(MedusaCoreWindow*)window
    autofillPrompt:(NSDictionary<NSString*, id>*)prompt
            forTab:(MedusaCoreTab*)tab;
- (void)window:(MedusaCoreWindow*)window
    passwordSavePromptForTab:(MedusaCoreTab*)tab
                    username:(NSString*)username
                      origin:(NSString*)origin;
- (void)window:(MedusaCoreWindow*)window showRequestedActive:(BOOL)active;
- (BOOL)windowShouldClose:(MedusaCoreWindow*)window;
- (void)windowDidCancelClose:(MedusaCoreWindow*)window;
- (void)window:(MedusaCoreWindow*)window
    confirmCloseWithDownloads:(int)count
                   completion:(void (^)(BOOL closeAnyway))completion;
- (BOOL)window:(MedusaCoreWindow*)window preHandleKeyEvent:(NSEvent*)event;
- (BOOL)window:(MedusaCoreWindow*)window handleKeyEvent:(NSEvent*)event;
@end

MEDUSACORE_EXPORT
@interface MedusaCoreWindow : NSObject
- (instancetype)initWithContentRect:(NSRect)rect;
@property(readonly) NSWindow* window;
@property(readonly) NSView* hostView;
@property(weak, nullable) id<MedusaCoreWindowDelegate> delegate;

- (MedusaCoreTab*)openTab:(NSString*)url
              profile:(MedusaCoreProfile*)profile
           foreground:(BOOL)foreground;
- (nullable MedusaCoreTab*)openExtensionView:(NSString*)url
                                 profile:(MedusaCoreProfile*)profile
                                    kind:(NSString*)kind;
@property(nonatomic, nullable) MedusaCoreProfile* activeProfile;
- (void)activateTab:(MedusaCoreTab*)tab;
- (NSArray<MedusaCoreTab*>*)tabsForProfile:(MedusaCoreProfile*)profile;
- (int)chromeWindowIdForProfile:(MedusaCoreProfile*)profile;
- (BOOL)executeChromeCommand:(int)commandId profile:(MedusaCoreProfile*)profile;
- (void)showInactive;
@property(nonatomic) BOOL actedFullScreen;
- (void)close;

- (void)prepareProfile:(MedusaCoreProfile*)profile;
- (void)adoptTab:(MedusaCoreTab*)tab;
- (nullable MedusaCoreTab*)restoreTab:(nullable NSString*)state
                          profile:(MedusaCoreProfile*)profile
                       foreground:(BOOL)foreground;
- (nullable MedusaCoreTab*)duplicateTab:(MedusaCoreTab*)source
                            profile:(MedusaCoreProfile*)profile
                         foreground:(BOOL)foreground;
- (void)placeTab:(MedusaCoreTab*)tab index:(int)index pinned:(BOOL)pinned;
@property(nonatomic) BOOL internal;
@end

@protocol MedusaCoreTabDelegate <NSObject>
@optional
- (void)tabDidChangeTitle:(MedusaCoreTab*)tab;
- (void)tabDidChangeURL:(MedusaCoreTab*)tab;
- (void)tabDidChangeLoading:(MedusaCoreTab*)tab;
- (void)tabDidChangeProgress:(MedusaCoreTab*)tab;
- (void)tabDidChangeFavicon:(MedusaCoreTab*)tab;
- (void)tabDidChangeNavigationState:(MedusaCoreTab*)tab;
- (void)tab:(MedusaCoreTab*)tab didFindMatches:(int)count active:(int)active final:(BOOL)final;
- (void)tab:(MedusaCoreTab*)tab didReceivePageMessage:(NSString*)kind json:(NSString*)json;
- (void)tab:(MedusaCoreTab*)tab
    didReceivePageMessage:(NSString*)kind
                     json:(NSString*)json
                    frame:(NSString*)frameId
                     main:(BOOL)main;
- (void)tabWillClose:(MedusaCoreTab*)tab;
- (void)tab:(MedusaCoreTab*)tab rendererGone:(NSString*)status code:(int)code;
- (void)tab:(MedusaCoreTab*)tab didFailLoad:(NSString*)url code:(int)code description:(NSString*)text;
- (void)tab:(MedusaCoreTab*)tab didChangeStatusText:(NSString*)text;
- (void)tab:(MedusaCoreTab*)tab didRequestAppURL:(NSString*)url userGesture:(BOOL)userGesture;
- (void)tabDidChangeThemeColor:(MedusaCoreTab*)tab;
- (void)tabDidCommitDocument:(MedusaCoreTab*)tab;
- (void)tabDidGainFocus:(MedusaCoreTab*)tab;
- (void)tabDidChangeAudio:(MedusaCoreTab*)tab;
- (void)tabDidChangeSecurity:(MedusaCoreTab*)tab;
- (void)tabDidChangeZoom:(MedusaCoreTab*)tab;
- (void)tab:(MedusaCoreTab*)tab didBlockPopup:(NSDictionary<NSString*, NSString*>*)popup;
- (void)tab:(MedusaCoreTab*)tab preferredSizeDidChange:(NSSize)size;
- (void)tab:(MedusaCoreTab*)tab externalAppRequest:(NSDictionary<NSString*, id>*)request;
- (void)tab:(MedusaCoreTab*)tab requestsActivation:(NSString*)reason;
- (void)tab:(MedusaCoreTab*)tab didChangePictureInPicture:(NSDictionary<NSString*, id>*)state;
- (void)tab:(MedusaCoreTab*)tab didShowAutofillSuggestions:(NSArray<NSDictionary<NSString*, NSString*>*>*)items;
- (void)tab:(MedusaCoreTab*)tab didBlockRequests:(int)count lastURL:(NSString*)url;
- (NSArray<NSDictionary<NSString*, NSString*>*>*)tab:(MedusaCoreTab*)tab
                         contextMenuItemsForSelection:(NSString*)text;
- (void)tab:(MedusaCoreTab*)tab
    contextMenuCommand:(NSString*)itemId
                  text:(NSString*)selection
             modifiers:(NSDictionary<NSString*, NSNumber*>*)modifiers;
- (void)tab:(MedusaCoreTab*)tab didShowContextMenu:(NSArray<NSDictionary*>*)items;
- (nullable NSDictionary<NSString*, id>*)tab:(MedusaCoreTab*)tab
                              runContextMenu:(NSDictionary<NSString*, id>*)menu;
- (void)tab:(MedusaCoreTab*)tab navigationBecameDownload:(NSString*)url;
- (void)tabDidChangeDiscarded:(MedusaCoreTab*)tab;
- (void)tabBecameUnresponsive:(MedusaCoreTab*)tab;
- (void)tabBecameResponsive:(MedusaCoreTab*)tab;
- (void)tab:(MedusaCoreTab*)tab didChangeMediaAccess:(NSDictionary<NSString*, NSNumber*>*)access;
@end

MEDUSACORE_EXPORT
@interface MedusaCoreTab : NSObject
@property(readonly) NSView* view;
@property(readonly, weak) MedusaCoreProfile* profile;
@property(readonly) int tabId;
@property(readonly) NSString* url;
@property(readonly) NSString* title;
@property(readonly) BOOL loading;
@property(readonly) double progress;
@property(readonly, nullable) NSImage* favicon;
@property(readonly) BOOL canGoBack;
@property(readonly) BOOL canGoForward;
@property(readonly) BOOL closed;
@property(weak, nullable) id<MedusaCoreTabDelegate> delegate;

- (void)loadURL:(NSString*)url;
- (void)focus;
- (void)find:(NSString*)text forward:(BOOL)forward;
- (void)stopFinding;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;
- (void)close;
- (void)showDevTools;
- (void)closeDevTools;
@property(readonly, nullable) NSView* devToolsView;
- (void)devToolsLayoutForSize:(NSSize)size
                     devTools:(NSRect*)devToolsFrame
                         page:(NSRect*)pageFrame;
@property(readonly, nullable) NSDictionary<NSString*, id>* passwordPrompt;
- (void)resolvePasswordPrompt:(NSString*)action
                     username:(nullable NSString*)username
                     password:(nullable NSString*)password;
@property(readonly, nullable) NSDictionary<NSString*, id>* autofillPrompt;
- (void)resolveAutofillPrompt:(NSInteger)promptId action:(NSString*)action;

@property(readonly, nullable) NSString* faviconURL;
@property(readonly, nullable) NSString* themeColor;
@property(readonly) BOOL audible;
@property(nonatomic) BOOL muted;
@property(readonly) int browserId;
@property(readonly, nullable) NSString* committedOrigin;
@property(readonly) BOOL initialDocumentAccessed;
@property(readonly) BOOL committedInitial;
- (nullable id)suppressInput;
- (void)loadURL:(NSString*)url userInitiated:(BOOL)userInitiated;
- (void)goToOffset:(int)offset;
- (void)reloadIgnoringCache;
- (void)closeNow;
@property(readonly) NSArray<NSDictionary<NSString*, id>*>* navigationEntries;
- (void)executeJavaScript:(NSString*)code;
- (void)executeJavaScript:(NSString*)code userGesture:(BOOL)userGesture;
- (void)executeJavaScript:(NSString*)code frame:(NSString*)frameId;
- (void)evaluate:(NSString*)code completion:(void (^)(NSString* _Nullable json))completion;
- (void)evaluate:(NSString*)code
     userGesture:(BOOL)userGesture
      completion:(void (^)(NSString* _Nullable json))completion;
- (void)callPage:(NSString*)kind json:(NSString*)json;

@property(readonly) NSDictionary<NSString*, id>* securityInfo;
@property(nonatomic) double zoomFactor;
- (void)zoomStep:(int)direction;
@property(readonly) double pinchScale;
- (BOOL)executeChromeCommand:(int)command;
- (void)openBlockedPopup:(NSString*)popupId always:(BOOL)always;
- (BOOL)discard;
@property(readonly) BOOL discarded;
@property(nonatomic) BOOL frozen;
- (void)resolveUnresponsive:(BOOL)terminate;
@property(nonatomic, nullable) NSColor* pageBackgroundColor;
@property(nonatomic, copy, nullable) NSString* pageColor;
- (NSString*)executeExtensionAction:(NSString*)extensionId;
- (NSDictionary<NSString*, NSDictionary*>*)actionStatesForExtensions:(NSArray<NSString*>*)extensionIds;
- (nullable NSString*)sidePanelURLForExtension:(NSString*)extensionId;
@property(readonly, nullable) NSString* mediaCaptureSourceId;
- (void)copyPicture:(NSTimeInterval)timeout completion:(void (^)(CGImageRef _Nullable picture))completion;
- (BOOL)stopCapture;
@property(readonly) BOOL autoPictureInPictureIsChromes;
- (void)noteShownByHost:(BOOL)shown;
- (void)exitFullscreen;
- (void)exitExclusiveAccess;
- (void)tracePictureInPicture:(NSString*)line withInputs:(BOOL)withInputs;
- (void)devToolsCall:(NSString*)method
              params:(nullable NSDictionary*)params
          completion:(void (^)(NSDictionary* _Nullable result,
                               NSString* _Nullable error))completion;
- (void)devToolsCall:(NSString*)method
              params:(nullable NSDictionary*)params
             timeout:(NSTimeInterval)timeout
          completion:(void (^)(NSDictionary* _Nullable result,
                               NSString* _Nullable error))completion;
- (BOOL)canShareThisTabInsteadFor:(MedusaCoreTab*)capturer;
- (BOOL)shareThisTabInsteadFor:(MedusaCoreTab*)capturer;
- (BOOL)showAutofillSuggestions:(BOOL)passwords;
- (BOOL)showCastDialog;
- (BOOL)devShowBluetoothChooser:(BOOL)unauthorized;
@property(readonly, nullable) NSDictionary<NSString*, NSNumber*>* popupFeatures;
@property(readonly) NSSize preferredSize;
- (void)callFrame:(NSString*)frameId kind:(NSString*)kind json:(NSString*)json;
@end

NS_ASSUME_NONNULL_END

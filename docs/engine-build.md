# Building the engine from source

Medusa runs on MedusaCore: Chrome's own framework (`//chrome:chrome_framework`) built from our Chromium tree, with our
layers linked in (`docs/medusacore-spike.md`). The tree is plain **Chromium 155.0.8059.84** (`CHROMIUM_VERSION` in
`env.sh`), then ungoogled-chromium, then our patch series. Nothing of CEF's is checked out or built. CEF left the tree
on 2026-10-09: its 117 patches to Chrome are gone, except a few kept as `chromium-cef-carryover.patch`
([below](#cefs-117-patches)), and the seams of theirs MedusaCore used are our own hooks H1–H6
([below](#our-hooks-in-chromes-code)). The framework is still named "Chromium Framework". Crashpad stays off.

What the build adds:

- **H.264 / AAC.** Set with `proprietary_codecs=true` and `ffmpeg_branding="Chrome"`; H.264 decodes
  through VideoToolbox.
- **Chrome's release optimisations**, as Helium ships them: an official build with ThinLTO and PGO (Chromium's own
  mac-arm profile). See [Helium](#helium) for what else came from Helium and what didn't.
- **ungoogled-chromium** 155.0.8059.84-1 (macOS 155.0.8059.39-1.1). Its patch series and domain substitution strip
  Google background services; see [ungoogled-chromium](#ungoogled-chromium). The Chrome Web Store and
  extension auto-updates are deliberately kept working.
- **Our patches**, in `engine/patches/`, applied in the order `engine/patches/series` gives (see
  [The patch series](#the-patch-series)):

| Patch | What it does |
|---|---|
| `chromium-cef-carryover.patch` | The CEF patches we keep ([CEF's 117 patches](#cefs-117-patches)): `BrowserManagerService::DeleteBrowser`'s destruction order, no `NOTREACHED` for unmapped Mac key codes, bubbles kept on screen on the Mac (`kAdjustBubbleIfOffscreen`), a window with a child-modal sheet resizable and the sheet's focus back after the resize, the ResourceBundle delegate parameter H5 passes to `LoadLocalState`, the tab strip API's colour provider without an active tab, and `browser_tests` building without background mode (for `enable_background_mode=false`) |
| `chromium-extension-window-hidden.patch` | The windows of MedusaCore's own pages are invisible to chrome.windows/tabs (`g_medusa_hidden_from_extensions`, also read by the next patch and apply.sh's `browser_window_util` hook): not listed, not found by id (`ExtensionTabUtil::GetTabById` and `GetControllerInProfileWithId`, so tabs.get/update/remove, scripting and tabs.sendMessage on a leaked id fail as for a closed tab), no tabs events (`TabsEventRouter::ShouldTrackBrowser`) and no webNavigation events for their tabs, or for tabs they open |
| `chromium-component-extension-restricted-urls.patch` | Chrome lets every `kComponent` extension script any page (`PermissionsData::CanExecuteScriptEverywhere`), Web Store included. For the component extensions Medusa bundles (`g_medusa_restricted_component_extension`, set in every process by `ACMainDelegate`: uBlock Origin's id), `IsRestrictedUrl` makes Chrome's usual checks anyway: no scripts on the Web Store, chrome:// pages or other extensions' pages. Nothing else about `kComponent` changes |
| `chromium-password-bubble-hook.patch` | MedusaCore may replace Chrome's password bubble (`g_medusa_password_bubble`) |
| `chromium-extension-install-prompt-hook.patch` | MedusaCore may replace Chrome's extension install dialog (`g_medusa_extension_install_prompt`) |
| `chromium-branding.patch` | Medusa's bundle and team id (`branding_file_path`), for the passkey and payments keychain access groups; product names stay "Chromium" |
| `chromium-safe-storage-name.patch` | The Safe Storage key lives in its own "Medusa Safe Storage" keychain item, account "Medusa". **Load-bearing:** it's Chromium's own `os_crypt` code, so MedusaCore uses it too, and every user's saved passwords and cookies are encrypted with that item's key. Keep it, unchanged, through every re-sync and version bump; without it Chrome reads "Chromium Safe Storage" and nothing decrypts |
| `chromium-device-chooser-hook.patch` | `chrome::ShowDeviceChooserDialog` (and its extension-page variant) asks MedusaCore (`g_medusa_device_chooser`) once Chrome's `DropFullscreenForChooserDialog` has dropped the page's full screen and revalidated the frame and active tab: MedusaCore gets that WebContents and the full-screen blocker, which its chooser holds until it closes |
| `chromium-cast-dialog-hook.patch` | The Media Router's Cast dialog (and Presentation API requests) asks MedusaCore first (`g_medusa_wants_cast_dialog`, `g_medusa_cast_dialog`). Both paths reach `CreateMediaRouterDialog`, which asks MedusaCore only after Chrome's `ForSecurityDropFullscreen` has dropped the page's full screen and the window has survived the drop; MedusaCore gets the full-screen blocker and its Cast dialog (`ac_cast_dialog.mm`) holds it until it closes, so a page can't re-enter full screen over the picker |
| `chromium-side-panel-hook.patch` | `side_panel_util` asks MedusaCore first for an extension's side panel (`g_medusa_extension_side_panel`) |
| `chromium-initial-document-access.patch` | When another frame touches a tab's initial empty document (`RenderFrameHostImpl::DidAccessInitialMainDocument`, primary frame tree), MedusaCore hears it (`g_medusa_initial_main_document_accessed`): the tab sends a URL and navigation-state change, as Chrome's omnibox stops showing the pending URL then. `content::MedusaHasAccessedInitialMainDocument` answers `WebContentsImpl::HasAccessedInitialDocument`, which 155 no longer has on the public `WebContents`; `MedusaCoreTab.initialDocumentAccessed` and `.committedInitial` (the last committed entry is the initial one) report them |
| `chromium-hidden-window-current-window.patch` | Extension pages in hidden windows (our popups and side panels) take the last active window as their current window |
| `chromium-extension-updates.patch` | Undoes ungoogled's early `return` in `UpdateCheckerImpl::CheckForUpdates`, which left every update check pending: Web Store extensions never updated |
| `chromium-extension-omaha-attributes.patch` | Google's kill switch for extensions works again: the update check's `_malware`, `_policy_violation` and `_potentially_uws` answers reach `ExtensionService::PerformActionBasedOnOmahaAttributes` and its `OmahaAttributesHandler`, which blocklist (malware: unloaded, "This extension contains malware.") or greylist (disabled) the extension, as in Chrome. It restores what `fix-building-without-safebrowsing` cut with Safe Browsing: the handler in `chrome/browser/extensions/BUILD.gn` and `ExtensionService`, `ChromeExtensionSystem`'s forwarding, `UpdateService::OnCrxStateChange`'s call, and the bodies of `ExtensionRegistrar::OnBlocklistState*`/`OnGreylistState*`. Safe Browsing's own verdict handlers stay cut |
| `chromium-window-docked-devtools.patch` | `DevtoolsUIController::UpdateDevtools` tells MedusaCore of every change to a tab's docked DevTools (`g_medusa_devtools_dock_changed`). DevTools may dock in any Browser, as in stock Chrome (CEF had turned docking off for every Browser but MedusaCore's own) |
| `chromium-devtools-redock-display.patch` | A `RenderWidgetHostViewMac` that a `views::WebView` gives up (`SetParentUiLayer(nullptr)`) draws into its own NSView again. Chrome switched it to the Views compositor for good the first time it was attached, so DevTools docked back from their own window stayed blank in the client's view |
| `chromium-window-hosted.patch` | `BridgedContentView.medusaEmbeddedView`: hit testing and accessibility ask the embedder's subview of a Chrome window's content view first. A Browser MedusaCore says so of (`g_medusa_keeps_window_without_tabs`) stays open when its last tab closes, unless the window is closing |
| `chromium-devtools-window-title.patch` | DevTools' title is Dia's, "Developer Tools - <url>" (`DevToolsUIBindings` `kTitleFormat`), so Chrome's own undocked DevTools window says so too |
| `chromium-devtools-control-token.patch` | The `medusa` command's control server: a DevTools HTTP handler whose socket factory MedusaCore claims (`g_medusa_devtools_token_factory`) runs in token mode. Every WebSocket upgrade, browser or page, needs `?token=` (`g_medusa_devtools_token_accepts`, compared in constant time; 403 otherwise) and is routed without its query; `/json*`, `/` and `/devtools/*` answer 404, and so does every other route but `GET /medusa/active?token=` (no Origin): `{"targetId": …}`, the DevTools page target of the tab the user is looking at in the last focused window, or null for New Tab and Medusa's own pages (the app reports that tab, `ac_cli_control {active}`), since an occluded window's pages all report hidden; Chrome's Host check stays and any Origin is refused, whatever `--remote-allow-origins` says; a handshake Chrome's WebSocket code would refuse (version, key) is refused before it counts. The handler reports listening, failing, going away and its connection count (`g_medusa_devtools_token_server`). The owner is `//chrome/browser/medusa` `ac_cli_control.cc` (engine call `ac_cli_control`): one server per start with a new token, published in `<user data dir>/MedusaControl.json` (0600, written atomically, deleted on stop and at quit), never `DevToolsActivePort`. A start settles only once that file is written (a failed write stops the server and says why), and a write still queued after a stop never lands (its generation check and rename hold the lock a stop takes to revoke it). It stops when the `RemoteDebuggingAllowed` policy turns off, and stands aside when `--remote-debugging-port` runs a server. The app turns off `DevToolsAcceptDebuggingConnections` (`MedusaCoreHost.mm`): chrome://inspect's approval mode would swap the process's one handler for its own. **A token client gets what page JS could, plus navigation, input and screenshots** (`ac_cli_token_policy.cc`, owned by `ac_cli_control.cc`; the plain `--remote-debugging-port` server is untouched): every client of a token server gets an `MedusaDevToolsTokenClient` (`g_medusa_devtools_token_client`; a token server whose policy is missing refuses every socket). Commands, flattened child sessions included, pass an allowlist (Target discovery/attach/create/close with `flatten:true`, `Browser.getVersion`, reading DOM and Accessibility, ordinary Page/Runtime/Input calls, `Network.enable` and body reads); anything else answers `medusa: <Method> isn't allowed for the medusa command` (-32601). The allowed ones are checked further (-32000): destinations of `Page.navigate`/`Target.createTarget` are http(s), `about:blank`, `data:` or a web origin's `blob:`; execution contexts, and the context part of every object id (`<isolate>.<context>.<n>`), must be the page's main worlds, bound to the target's renderer process: learned only from `Runtime.executionContextCreated` with `isDefault`, from the `result.objectId` of a `Runtime.evaluate` without a context and the `object.objectId` of a `DOM.resolveNode` without one (both run in the default world; no other reply values are read), and from the client's own `Page.createIsolatedWorld`, whose `grantUniveralAccess` is forced off, so extensions' isolated worlds are unreachable and unannounced; no `includeCommandLineAPI`, named worlds on new documents or PDF streams. `Input.dispatchKeyEvent` takes only reviewed editing `commands` (caret moves and selection, deletes, newline and tab, select all, undo and redo; nothing that touches the clipboard, and no print) and loses `nativeVirtualKeyCode` and `isSystemKey`, so a key event carries no native event and is `skip_if_unhandled`: it reaches the renderer only, never Chrome's or the app's shortcuts and menu. Input lands only in an authorized frame: `InputHandler` checks the widget it resolved (hit testing for mouse and touch, the focused widget for keys and text) against `g_medusa_devtools_may_input` for every frame of that widget, and drops the event otherwise. A command's envelope may hold only `id`, `method`, `params` and `sessionId`, and its `sessionId` must name a session this client has attached; anything else is refused. Every command is tracked by (session, id) until its reply; a second command with the same pair is refused before dispatch, so a reply always belongs to one command (ids are read signed, and the reply's session from its trailing `sessionId`). A tracked reply that can't be parsed is dropped, and past 4096 commands outstanding on a socket (Chrome drops some without a reply, such as a navigation `Page.disable` cancels) the socket is closed with that reason rather than left wedged; a session's entries go when it detaches, crashes or its target goes away (`Target.detachedFromTarget`, `Inspector.targetCrashed`, `Inspector.detached`). With `SyntheticPointerActions` on, touch goes through Chrome's synthetic gestures, which skip the destination check, so token clients get no touch then; a drag's drop is checked against the widget it lands on too. Targets in internal Medusa windows, outside a tab strip, or not at a web URL or origin can't be attached (`g_medusa_devtools_may_attach` in `DevToolsAgentHostImpl::AttachInternal`, so workers and auto-attach too, plus the client's `MayAttachToURL`/`MayAttachToRenderFrameHost`, which detach a session whose tab navigates away, and a 403 for such a page socket), and don't appear in `Target.getTargets` or Target events. Local files are off (`MayReadLocalFiles`/`MayWriteLocalFiles`). Outbound, `Network.*ExtraInfo` and early-hints events are dropped and `Cookie`, `Set-Cookie`, `Authorization`, `Proxy-Authorization` and raw header text are stripped from the rest; only Network, Runtime and Target events and tracked replies are parsed, so screenshots pass untouched |
| `chromium-neterror-game.patch` | "Where's the lamb?" replaces the dino: the offline page and chrome://game (below) |
| `chromium-autofill-address-bubble-window.patch` | Chrome's offers to save or update an address (and its address sign-in promo) look the `AutofillBubbleHandler` up on the tab's Browser (`AutofillBubbleHandler::Get` on its unowned user data, as the save-card bubble already does), so they reach MedusaCore's handler (`ACBrowserWindow::AttachBrowser` registers it): `FindBrowserWindowWithWebContents` finds BrowserViews only. It also carries CEF's `chrome_autofill_bubble_3796`: a tab with no window, or a handler that shows nothing, gets no address or card bubble instead of a crash |
| `chromium-password-generation-local.patch` | Chrome offers "Suggest strong password" without password sync (`PasswordFeatureManagerImpl::IsGenerationEnabled`); generated passwords save to the profile's local store like any other. With no account, its popup says "Passwords are saved to Password Manager on this device." instead of "…saved to Google Password Manager for ." |
| `chromium-extension-installed-bubble.patch` | Chrome's "<extension> has been added" bubble (`ShowInfoDialog`): a window without Chrome's toolbar (every client window) gets it as a bubble under the top-right corner of the window, with a close button, closing on Esc and when the window is clicked. Chrome fell back to a browser-modal sheet there, with no buttons and no way to dismiss it. The app renames "Chromium" in Chrome's strings itself (`ac_strings.cc`) |
| `chromium-tab-sharing-capturer.patch` | Each tab-sharing infobar remembers the frame whose capture it's for (`TabSharingInfoBarDelegate::capturer_id()`): a tab shows one infobar per share, and "Share this tab instead" moves only that share, never another call's |
| `chromium-video-super-resolution.patch` | Video upscaling on Apple silicon: a per-compositor gate (`RenderWidgetHostView::SetVideoSuperResolutionAllowed` → `BrowserCompositorMac`, kept across its compositors → `ui::Compositor` → `DisplayPrivate.SetVideoSuperResolutionAllowed` → `viz::Display`, which redraws once on a change → `gfx::FrameData`) reaches the GPU process's `ImageTransportSurfaceOverlayMac::Present`, where `CALayerTreeCoordinator::UpscaleVideo` hands the frame's video layers to MedusaCore's upscaler (`g_medusa_create_video_upscaler`, set in the GPU process; `//medusa/core` `ac_video_upscaler.mm`). A frame whose upscale has just started holds its CA commit until the job completes (at most 0.6 of a display frame, 4–10 ms, posted, never blocking the GPU thread); a later finish replaces the committed layer's contents in a small CA commit, a redraw of the same frame takes the cached output at once, and the contents are a `CALayer`'s IOSurface or an `AVSampleBufferDisplayLayer`'s buffer alike. The browser side decides the gate (`ac_video_upscaling.mm`) |
| `chromium-safe-browsing-off-file-types.patch` | With `safe_browsing_mode=0`, `components_resources` still builds the download file types protobuf the download code reads (Helium carries the same fix) |
| `chromium-background-features-off.patch` | Background work Helium turns off, off by default here too: history clustering (Journeys), the Topics API, the Protected Audience (FLEDGE) runtime feature, Live Caption (so no on-device speech model download) and the outdated build check's timer |
| `chromium-medusa-layer.patch` | The macOS `//chrome:chrome_dll` (MedusaCore's framework) links `//chrome/browser/medusa` and exports its `ac_*` calls |
| `chromium-pip-overlay-window.patch` | Chrome makes our `MedusaVideoOverlayWindow` (`chrome/browser/medusa/pip/`, a `VideoOverlayWindowViews` subclass with its own buttons, progress bar, fade and bounds memory; the hook makes six methods virtual): Dia's video Picture in Picture window (measured in `docs/dia-spec.md` › Picture in Picture): nothing but the video at rest (the origin shows only with the controls); on hover a 35 % black scrim, back to tab (top left) and close (top right) as 28 pt rounded squares with 1 pt line glyphs, the origin centred in 13 pt, a bare play/pause glyph and a 5 pt progress bar that seeks; no skip, time, mute, captions or minimize controls (the keyboard shortcuts stay). Controls fade in 200 ms ease-in-out. The window shows at once and fades out in Core Animation (100 ms from the close button, 70 ms otherwise, smooth while the tab is being shown), and a new window opens where the last one was left, sized to the new video and kept on screen (`MedusaPictureInPicture.plist` in the user data dir). Closing it, by its button or by the window going away any other way, never pauses the video, which keeps playing in its tab, as in Dia and Arc (`OnCloseButtonPressed` asks for `kCloseWindowOnly`, and the subclass's `OnNativeWidgetDestroyed` tells the controller not to pause; Chrome paused whenever the window had a play/pause button) |

Removed, all in git history:

- 2026-10-15: `chromium-ui-update-before-insert.patch` and `chromium-tab-strip-notify-before-insert.patch` (CEF's guards
  for an embedder that made the Browser a tab's delegate before inserting it; MedusaCore never does, and an instrumented
  build never hit either guard across popups, `target=_blank`, ⌘-click, `window.open`, session restore, splits and tabs
  moved between windows), `chromium-icloud-keychain-window.patch` (the tab's window is MedusaCore's `views::Widget`, so
  Chrome's own branch hands iCloud Keychain that window) and `chromium-pip-close-keeps-playing.patch` (now
  `MedusaVideoOverlayWindow`'s close button and `OnNativeWidgetDestroyed`).
- 2026-10-09, with CEF: `chromium-webview-native-hosted.patch`, `chromium-browser-view-hosted-fullscreen.patch` and
  `chromium-autofill-card-touchbar.patch`, which served CEF's hosted tabs and views-hosted windows. MedusaCore has neither.
- 2026-10-08: our 18 `cef-*.patch` to CEF's own tree (the CEF runtime's API the app used before MedusaCore, `CEF_AC_*`).
- After 0.2.19: `chromium-zz-extensions-page-uninstall.patch` (chrome://extensions uninstalled without Chrome's
  dialog), with the hidden chrome:// pages it served.
- 0.2.0: `chromium-context-menu-hosted.patch`, with the hidden "ghost" Browser windows.

## Using it

The app's build (`apps/browser/macos`) stages `out/Release_GN_arm64/Chromium Framework.framework` itself
(`packages/medusacore/scripts/stage-framework.sh`, under the chromium lock) and embeds it (`embed.sh`). A checkout without a
Chromium tree downloads the prebuilt engine matching `engine/` instead (`packages/medusacore/scripts/fetch-engine.sh`,
published with each release whose engine changed; `docs/releasing.md`). After an engine change, rebuild incrementally
(`scripts/agent/engine-build`, or `scripts/agent/locked chromium -- autoninja -C out/Release_GN_arm64 chrome_framework`)
and the next app build picks it up.

## Our hooks in Chrome's code

Where our patches and `engine/medusacore/apply.sh` let MedusaCore decide something in Chrome's code, the hook is a
`g_medusa_*` function pointer (or flag) defined in the Chrome file that calls it; unset, Chrome behaves as stock. Each is
declared once, in `//medusa/core`'s `ac_hooks.h` (hooks in `chrome/`) or `ac_content_hooks.h` (in `content/`,
`components/`, `extensions/`, which can't see `chrome/`'s headers), and both the Chrome file and MedusaCore include that
header (`// nogncheck`), so a signature that drifts on either side is a compile error, not a crash at the first call.
(Some changes are direct instead: `ChromeMain` making MedusaCore's main delegate, the PiP window factory, the `CHECK`s made tolerant of a Browser without a `BrowserView`.) MedusaCore sets the patches' hooks as
the browser process starts (`ACMainDelegate::PreSandboxStartup`), in `medusacore::InstallChromeHooks` (`ac_seams.mm`: the
password bubble, the extension install prompt, device choosers, the Cast dialog, extension side panels, hidden
windows, windows without tabs, docked DevTools' changes, the WebContentsDelegate (H2), and `g_medusa_viewless_browsers`, which apply.sh's toast and
reading mode hooks read); apply.sh's other hooks are set next to the code they serve.

`apply.sh` also adds H1–H6, which stand where CEF's patches had seams MedusaCore used. "Is this Browser ours" is
`WindowHost::ForBrowser`: MedusaCore's record (`ac_browser_window.h`), made when a Browser gets one of MedusaCore's
`ACBrowserWindow`s and dropped when its `ACWebContentsDelegate` goes in `~Browser`, after the window.

| Hook | Where | What | Replaces |
|---|---|---|---|
| H1 | `browser.cc` | With `g_medusa_browser_window_factory` set, a Browser may take the host's own `BrowserWindow` (`params.window`) without `CHECK_IS_TEST` | CEF's removed `CHECK` |
| H2 | `browser_window_features.cc` `InitPostWindowConstruction` | `g_medusa_create_web_contents_delegate` makes MedusaCore's `BrowserWebContentsDelegate` for its Browsers | `cef::BrowserDelegate::CreateWebContentsDelegate` |
| H3 | `permission_prompt_factory.cc` | `g_medusa_create_permission_prompt` | `SetCreatePermissionPromptFunction` |
| H4 | none: `ACContextMenu` (`ac_context_menu.mm`) overrides `RenderViewContextMenuMacCocoa::Show()` | in background mode the menu goes to the host, not the screen | `RegisterMenuShowHandlerCallback` |
| H5 | `chrome_main_delegate.cc` | `g_medusa_resource_bundle_delegate`, passed where Chrome inits the shared ResourceBundle | CEF's `GetResourceBundleDelegate()` |
| H6 | `chrome_main_delegate.cc`, `chrome_browser_main.cc`, `chrome_browser_main_mac.mm`, `chrome_content_browser_client.cc`, `chrome_browser_policy_connector.cc` | `g_medusa_embedder` (set by `ACMainDelegate` in every process) skips at run time what `chrome_runtime.patch` compiled out under `ENABLE_CEF`: `InitializeUserDataDir` and startup metrics, `RecordCoreSystemProfile`, crash keys, the crash reporter and crashpad; `StartupBrowserCreator::Start` and the `RunLoop` (not a no-op under `--no-startup-window`: it sets up profiles and Chrome's own main `RunLoop`); `AppController` and `BuildMainMenu`, `didEndMainMessageLoop`; the `HandleWebUI` handler pair (it rewrites `chrome://` URLs and claims them as WebUI, so it isn't a no-op either). First run and `--make-default-browser` need no hook: `ACMainDelegate::BasicStartupComplete` gives the browser process `--no-first-run` (so `IsChromeFirstRun()` is false), `--no-default-browser-check` and `--no-startup-window`, and drops `--make-default-browser`. And no platform policy provider (`CreatePlatformProvider`), as CEF made none without a policy id: the macOS one's first load ran on the main thread before `BrowserMain`, waiting for `/usr/bin/profiles`, 10–20 ms of every launch | `chrome_runtime.patch`'s `#if !BUILDFLAG(ENABLE_CEF)` blocks; `chrome_browser_policy.patch`'s `CreatePlatformProvider` |

apply.sh also has three hooks for idle wakeups:
- `cpu_health_tracker.cc`: with `g_medusa_skip_cpu_health_sampling`, `CpuHealthTracker` gets no `CpuProbe`, so there's
  no 15 s CPU sampling. That sampling only feeds Chrome's performance-intervention toolbar button.
- `system_memory_pressure_evaluator_mac.cc`: with `g_medusa_disk_space_check_seconds`, free disk is checked at that
  period while more than 20 GiB are free, and at Chrome's 5 s otherwise.
- `extension_action_storage_manager.cc`: restored browser-action defaults notify the `ExtensionActionDispatcher`, so
  `ac_extensions_watch_actions`' watchers see them.

`ACMainDelegate::BasicStartupComplete` sets the first two (60 s) and turns on
`PartitionAllocAdaptiveMemoryReclaimInterval`. Kill switches: `MEDUSA_CPU_HEALTH_SAMPLING=on`,
`MEDUSA_DISK_CHECK_SECONDS=5`, `MEDUSA_PA_RECLAIM=fixed`. HangWatcher stays on; `MEDUSA_HANG_WATCHER=off` turns it off.

`settings_storage_quota_enforcer.cc`: with `g_medusa_lazy_storage_usage` (set by `ACMainDelegate`), a write that ignores
the quota (an extension with `unlimitedStorage`, or sync) and any `remove` or `clear` go straight to the store while
usage hasn't been counted yet, instead of first reading and re-serializing every stored value to count it. The count is
still made, from the store as it is then, when something needs it (`getBytesInUse`, a quota-checked write). When
such an op finds a corrupt value and deletes it (`VALUE_RESTORE_DELETE_SUCCESS`), it runs once more, as the scan's
deletion used to let it succeed. uBlock
Origin keeps ~30 MB in `chrome.storage.local`, and its first write of a session (its request counts, ~4 minutes after
launch) cost ~180 ms on a performance core. Kill switch: `MEDUSA_LAZY_STORAGE_USAGE=off`.

## The offline page

Wherever Chrome would start the dino (`LocalizedError::IsOfflineError`: `ERR_INTERNET_DISCONNECTED`, or a DNS
probe that ends in `DNS_PROBE_FINISHED_NO_INTERNET`; main frames only; not with `--disable-dinosaur-easter-egg`),
`NetErrorHelper` serves `IDR_MEDUSA_GAME_HTML` instead of `neterror.html`: the game from
`apps/browser/assets/offline-game`, one self-contained document (3.8 MB, brotli in `resources.pak`: CSS, scripts and
manifest inline, every WebP a `data:` URL, a CSP that allows exactly those inline blocks by hash). Its
`<script type="application/json" id="game-error">` block gets `{code, url}` of the failed load, which the game reads as
`window.GAME_ERROR`. Every other error keeps Chrome's page. A DNS probe that turns the page offline after it loaded
swaps the game's document in (`document.write`), where Chrome's page would start the dino. The page runs as Chrome's
error page, so Retry is `errorPageController.reloadButtonClick()` and the best score is Chrome's easter-egg high
score (`trackEasterEgg` / `updateEasterEggHighScore`).

The page paints itself in the tab's profile colour: the app sets `-[MedusaCoreTab pageColor]` (WebView `pageColor`),
MedusaCore sends it to each main frame as it is created (`ACPage.SetPageColor`, before the frame's first commit) and
again on change, and the renderer sets `window.medusaPageColor` (and fires `medusapagecolor`) in error pages only,
before their own scripts; web pages never see it. game.js recolours the backgrounds on a canvas as the New Tab mark is
recoloured, from `offline-game-pipeline/tint_maps.py`'s maps (`assets/bg-map`, 35 KB) and per-scene statistics.

`chrome://game` (the app's `medusa://game`) is an alias of `chrome://dino`: a simulated `ERR_INTERNET_DISCONNECTED`
whose page plays the game on its own, without the offline header. Tabs, popups and side panels share the renderer, so
all of them show it.

The resource file is generated, not patched in: `game-resource.sh` runs
`apps/browser/assets/offline-game-pipeline/inline.py` (Python standard library only) into
`components/neterror/resources/game/game.html` of the Chromium tree. `apply-chromium-patches.sh` and step 5 run it,
and `scripts/agent/engine-build` runs `inline.py` itself (it rewrites the file only when it changed), so every build ships the game folder as it is; `AC_REPO` (in `env.sh`, default the checkout `env.sh` is in, or
`~/Documents/medusa` for the step scripts' copy in `~/chromium-build/scripts`) says where the checkout is. The sprites stay at the art pipeline's 400 px: at the default zoom the front rows already draw them at
about 1:1 on a 2x screen, so 256 px sprites (about 1 MB) would be visibly soft.

## Nothing writes into the app bundle

The signature seals every file in `Medusa.app`, so the app must never write there: one added file and
`codesign --verify --deep --strict` fails ("a sealed resource is missing or invalid"), and an app on a read-only
volume or run translocated can't be written at all. A background run of a signed build, with pages, PDFs, the offline
page, chrome://settings, chrome://extensions, chrome://components and uBlock's own pages, then a diff of the bundle,
found one writer (2026-09-25):

- **declarativeNetRequest indexes next to the extension.** An extension's static rulesets are indexed into
  `<extension>/_metadata/generated_indexed_rulesets/_ruleset<N>`, a path Chrome derives from the extension's folder
  (`FileBackedRulesetSource::CreateStatic`). The ruleset checksums live in the profile's prefs, so a profile with none
  (every new profile; component extensions are never "installed") indexes again, and so does any profile whose
  indexes go stale (a new indexed format in a Chrome update). Shipping prebuilt indexes wouldn't stop the writes.
  So `MedusaCoreContentBlocker.mm` loaded uBlock Origin Lite from a writable copy in the data directory
  (`<data dir>/Built-in Extensions`). Medusa 0.1.0 loaded uBOL straight from the bundle: its first launch wrote the six
  indexes into the bundle, and from a read-only bundle nothing was blocked at all. Its successor, full uBlock Origin
  (MV2), has no DNR rulesets, and Chrome writes nothing into its folder, so it loads straight from the signed bundle
  (`Contents/Resources/Extensions/ublock`); a copy in the data dir was code any same-user process could edit. The
  first launch of a build that loads it from the bundle deletes the old `Built-in Extensions` folder.

Everything else Chrome writes (component updater, caches, extension installs) goes to the user data dir, and
`MacAppCodeSignClone` is disabled (`MedusaCoreHost.mm`). `scripts/release.sh` launches the exported app once and verifies
the signature again, so a new writer fails the release.

## MedusaCore's layer: `//medusa/core`

MedusaCore (`docs/medusacore-spike.md`) is our own layer over Chrome. `engine/medusacore/apply.sh` copies `engine/medusacore/src` to
`//medusa/core` and adds its hooks: in files only Chrome's framework compiles (`chrome/BUILD.gn`'s macOS
`chrome_dll`, `chrome/app/chrome_main.cc`), H1–H6 ([above](#our-hooks-in-chromes-code)), and a few `CHECK`s made
tolerant of a Browser without a `BrowserView` (`read_anything_side_panel_controller.cc`, `sad_tab_controller.cc`…).
Run `apply.sh` again after anything that resets these files (steps 1–4). Each hook is one `hook "$src/<file>"` block that
names its own markers, lines only that edit writes: `apply.sh` skips a block whose markers are all in the file, refuses one
that is partly there, and `apply.sh --check` runs every block and names each hook whose markers or header include are
missing. `series.py check` doesn't replace it: it runs `apply.sh` itself, so a hook skipped in the tree is skipped in its
copy too. Changing or removing a hook means restoring its file from the series (`series.py check --keep <dir>` writes
the expected files) before `apply.sh` runs again.

## Our own code in the tree: `chrome/browser/medusa`

New engine code is plain Chromium code in new files. It lives in
`//chrome/browser/medusa`, calls Chrome's services directly (`PasswordStoreInterface`, `PersonalDataManager`,
`ExtensionRegistrar`, `HostZoomMap`, `TemplateURLService`, `HistoryService`…) and is exported as plain C from Chrome's
framework.

- **Where it lives.** `engine/chromium/src` mirrors `chromium/src`; `engine/chromium/apply.sh` copies it in
  (`--check` reports drift). This is MedusaCore's convention too (`engine/medusacore/src` → `//medusa/core`). Edit the
  repo copy only; `apply.sh` replaces the tree's.
- **Chromium's files we replace.** A file under `engine/chromium/src` outside `chrome/browser/medusa` replaces
  Chromium's at the same path (`apply.sh --paths` lists them; `series.py` counts each as the layer's). Only Chromium's
  logo, by Medusa's (`docs/brand/medusa/build.py` writes them): binary files a patch can't carry.
- **How it links.** One `source_set("medusa")` in `chrome/browser/medusa/BUILD.gn`: add your
  `ac_<domain>.{h,cc}` to its sources (sorted) and its deps.
  `chromium-medusa-layer.patch` links it into the macOS `//chrome:chrome_dll` (MedusaCore's framework), through the
  `:exports` group that exports `_ac_*`.
- **The C surface.** `public/ac_engine.h` is plain C with the rules: exports are `ac_<domain>_<verb>`, all with one
  signature `void (const char* profile_dir, const char* args_json, ac_engine_reply_t reply, void* context)`; JSON
  object in, JSON object out (`{"error": …}` on failure); UI thread only; the reply runs once, maybe before the
  call returns. Events go to one sink (`ac_engine_set_event_sink`) as `("<domain>.<what>", {profile, …})`.
  `ac_engine.h` has the C++ side (`AC_ENGINE_CALL`, `medusa::Call`, `Reply`, `Emit`).
- **The app** includes `public/ac_engine.h` from the repo and looks each export up with `dlsym` on the engine
  framework (`packages/medusacore/ios/MedusaCoreEngineBridge.mm`). A missing export aborts: the app bundles an engine it wasn't built
  for. Add each new call to `docs/medusacore-parity.md`.

## The patch series

`engine/patches/series` is the one place that says what goes into the tree and in what order: `chromium <patch>`
lines (after ungoogled-chromium and domain substitution, step 4), then `layer <dir>` lines (our own files,
`<dir>/apply.sh`). Each patch is made against the tree as every line above it leaves it, and covers one concern, named
for it. A new patch goes where it belongs in the file; names no longer carry the order.

`engine/patches/series.py` does everything with it:

- `apply [--phase chromium]`: applies the series to the tree, skipping what is applied (step 4 runs it, through
  `apply-chromium-patches.sh`).
- `capture-base`: records every file the series touches as it is before the series (the base). Step 4 runs it
  just before it applies the series, so a fresh or rebased checkout records its own; `01-sync.sh` clears the old
  one. It lives in `~/chromium-build/series-base` (`AC_SERIES_BASE`).
- `check`: copies the base to a scratch directory, applies the whole series there strictly (`git apply`: exact
  context, no fuzz; each layer's `apply.sh` with `CHROMIUM_SRC` pointed at the scratch copy) and compares every
  touched file with the tree, byte for byte. Exit 0 means the series reproduces the engine we build; otherwise it
  lists each step that no longer applies and each file the series doesn't reproduce (an edit made in the tree but
  not in a patch, or the reverse), and keeps the scratch copy for `diff -u`. It writes nothing else and needs no
  lock.
- A file the series starts touching later (a new hook) needs its base too: run `capture-base` before the hook
  first goes into the tree. On an applied tree that's safe: it only records files the base lacks, never one a patch
  creates. `apply` dry-runs each patch first and refuses one that is partly in already, instead of applying its other
  hunks twice. Until then `check` takes the checkout's git HEAD for it and says so, which is right only when nothing
  upstream changes that file.
- `materialize --until <patch> <dir>`: the touched files as the series leaves them after one line. To remake a
  patch, materialize the line above it, edit a copy, and diff.
- `files`: what each line touches.

Run `check` after any patch change, before committing it. For a nightly run on this machine (a local launchd job;
nothing remote is set up), point a LaunchAgent at it, for example `~/Library/LaunchAgents/com.medusa.series-check.plist`
with `ProgramArguments` `/usr/bin/python3`, `<repo>/engine/patches/series.py`, `check`, a
`StartCalendarInterval` of 03:00 and `StandardOutPath` `~/chromium-build/logs/series-check.log`. A CI machine
needs only the repo plus a copy of the base and the tree's touched files: `CHROMIUM_SRC` and `AC_SERIES_BASE` say
where they are.

## Rebuilding

Everything lives outside the repo in `~/chromium-build`, which carries `.metadata_never_index`.
The step scripts are copied in `engine/patches/build/`, and each expects `~/chromium-build`. Run them under the
chromium lock (`scripts/agent/locked chromium`), in the order 1, 3, 4, 2, 5 on a fresh checkout (`gn gen` once the
tree is patched).

| Step | Script | Time (M5 Pro, shared machine) |
|---|---|---|
| 1. Fetch Chromium's tag (`CHROMIUM_VERSION` in `env.sh`) at depth 1 and check it out, then `gclient sync --no-history` of its deps for the Mac with the PGO profiles (`checkout_pgo_profiles`), then its hooks; clears the series base | `01-sync.sh` | ~40 min, 30 GB (deps alone, re-cloned: 7 min) |
| 2. Write `out/Release_GN_arm64/args.gn` from `gn_defines.sh`, then `gn gen` | `02-gn-args.sh` | ~1 min |
| 3. ungoogled-chromium's series, with the exceptions below | `03-ungoogled.py` | 2 min |
| 4. Domain substitution, minus the store files (`domsub-keep-store.txt`), then our series: `apply-chromium-patches.sh` (`series.py capture-base` and `apply --phase chromium`, then the layers `engine/chromium/apply.sh` and `engine/medusacore/apply.sh`) | `04-domain-substitution.sh` | 5 min |
| 5. Regenerate the offline page (`game-resource.sh`), compile `chrome_framework` (MedusaCore; the app's build stages it from `out/Release_GN_arm64`) | `05-build.sh` | first build 2.5 h (official, ThinLTO, PGO; 2026-10-18); incremental: the compile, then a ThinLTO relink of the framework, about 7 min (its cache, `thinlto-cache`, keeps that short) |

Disk: about 45 GB in total. That's 40 GB for the checkout with its 13 GB out dir, the PGO profiles (170 MB) and
0.2 GB for the domain-substitution cache.

Rules for editing the tree after the first build:

- **GN args** live in `gn_defines.sh`, the complete list (the args CEF's `gn_args.py` used to merge in are there
  too): an official build (`is_official_build=true`, which turns on ThinLTO and stripping) with PGO
  (`chrome_pgo_phase=2`, the profile `chrome/build/mac-arm.pgo.txt` names), no DCHECKs, no symbols, proprietary
  codecs, Widevine (DRM still needs Google's VMP signing), Medusa branding, and ungoogled's and Helium's `flags.gn`
  minus the exceptions below. Official builds don't allow `chrome_enable_logging_by_default`, so Chrome writes no
  `chrome_debug.log` unless it's started with `--enable-logging` (a test instance:
  `MEDUSA_CHROMIUM_SWITCHES=--enable-logging`).
  After changing them, run step 2 again.
- **Moving to a new Chromium version.** It deletes `out/` and costs a full build (official, ThinLTO, PGO), so it
  needs the owner's OK.
  1. Domain substitution doesn't need reverting: its cache never matches a tree our series has patched (the revert
     fails on the hashes). Set `domsubcache.tar.gz` aside instead, and reset every repo of the checkout to its
     commit (`git reset --hard` and `git clean -ffd` in `src` and through `gclient recurse`). `01-sync.sh` runs
     `gclient sync --reset --force -D` too.
  2. Set `CHROMIUM_VERSION`, `UNGOOGLED_TAG` and `UNGOOGLED_MACOS_TAG` in `env.sh` (ungoogled's lists are made
     for exactly one Chromium version) and check those tags out in `~/chromium-build/ungoogled{,-macos}`. The macOS
     repo is often a few patch releases behind; its tag for the same milestone is fine, since only
     `fix-disabling-safebrowsing.patch` comes from it.
  3. Delete `out/`, re-run `01-sync.sh`, then steps 3, 4, 2 and 5.
  4. `src` is an unmanaged, shallow solution. gclient never moves it to a new tag, and a plain `git fetch` of it
     (or of a shallow dep) asks for the whole history of every branch: the server builds that pack for an hour
     without sending a byte. So `01-sync.sh` fetches the tag itself at depth 1. If deps stall the same way
     (`STALL DETECTED`, `git fetch --prune --no-tags origin` at 0 % CPU), delete the dep checkouts listed in
     `.gclient_entries` and sync again: gclient clones them fresh at depth 1.
  5. Our patches and the hooks may need their context refreshed; `series.py check` and `apply.sh --check` say
     which. A patch whose file moved is rewritten for the new path, and the new path's file goes into the series
     base (`series-base/`) as steps 3 and 4 left it.

## ungoogled-chromium

The patch set comes from the 155.0.8059.84-1 series plus the macOS repo's (155.0.8059.39-1.1)
`fix-disabling-safebrowsing.patch` (`UNGOOGLED_TAG`, `UNGOOGLED_MACOS_TAG` in `env.sh`). The full list with reasons
is `engine/patches/ungoogled-status.tsv`; the exceptions are `03-ungoogled.py`'s. `disable-gcm` now applies in full
(CEF's own GCM stub went with CEF). The other exceptions first made for CEF are kept as the CEF-era build had them:
a behaviour decision for later, no longer a build need.

**Partial:**

- `0021-disable-rlz`: `rlz/buildflags/buildflags.gni` is left out, so `enable_rlz` stays true (CEF required it).
  RLZ stays inert: there's no brand code, and its host is substituted.
- `add-flag-to-show-avatar-button` and `add-flag-for-incognito-themes`: their hunks in Chrome's toolbar and frame are
  left out (they conflicted with CEF's patches there); MedusaCore never shows either.
- `0005-disable-default-extensions`: its WebstoreInstaller stubs are dropped.
- `0006-modify-default-prefs`: saving passwords and autofilling addresses and cards stay on, because
  Chrome's password manager and autofill are used (locally). Autosign-in stays off.
- `block-requests`: its early `return` in `UpdateCheckerImpl::CheckForUpdates` is undone
  (`chromium-extension-updates.patch`), so Web Store extensions auto-update. The component updater's
  hosts stay unreachable through domain substitution.

**Safe Browsing is compiled out** (`safe_browsing_mode=0`, as in ungoogled and Helium, since 155): its lists could
never update through domain substitution, yet every navigation and download still went through its checks. So
`0001-fix-building-without-safebrowsing`, `fix-building-without-safebrowsing` (with fuzz 3, `FUZZ` in
`03-ungoogled.py`: one `chrome/test/BUILD.gn` hunk sits next to the skipped pruning fix), `remove-unused-preferences-fields`,
`move-js-optimizer-unfamiliar-sites` and the macOS `fix-disabling-safebrowsing` apply now. A patch applied with fuzz is
checked as soon as it applies (`misplaced_hunks`): every hunk's result, its context and added lines, must be in its
file, and the hunks fuzz is known to move (`FUZZED_HUNKS`, the `chrome/test/BUILD.gn` one) must pass their own
present/absent checks instead; anything else fails step 3, so a hunk fuzz put in the wrong place on a Chromium bump
is caught there. `fix-building-without-safebrowsing` also cuts the extension kill switch (Omaha attributes);
`chromium-extension-omaha-attributes.patch` puts it back.

**Not applied:** `fix-building-without-mdns-and-service-discovery`: mDNS and service discovery stay compiled in, since
the Cast dialog finds devices through them.

**Also not applied:**

- `enable-extra-locales`: not privacy-related (it broke CEF's string packs).
- `disable-webstore-urls`: the Web Store and extension updates are needed (user decision).
- `disable-download-quarantine`: Chrome quarantines every download itself (`com.apple.quarantine`, and
  `kMDItemWhereFroms` with its source URL) before it reports it complete, and turns a file macOS blocks into a failed
  download. Medusa used to apply the patch and quarantine finished files afterwards, from `chrome/browser/medusa`.
- `prefs-always-prompt-for-download-directory-by-defaul`: Chrome's default, save to the Downloads folder without
  asking, is Medusa's. Medusa used to apply the patch and then write "don't ask" into each profile.

**Skipped:**

- Pruning and its two fixes: a gclient checkout keeps its prebuilt toolchains.
- Two Linux-only patches.

**Other changes:**

- The ScreenAI sandbox fixup is gone: 155's ChromeContentBrowserClient no longer reaches ScreenAI code there.
- GN flags not used: `enable_mdns=false` and `enable_service_discovery=false` (the Cast dialog). `safe_browsing_mode=0`
  and `enable_reporting=false` are used.
- Domain substitution skips the Web Store and extension-updater sources (`domsub-keep-store.txt`),
  so chromewebstore.google.com, clients2.google.com and clients2.googleusercontent.com work.
  Everything else Google stays substituted. That includes the component updater (the Widevine CDM
  download), spell-check dictionaries, Safe Browsing list updates and the CWS info service.
- A `--log-net-log` capture of an app session showed no Google hosts. The only attempt was Safe
  Browsing's update to a substituted, blocked host.

## Helium

[Helium](https://github.com/imputnet/helium-chromium) (0.19.4, also on 155.0.8059.84, ungoogled-based) was the model for
the 155 upgrade. What we took and what we left, with the reason for each. Helium's patches are GPL-3.0, so none is
copied in: the ones adopted are one-line default changes, made again here.

**GN args** (its `flags.gn` and `helium-macos`'s `flags.macos.gn` and `devutils/shared.sh` release mode):

- Adopted: `is_official_build=true` (ThinLTO, stripping, official optimisation levels) and `chrome_pgo_phase=2` with
  `checkout_pgo_profiles` (Chromium's own PGO profile, as Chrome's release builds use), `safe_browsing_mode=0` and
  `enable_reporting=false`.
- Kept as ours: `symbol_level=0` (Helium has 1, for its crash reporter; we have none), the codecs, Widevine with its
  CDM storage id, branding.
- Not adopted: `enable_mdns=false` and `enable_service_discovery=false` (the Cast dialog), `use_siso`/`cc_wrapper`
  (Helium's own build cache), `enable_sparkle` (the app has its own updater).

**Patches adopted:**

- `disable-history-clusters`, `disable-ad-topics-and-etc`, `disable-live-caption-completely`,
  `disable-outdated-build-detector`: background work off by default (`chromium-background-features-off.patch`).
- `fix-building-without-safebrowsing`: the download file types protobuf with `safe_browsing_mode=0`
  (`chromium-safe-browsing-off-file-types.patch`).

**Patches not adopted:**

- `infinite-tab-freezing`: already on, from the app's command line (`InfiniteTabsFreezing`, with its
  `MEDUSA_TAB_FREEZING=off` kill switch).
- `memory-saving-by-default`: Medusa sleeps tabs by its own policy (`lib/tabLifecycle`, after Dia); Chrome's Memory
  Saver would discard tabs on a schedule of its own.
- `lazy-session-restore`: MedusaCore restores its own session; Chrome's session restore is off for its Browsers
  (`should_trigger_session_restore=false`).
- `prioritize-platform-policy-loading`: MedusaCore makes no platform policy provider (`CreatePlatformProvider` returns
  null).
- `remove-unused-ai-resources`: the AI component extensions it stops loading (glic, contextual tasks) are already
  off in a Chromium build (feature-gated, Google-branded only), so it only saves pak space.
- `add-low-power-framerate-flag`: only a flag; Energy Saver's 30 fps default doesn't change.
- `upstream-fixes/missing-dependencies` and `tab-restore-live-tabs`: already in 155.0.8059.84.
- `fix-instance-id-stuck`: GCM is off (ungoogled's `disable-gcm`).
- Everything under `helium/ui`, `helium/settings` and `helium/macos` (UI, settings pages, branding, Sparkle,
  keychain names, menus), the search, sync, importer, uBlock-as-component, fingerprinting-noise, network-flag and
  onboarding patches: UI, product features or privacy choices, not speed. AI patches: no AI features.

## Tab capture

A page that calls
`getUserMedia({video: {mandatory: {chromeMediaSource: "desktop", chromeMediaSourceId: id}}})`
captures the tab behind `id`; Chromium's `DesktopMediaID::Parse` already understands the id. Asking
for `audio: {mandatory: {chromeMediaSource: "desktop"}}` gets that tab's audio instead of system
audio. Capturing reads Chromium's own compositor frames, so macOS asks for no Screen Recording
permission.

In the app:

- The WebView method `mediaCaptureSourceId()` returns the id.
- The share picker answers a `displayMediaRequest` with that id, and the page script adds tab audio
  when the page asked for audio.
- The answer lets one getUserMedia request of the asking frame, within 15 s, capture exactly the picked
  source (`ac_desktop_capture.mm`), with desktop audio only for a tab the page asked audio of.
  Anything else is refused: the page script runs in the page's world, so the page decides what
  getUserMedia asks for.
- Desktop getUserMedia without a picked source is refused outright, with no prompt (as in Chrome, where
  only `getDisplayMedia` and its picker capture the screen). Only camera and microphone get a permission
  prompt.

Verified in the app: a "Tab" track at 1558×1080 delivering frames, plus a "Tab Audio" track.

## CEF's 117 patches

What became of each patch in CEF 154's `patch/patches` (branch 8037) when CEF left the tree. "Dropped" means
MedusaCore doesn't need it: it serves a platform we don't ship, off-screen rendering (OSR), CEF's Alloy runtime, CEF's
own API, Views or build, or crash upload.

| Patch | Now |
|---|---|
| `angle_commit_config` | dropped (CEF source tarballs) |
| `base_command_line_1872` | dropped (CEF API: lower-case switch names) |
| `base_logging_3951` | dropped (Windows bootstrap) |
| `base_rand_util_lazy_seed` | dropped (Windows DCHECK builds) |
| `base_test_4396276` | dropped (CEF's test binaries) |
| `base_thread_pool_5548577` | dropped (CEF's multi-threaded message loop; Windows/Linux only) |
| `blink_ax_viewport_collapse` | dropped (CEF API: accessibility tree collapse) |
| `blink_web_element_4200240` | dropped (CEF API) |
| `blink_window_size_3714` | dropped (CEF's Document PiP options) |
| `browser_scheduler` | dropped (multi-threaded message loop shutdown) |
| `browser_security_policy_1081397` | dropped (CEF's custom schemes) |
| `chrome_autofill_bubble_3796` | folded (`chromium-autofill-address-bubble-window`) |
| `chrome_browser` | dropped (CEF build) |
| `chrome_browser_browser` | hook (H1, H2); folded (`chromium-cef-carryover`: `DeleteBrowser` order, the tab strip API's colour provider without an active tab; its `browser_ui_controller` guard against a tab that loads before it's in the strip, kept as `chromium-ui-update-before-insert` until 2026-10-15, dropped with it); rest dropped |
| `chrome_browser_content_settings` | dropped (a `NOTREACHED` only CEF's tests hit) |
| `chrome_browser_context_menus` | dropped (H4 is `ACContextMenu::Show()`) |
| `chrome_browser_devtools_osr` | dropped (OSR) |
| `chrome_browser_dialogs_jsmodal` | dropped (Alloy, OSR) |
| `chrome_browser_dialogs_misc` | dropped (OSR; CEF's toolbar-less extension dialog anchor) |
| `chrome_browser_dialogs_native` | dropped (CEF API: file dialog interception) |
| `chrome_browser_dialogs_widget` | dropped (OSR dialog parents, CEF Views) |
| `chrome_browser_download` | dropped (CEF API: download delegate) |
| `chrome_browser_extensions` | dropped (Alloy tabs API, CEF's PDF viewer delegate) |
| `chrome_browser_extensions_background` | folded (`chromium-cef-carryover`: `gn gen` asserts without it, given `enable_background_mode=false`) |
| `chrome_browser_frame_mac` | dropped (CEF Views) |
| `chrome_browser_metrics_tpm_476896967` | dropped (a Windows TPM driver crash) |
| `chrome_browser_permission_prompt` | hook (H3) |
| `chrome_browser_policy` | dropped (CEF API: policy configuration) |
| `chrome_browser_printing_oop_osr` | dropped (OSR) |
| `chrome_browser_privacy_1119417` | dropped (CEF build; Windows/Linux) |
| `chrome_browser_profile_menu` | dropped (Chrome's profile menu, which MedusaCore never shows) |
| `chrome_browser_profiles` | dropped (CEF's incognito request contexts) |
| `chrome_browser_safe_browsing` | dropped (component build) |
| `chrome_browser_startup` | dropped (CEF API: process singleton) |
| `chrome_browser_task_manager` | dropped (multi-threaded message loop shutdown) |
| `chrome_browser_views_dangling_rawptr` | dropped (Chrome's toolbar, which MedusaCore never shows) |
| `chrome_browser_webui_license` | dropped (CEF's chrome://license) |
| `chrome_browser_webui_version` | dropped (CEF's chrome://version) |
| `chrome_common_logging` | dropped (CEF build: logging on in Release) |
| `chrome_plugins` | dropped (CEF API) |
| `chrome_renderer` | dropped (CEF build) |
| `chrome_renderer_print_preview` | dropped (CEF API: per-frame print preview) |
| `chrome_runtime` | hook (H5, H6); its `ConfigureNetworkContextParams` `bool` return and `CleanupOnUIThread` dropped |
| `chrome_runtime_views` | dropped (CEF Views) |
| `color_provider_manager_3610` | dropped (CEF Views) |
| `component_build` | dropped (component build) |
| `component_updater_4087` | dropped (CEF API: component updater) |
| `components_gcm_disable` | dropped (ungoogled's `disable-gcm` now applies in full) |
| `config_3892` | dropped (CEF API: preferences and variations) |
| `content_2015` | dropped (MedusaCore's `ConfigureNetworkContextParams` is `void` again) |
| `content_main_654986` | dropped (CEF's split `ContentMain`; MedusaCore starts through `ChromeMain`) |
| `content_throttle_registry` | dropped (CEF API) |
| `crashpad_1995` | dropped (CEF's crash reporting; crashpad stays off) |
| `crashpad_tp_1995` | dropped (crash upload) |
| `dawn_dxil_redist` | dropped (Windows) |
| `devtools_ai_assistance_skills` | dropped (CEF build: DevTools' AI assistance bundle) |
| `embedder_product_override` | dropped (CEF API: User-Agent product) |
| `gn_config` | dropped (CEF build) |
| `gritsettings` | dropped (CEF build) |
| `libxml_visibility` | dropped (CEF build) |
| `light_mode_3534` | dropped (CEF's force-light/dark mode switches) |
| `linux_assets_path_1936` | dropped (Linux) |
| `linux_atk_1123214` | dropped (Linux) |
| `linux_chrome_widevine_3149` | dropped (Linux) |
| `linux_glib_deprecated_volatile` | dropped (Linux) |
| `linux_gtk_theme_3610` | dropped (Linux) |
| `linux_gwp_asan_3803` | dropped (Linux) |
| `linux_printing_context` | dropped (Linux) |
| `mac_chrome_locale_3623` | folded (`chromium-cef-carryover`: only `LoadLocalState`'s ResourceBundle delegate, for H5); its Mac UI locale from Local State dropped (Chrome's own on the Mac: Cocoa's, `en-US` for Medusa's bundle either way) |
| `mac_event_observer_2539` | dropped (CEF's own `NSApplication`; MedusaCore runs Chrome's) |
| `mac_fling_scheduler_2540` | dropped (OSR) |
| `mac_keyboard_conversion_1467329` | folded (`chromium-cef-carryover`) |
| `mac_platform_style_bubble_893292` | folded (`chromium-cef-carryover`: `kAdjustBubbleIfOffscreen`); its `profile_menu_view_base.cc` hunk dropped (Chrome's profile menu, which MedusaCore never shows) |
| `mac_print_preview_modal` | folded (`chromium-cef-carryover`: child-modal resize and focus); its Save as PDF file dialog policy dropped (`PdfPrinterHandler::SelectFile` already checks it) |
| `mac_render_widget_3680` | dropped (CEF Views: `acceptsFirstMouse`) |
| `message_loop` | dropped (Windows; multi-threaded message loop) |
| `metrics_system_profile` | dropped (multi-threaded message loop) |
| `mime_handler_view_guest_1565_2727` | dropped (OSR) |
| `mojo_connect_result_3664` | dropped (CEF API) |
| `net_cookie_flags` | dropped (CEF API: per-request cookies) |
| `net_test_server_3798752` | dropped (tests) |
| `net_url_request_3596` | dropped (CEF's custom schemes) |
| `osr_fling_2745` | dropped (OSR) |
| `osr_win_remove_keyed_mutex_2575` | dropped (Windows OSR) |
| `printing_context_2196` | dropped (Linux) |
| `raw_ptr_3239` | dropped (CEF's directory listing) |
| `renderer_host_1070713` | dropped (CEF API: background colour) |
| `renderer_host_aura` | dropped (Aura: Windows/Linux) |
| `resource_bundle_2512` | dropped (CEF's threading) |
| `rfh_navigation_4829483` | dropped (CEF's custom schemes and window callback) |
| `runhooks` | dropped (Windows toolchain) |
| `screen_1443650` | dropped (`Screen::*RectInWindow` has only Aura and Windows callers) |
| `services_network_2622` | dropped (CEF API: cookieable schemes) |
| `services_network_2718` | dropped (the `bool` `ConfigureNetworkContextParams`) |
| `set_resize_background_color` | dropped (CEF Views) |
| `tarball_deps` | dropped (CEF source tarballs) |
| `tarball_gclient` | dropped (CEF source tarballs) |
| `trace_event` | dropped (CEF's trace categories) |
| `ui_base_x11_util` | dropped (Linux) |
| `ui_dragdrop_355390` | dropped (Linux) |
| `ui_menu_model_3577` | dropped (CEF menus) |
| `ui_views_widget_type` | dropped (CEF Views; Linux) |
| `v8_build` | dropped (CEF build) |
| `views_1749_2102_3330` | dropped (CEF Views and menus) |
| `views_textfield_5399416` | dropped (CEF Views) |
| `views_widget` | dropped (CEF Views: external parents; mostly Windows/Linux) |
| `viz_capture_3826` | dropped (OSR) |
| `viz_osr_2575` | dropped (OSR) |
| `web_contents_1257_1565` | dropped (OSR, CEF API) |
| `webkit_move_pip` | dropped (CEF's Document PiP options) |
| `webkit_plugin_info_2015` | dropped (CEF API) |
| `win_app_icon_3606` | dropped (Windows) |
| `win_ax_platform_node` | dropped (Windows) |
| `win_sandbox_3210` | dropped (Windows) |
| `win_shell_dialogs_3294` | dropped (Windows) |
| `win_taskbar_decorator_3645` | dropped (Windows) |
| `win_taskbar_group_3641` | dropped (Windows) |

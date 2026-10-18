import { useRef } from "react";
import { FadeLabel } from "@medusa/shell";
import { Pressable, StyleSheet, View, type ViewStyle } from "react-native";
import { layout, useTheme } from "../../lib/theme";
import { useBrowser } from "../../store/browser";
import { useActiveTabId, useTabLive, useWindowId } from "../../store/hooks";
import { usePageProgress } from "../../store/pageProgress";
import { splitOf } from "../../store/splits";
import { extensionsFitting, ToolbarExtensions, useToolbarExtensionsWidth } from "../extensions/ToolbarExtensions";
import { useHistoryAvailability } from "../layout/history";
import { toolbarPalette, type ToolbarPalette } from "../layout/toolbarColors";
import { ToolbarButton, type ButtonHit } from "../layout/controls";
import { addressBarInSidebar, setUrlAnchor, SIDEBAR_FIELD } from "../layout/windowLayout";
import { focusHeroBar } from "../omnibox/barState";
import { GlassFill, liquidGlass } from "../glass";
import { useHover } from "../primitives";
import { GLYPH, HistoryButton, ReloadButton, UrlField, useToolbarTab } from "../Toolbar";
import { HEADER_TOOLS, navButtonsFitting, type HeaderButton } from "../layout/dockMotion";

const BUTTON = layout.toolbarButton;
const { toggleX: TOGGLE_X, edge: EDGE, lightsRight: LIGHTS_RIGHT } = HEADER_TOOLS;
const LIGHTS_Y = 26.75;
const HIT_TOP = 0;
const HIT_BOTTOM = SIDEBAR_FIELD.top - 2;

type Slot = { center: number; left: number; right: number };
function slots(centers: number[], width: number): Slot[] {
  return centers.map((center, i) => ({
    center,
    left: i ? (centers[i - 1]! + center) / 2 : LIGHTS_RIGHT + 1,
    right: i < centers.length - 1 ? (center + centers[i + 1]!) / 2 : width - 2,
  }));
}

export function SidebarHeaderTools({ width }: { width: number }) {
  const windowId = useWindowId();
  const tab = useToolbarTab(useActiveTabId());
  const palette = toolbarPalette(useTheme(), null);
  const { buttons, step } = navButtonsFitting(width, BUTTON);
  const shown = tab ? buttons : [];
  const last = width - EDGE - BUTTON / 2;
  const at = slots([TOGGLE_X, ...shown.map((_, i) => last - (shown.length - 1 - i) * step)], width);
  const place = (s: Slot) => ({
    style: { position: "absolute" as const, top: HIT_TOP, left: s.left },
    hit: { width: s.right - s.left, height: HIT_BOTTOM - HIT_TOP, plateX: s.center - BUTTON / 2 - s.left, plateY: LIGHTS_Y - BUTTON / 2 - HIT_TOP },
  });
  return (
    <>
      <ToolbarButton
        {...place(at[0]!)}
        palette={palette}
        icon="sidebar.left"
        size={GLYPH}
        onPress={() => useBrowser.getState().toggleSidebar(windowId)}
        tooltip="Auto-Hide Tabs (⌘S)"
      />
      {tab ? <NavigationButtons tab={tab} palette={palette} buttons={shown} slots={at.slice(1).map(place)} /> : null}
    </>
  );
}

const alreadyFocused = () => {};

function NavigationButtons({
  tab,
  palette,
  buttons,
  slots,
}: {
  tab: NonNullable<ReturnType<typeof useToolbarTab>>;
  palette: ToolbarPalette;
  buttons: HeaderButton[];
  slots: { style: ViewStyle; hit: ButtonHit }[];
}) {
  const loading = useTabLive(tab.id, (l) => l.isLoading);
  const history = useHistoryAvailability(tab.id);
  return (
    <>
      {buttons.map((b, i) =>
        b === "reload" ? (
          <ReloadButton key={b} {...slots[i]!} tab={tab} loading={loading} palette={palette} onFocus={alreadyFocused} />
        ) : (
          <HistoryButton
            key={b}
            {...slots[i]!}
            tabId={tab.id}
            windowId={tab.windowId}
            direction={b === "back" ? -1 : 1}
            disabled={b === "back" ? !history.back : !history.forward}
            palette={palette}
            onFocus={alreadyFocused}
          />
        ),
      )}
    </>
  );
}

export function SidebarAddressRow({ width }: { width: number }) {
  const windowId = useWindowId();
  const tab = useToolbarTab(useActiveTabId());
  const field = useRef<View>(null);
  const anchor = () =>
    field.current?.measureInWindow((x, y, width, height) => {
      if (width && addressBarInSidebar(useBrowser.getState(), windowId)) setUrlAnchor(windowId, { left: x, top: y, width, sidebar: { height } });
    });

  return (
    <View
      ref={field}
      onLayout={anchor}
      style={{ position: "absolute", left: layout.sidebarInset, right: layout.sidebarInset, top: SIDEBAR_FIELD.top, height: SIDEBAR_FIELD.height }}
    >
      {tab?.url ? <PageField tab={tab} windowId={windowId} width={width - 2 * layout.sidebarInset} /> : <EmptyField windowId={windowId} />}
    </View>
  );
}

const HOST_ROOM = 84;

function PageField({ tab, windowId, width }: { tab: NonNullable<ReturnType<typeof useToolbarTab>>; windowId: string; width: number }) {
  const palette = toolbarPalette(useTheme(), null);
  const loading = useTabLive(tab.id, (l) => l.isLoading);
  const loaded = usePageProgress(tab.id);
  const progress = loading ? loaded : null;
  const inSplit = useBrowser((s) => !!splitOf(s, tab.id));
  const limit = extensionsFitting(width - 10 - 3 - HOST_ROOM);
  const extensionsWidth = useToolbarExtensionsWidth(windowId, limit);
  return (
    <UrlField
      tab={tab}
      palette={palette}
      windowId={windowId}
      inSplit={inSplit}
      onFocus={alreadyFocused}
      sidebar={{
        height: SIDEBAR_FIELD.height,
        progress,
        accessory: extensionsWidth ? (
          <View style={{ width: extensionsWidth - 6, height: 28 }}>
            <ToolbarExtensions tabId={tab.id} windowId={windowId} palette={palette} top={0} right={0} limit={limit} />
          </View>
        ) : null,
      }}
    />
  );
}

function EmptyField({ windowId }: { windowId: string }) {
  const theme = useTheme();
  const { hovered, hoverProps } = useHover();
  const open = () => {
    if (!focusHeroBar(windowId)) useBrowser.getState().openPanel(windowId, "");
  };
  return (
    <View {...hoverProps}>
      <Pressable onPress={open}>
        <View
          style={{
            height: SIDEBAR_FIELD.height,
            borderRadius: SIDEBAR_FIELD.radius,
            borderWidth: StyleSheet.hairlineWidth * 2,
            borderColor: liquidGlass ? "transparent" : theme.pinnedRestingStroke,
            backgroundColor: liquidGlass ? undefined : hovered ? theme.tabHover : theme.pinnedResting,
            justifyContent: "center",
            paddingLeft: 10,
          }}
        >
          {liquidGlass ? <GlassFill radius={SIDEBAR_FIELD.radius} border={StyleSheet.hairlineWidth * 2} fill={hovered ? theme.tabHover : theme.pinnedResting} /> : null}
          <FadeLabel text="Search or enter address" fontSize={13} color={theme.placeholder} fadeWidth={14} style={{ height: 18, marginLeft: -2 }} />
        </View>
      </Pressable>
    </View>
  );
}

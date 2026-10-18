import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { test } from "node:test";

globalThis.__DEV__ = false;

const medusacore = new URL("../test-native-stub.mjs", import.meta.url).href;
const stubs = {
  "@medusa/medusacore": `export * from ${JSON.stringify(medusacore)};
    export const listTasks = async () => [];
    export const onSystemState = () => ({ remove() {} });
    export const systemState = async () => null;
    export const releaseProfile = async () => {};
    export const setBatterySaver = (mode) => globalThis.batterySaverReply(mode);`,
  "../components/layout/splitActions": "export const showToast = () => {};",
  "../components/settings/windows": "export const openSettings = () => {};",
  "../components/pages": "export const isInternalTab = (t) => !/^https?:/.test(t.url ?? '');",
};
registerHooks({
  resolve(specifier, context, next) {
    if (!context.parentURL?.endsWith("/lib/tabLifecycle.ts") || !(specifier in stubs)) return next(specifier, context);
    return { url: `data:text/javascript,${encodeURIComponent(stubs[specifier])}`, shortCircuit: true };
  },
});

const { useBrowser } = await import("../store/browser.ts");
const { webviews } = await import("./webviews.ts");
const lifecycle = await import("./tabLifecycle.ts");

const S = () => useBrowser.getState();

function fakePage() {
  const page = { dirty: false, evaluated: 0, discarded: 0, release: () => {} };
  page.handle = {
    evaluate: async () => (page.evaluated++, page.dirty),
    setFrozen: () => new Promise((resolve) => (page.release = resolve)),
    discard: async () => (page.discarded++, "discarded"),
  };
  return page;
}

test("a tab shown and typed in while it was being frozen doesn't sleep", async () => {
  S().hydrate({});
  const w = S().createWindow({ url: "https://a.com" });
  const a = S().windows[w].tabIds[0];
  const b = S().newTab(w, { url: "https://b.com", background: true });
  const page = fakePage();
  webviews.set(b, page.handle);
  lifecycle.useLifecycle.setState({ batterySaver: true });

  const freezing = lifecycle.freezeTab(b);
  await new Promise((resolve) => setTimeout(resolve, 0));
  S().activate(b);
  page.dirty = true;
  page.release();
  await freezing;
  S().activate(a);

  assert.equal(await lifecycle.sleepTab(b), false);
  assert.equal(page.evaluated, 1, "asks the page now");
  assert.equal(page.discarded, 0);
  webviews.delete(b);
});

test("a tab without unsaved input sleeps", async () => {
  S().hydrate({});
  const w = S().createWindow({ url: "https://a.com" });
  const b = S().newTab(w, { url: "https://b.com", background: true });
  const page = fakePage();
  webviews.set(b, page.handle);
  assert.equal(await lifecycle.sleepTab(b), true);
  assert.equal(page.discarded, 1);
  webviews.delete(b);
});

const STATE = { off: 0, belowThreshold: 1, on: 3 };

async function syncWith(on, reply) {
  lifecycle.useLifecycle.setState({ batterySaver: on });
  globalThis.batterySaverReply = reply;
  return lifecycle.syncChromeBatterySaver();
}

test("Chrome owns Battery Saver when its effective state is the one asked for", async () => {
  assert.equal(await syncWith(true, async (mode) => ({ state: STATE[mode], active: mode === "on" })), true);
  assert.equal(await syncWith(false, async (mode) => ({ state: STATE[mode], active: false })), true);
});

test("a policy that pins Chrome's battery saver keeps our sampler running", async () => {
  assert.equal(await syncWith(true, async () => ({ state: STATE.off, active: false })), false);
  assert.equal(await syncWith(false, async () => ({ state: STATE.belowThreshold, active: false })), false);
});

test("an engine without the call keeps our sampler running", async () => {
  assert.equal(await syncWith(true, async () => { throw new Error("not an engine call"); }), false);
});

test("an older reply landing last doesn't override the newer one", async () => {
  let releaseFirst;
  lifecycle.useLifecycle.setState({ batterySaver: true });
  globalThis.batterySaverReply = () => new Promise((resolve) => (releaseFirst = () => resolve({ state: STATE.on, active: true })));
  const first = lifecycle.syncChromeBatterySaver();
  const second = syncWith(true, async () => ({ state: STATE.off, active: false }));
  assert.equal(await second, false);
  releaseFirst();
  assert.equal(await first, false);
});

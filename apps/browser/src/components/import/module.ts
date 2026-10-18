import type * as ImportApi from "@medusa/import";

let api: typeof ImportApi | null | undefined;

export function importModule(): typeof ImportApi | null {
  if (api === undefined) {
    try {
      api = require("@medusa/import") as typeof ImportApi;
    } catch {
      api = null;
    }
  }
  return api;
}

import { fileURLToPath } from "node:url";

export const HERE = fileURLToPath(new URL(".", import.meta.url));
export const REPO = fileURLToPath(new URL("../../../../", import.meta.url));
export const SYMBOLS_DIR = `${REPO}apps/demo/src/shims/web/symbols/`;
export const SCRATCH = process.env.MEDUSA_ICONS_SCRATCH ?? "/tmp/medusa-icons";
export const NATIVE = `${SCRATCH}/native`;

import { updaterState } from "@medusa/shell";
import { afterFirstWindow } from "./afterFirstWindow";
import { refreshSwitches } from "./killSwitches";

export function startKillSwitches() {
  afterFirstWindow(() => {
    void updaterState().then(
      (state) => {
        if (state.available && state.configured && state.automaticChecks) void refreshSwitches();
      },
      () => {},
    );
  });
}

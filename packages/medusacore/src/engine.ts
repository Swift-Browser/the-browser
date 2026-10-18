import { Cef } from "./native";

export async function engineCall<T>(name: string, profile: string, args?: object): Promise<T> {
  const result = JSON.parse(await Cef.engineCall(name, profile, args ? JSON.stringify(args) : null)) as T | { error: string };
  if (result && typeof result === "object" && "error" in result) throw new Error(`${name}: ${result.error}`);
  return result as T;
}

export const onEngineEvent = (listener: (topic: string, payload: { profile: string } & Record<string, unknown>) => void) =>
  Cef.addListener("onEngineEvent", (e) => listener(e.topic, JSON.parse(e.payload)));

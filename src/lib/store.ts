import { invoke } from "@tauri-apps/api/core";

export type ReplyPosition = "bottom-right" | "bottom-left" | "bottom-center";

export interface Settings {
  provider: string;
  api_key: string;
  base_url: string;
  model: string;
  position: ReplyPosition;
  max_tokens: number;
  bg_opacity: number;
}

export const DEFAULT_SETTINGS: Settings = {
  provider: "openai",
  api_key: "",
  base_url: "https://api.openai.com/v1",
  model: "gpt-4o-mini",
  position: "bottom-right",
  max_tokens: 800,
  bg_opacity: 100,
};

export interface ProviderPreset {
  id: string;
  label: string;
  base_url: string;
  needsKey: boolean;
}

export const PROVIDERS: ProviderPreset[] = [
  {
    id: "gemini",
    label: "Gemini",
    base_url: "https://generativelanguage.googleapis.com",
    needsKey: true,
  },
  {
    id: "openai",
    label: "OpenAI",
    base_url: "https://api.openai.com/v1",
    needsKey: true,
  },
  {
    id: "anthropic",
    label: "Anthropic",
    base_url: "https://api.anthropic.com",
    needsKey: true,
  },
  {
    id: "openrouter",
    label: "OpenRouter",
    base_url: "https://openrouter.ai/api/v1",
    needsKey: true,
  },
  {
    id: "groq",
    label: "Groq",
    base_url: "https://api.groq.com/openai/v1",
    needsKey: true,
  },
  {
    id: "ollama",
    label: "Ollama",
    base_url: "http://localhost:11434",
    needsKey: false,
  },
  {
    id: "custom",
    label: "Custom",
    base_url: "",
    needsKey: true,
  },
];

export const inTauri =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

export interface InitialState {
  settings: Settings;
  thumb: string;
  view: string;
  shown: boolean;
  needs_key: boolean;
}

export async function getInitialState(): Promise<InitialState> {
  if (!inTauri) return { settings: { ...DEFAULT_SETTINGS }, thumb: "", view: "ask", shown: true, needs_key: true };
  try {
    return await invoke<InitialState>("get_initial_state");
  } catch {
    const s = await getSettings();
    const needs_key = s.provider !== "ollama" && !s.api_key.trim();
    return { settings: s, thumb: "", view: "ask", shown: false, needs_key };
  }
}

export async function getSettings(): Promise<Settings> {
  if (!inTauri) return { ...DEFAULT_SETTINGS };
  try {
    return await invoke<Settings>("get_settings");
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export async function saveSettings(s: Settings): Promise<void> {
  if (!inTauri) return;
  await invoke("save_settings", { settings: s });
}

export interface Turn {
  role: "user" | "assistant";
  text: string;
}

export async function askAi(prompt: string, history: Turn[]): Promise<void> {
  await invoke("ask_ai", { prompt, history });
}

export async function overlayHidden(): Promise<void> {
  if (!inTauri) return;
  await invoke("overlay_hidden");
}

export async function hideOverlay(): Promise<void> {
  if (!inTauri) return;
  await invoke("hide_overlay");
}

export async function quitApp(): Promise<void> {
  if (!inTauri) return;
  await invoke("quit_app");
}

export async function fetchModels(provider: string, baseUrl: string, apiKey: string): Promise<string[]> {
  if (!inTauri) {
    return ["gemini-2.5-flash", "gemini-2.0-flash", "gpt-4o", "claude-3-7-sonnet"];
  }
  return await invoke<string[]>("fetch_models", {
    provider,
    baseUrl,
    apiKey,
  });
}

export interface InteractiveRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export async function setInteractiveRegions(regions: InteractiveRect[]): Promise<void> {
  if (!inTauri) return;
  try {
    await invoke("set_interactive_regions", { regions });
  } catch (err) {
    console.error("set_interactive_regions error:", err);
  }
}



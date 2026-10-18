import { invoke } from "@tauri-apps/api/core";

export type ReplyPosition = "bottom-right" | "bottom-left" | "bottom-center";
export type ThemeMode = "auto" | "dark" | "light" | "qt";
export type SettingsSection = "model" | "appearance" | "updates";

export interface ProviderProfile {
  api_key: string;
  base_url: string;
  model: string;
}

export interface Settings {
  provider: string;
  /** Active-provider aliases, retained for compatibility with older settings files. */
  api_key: string;
  base_url: string;
  model: string;
  /** Each provider keeps its own credentials, endpoint, and selected model. */
  provider_profiles: Record<string, ProviderProfile>;
  position: ReplyPosition;
  max_tokens: number;
  bg_opacity: number;
  theme: ThemeMode;
}

const PROFILE_DEFAULTS: Record<string, ProviderProfile> = {
  gemini: {
    api_key: "",
    base_url: "https://generativelanguage.googleapis.com",
    model: "gemini-2.5-flash",
  },
  openai: { api_key: "", base_url: "https://api.openai.com/v1", model: "gpt-4o-mini" },
  anthropic: { api_key: "", base_url: "https://api.anthropic.com", model: "claude-3-5-haiku-latest" },
  openrouter: { api_key: "", base_url: "https://openrouter.ai/api/v1", model: "openai/gpt-4o-mini" },
  groq: { api_key: "", base_url: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile" },
  ollama: { api_key: "", base_url: "http://localhost:11434", model: "qwen2.5:7b" },
  custom: { api_key: "", base_url: "", model: "" },
};

function defaultProfiles(): Record<string, ProviderProfile> {
  return Object.fromEntries(Object.entries(PROFILE_DEFAULTS).map(([id, profile]) => [id, { ...profile }]));
}

export const DEFAULT_SETTINGS: Settings = {
  provider: "openai",
  api_key: "",
  base_url: PROFILE_DEFAULTS.openai.base_url,
  model: PROFILE_DEFAULTS.openai.model,
  provider_profiles: defaultProfiles(),
  position: "bottom-right",
  max_tokens: 800,
  bg_opacity: 100,
  theme: "auto",
};

/** Normalize settings received from an older install and migrate its active credentials into profiles. */
export function normalizeSettings(value?: Partial<Settings> | null): Settings {
  const raw = (value ?? {}) as Partial<Settings>;
  const provider = raw.provider || DEFAULT_SETTINGS.provider;
  const profiles = defaultProfiles();

  for (const [id, profile] of Object.entries(raw.provider_profiles ?? {})) {
    profiles[id] = { ...PROFILE_DEFAULTS[id], ...profile };
  }

  const existing = raw.provider_profiles?.[provider];
  const active: ProviderProfile = {
    ...(profiles[provider] ?? { api_key: "", base_url: "", model: "" }),
    ...(existing ?? {}),
  };
  // The flat values are the source of truth for the selected profile in legacy settings
  // and while the settings UI edits the active provider.
  if (Object.prototype.hasOwnProperty.call(raw, "api_key")) active.api_key = raw.api_key ?? "";
  if (Object.prototype.hasOwnProperty.call(raw, "base_url")) active.base_url = raw.base_url ?? "";
  if (Object.prototype.hasOwnProperty.call(raw, "model")) active.model = raw.model ?? "";
  profiles[provider] = active;

  return {
    ...DEFAULT_SETTINGS,
    ...raw,
    provider,
    api_key: active.api_key,
    base_url: active.base_url,
    model: active.model,
    provider_profiles: profiles,
    position: raw.position ?? DEFAULT_SETTINGS.position,
    max_tokens: raw.max_tokens ?? DEFAULT_SETTINGS.max_tokens,
    bg_opacity: raw.bg_opacity ?? DEFAULT_SETTINGS.bg_opacity,
    theme: raw.theme ?? DEFAULT_SETTINGS.theme,
  };
}

/** Save active aliases back to the selected provider before persisting. */
export function settingsForSave(value: Settings): Settings {
  const settings = normalizeSettings(value);
  const active = {
    api_key: settings.api_key,
    base_url: settings.base_url,
    model: settings.model,
  };
  return {
    ...settings,
    provider_profiles: { ...settings.provider_profiles, [settings.provider]: active },
  };
}

export function selectProvider(value: Settings, provider: string): Settings {
  const settings = settingsForSave(value);
  const profile = settings.provider_profiles[provider] ?? {
    api_key: "",
    base_url: "",
    model: "",
  };
  return {
    ...settings,
    provider,
    api_key: profile.api_key,
    base_url: profile.base_url,
    model: profile.model,
  };
}

export function updateProviderProfile(
  value: Settings,
  provider: string,
  patch: Partial<ProviderProfile>,
): Settings {
  const settings = settingsForSave(value);
  const nextProfile = {
    ...(settings.provider_profiles[provider] ?? { api_key: "", base_url: "", model: "" }),
    ...patch,
  };
  return {
    ...settings,
    ...(settings.provider === provider ? nextProfile : {}),
    provider_profiles: { ...settings.provider_profiles, [provider]: nextProfile },
  };
}

export interface ProviderPreset {
  id: string;
  label: string;
  base_url: string;
  needsKey: boolean;
}

export const PROVIDERS: ProviderPreset[] = [
  { id: "gemini", label: "Gemini", base_url: PROFILE_DEFAULTS.gemini.base_url, needsKey: true },
  { id: "openai", label: "OpenAI", base_url: PROFILE_DEFAULTS.openai.base_url, needsKey: true },
  { id: "anthropic", label: "Anthropic", base_url: PROFILE_DEFAULTS.anthropic.base_url, needsKey: true },
  { id: "openrouter", label: "OpenRouter", base_url: PROFILE_DEFAULTS.openrouter.base_url, needsKey: true },
  { id: "groq", label: "Groq", base_url: PROFILE_DEFAULTS.groq.base_url, needsKey: true },
  { id: "ollama", label: "Ollama", base_url: PROFILE_DEFAULTS.ollama.base_url, needsKey: false },
  { id: "custom", label: "Custom", base_url: "", needsKey: true },
];

export const inTauri =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

let interactiveSequence = 0;

export interface InitialState {
  settings: Settings;
  thumb: string;
  preview: string;
  background: string;
  view: string;
  shown: boolean;
  overlay_revision: number;
  input_sequence: number;
  needs_key: boolean;
}

export async function getInitialState(): Promise<InitialState> {
  if (!inTauri) {
    return {
      settings: normalizeSettings(DEFAULT_SETTINGS),
      thumb: "",
      preview: "",
      background: "",
      view: "ask",
      shown: true,
      overlay_revision: 0,
      input_sequence: 0,
      needs_key: true,
    };
  }
  try {
    const state = await invoke<InitialState>("get_initial_state");
    interactiveSequence = Math.max(interactiveSequence, state.input_sequence ?? 0);
    return { ...state, settings: normalizeSettings(state.settings) };
  } catch {
    const settings = await getSettings();
    const needs_key = settings.provider !== "ollama" && !settings.api_key.trim();
    return {
      settings,
      thumb: "",
      preview: "",
      background: "",
      view: "ask",
      shown: false,
      overlay_revision: 0,
      input_sequence: 0,
      needs_key,
    };
  }
}

export async function getSettings(): Promise<Settings> {
  if (!inTauri) return normalizeSettings(DEFAULT_SETTINGS);
  try {
    return normalizeSettings(await invoke<Settings>("get_settings"));
  } catch {
    return normalizeSettings(DEFAULT_SETTINGS);
  }
}

export async function saveSettings(settings: Settings): Promise<void> {
  if (!inTauri) return;
  await invoke("save_settings", { settings: settingsForSave(settings) });
}

export interface Turn {
  role: "user" | "assistant";
  text: string;
}

export async function askAi(prompt: string, history: Turn[]): Promise<void> {
  await invoke("ask_ai", { prompt, history });
}

/** Tells the backend the dismiss animation finished, so it can drop the keyboard and the input region. */
export async function overlayHidden(): Promise<void> {
  if (!inTauri) return;
  await invoke("overlay_hidden");
}

export async function quitApp(): Promise<void> {
  if (!inTauri) return;
  await invoke("quit_app");
}

export async function fetchModels(provider: string, baseUrl: string, apiKey: string): Promise<string[]> {
  if (!inTauri) {
    return ["gemini-2.5-flash", "gemini-2.0-flash", "gpt-4o", "claude-3-7-sonnet"];
  }
  return await invoke<string[]>("fetch_models", { provider, baseUrl, apiKey });
}

export interface FileSuggestion {
  path: string;
  name: string;
  is_dir: boolean;
}

export async function searchLocalFiles(query: string): Promise<FileSuggestion[]> {
  if (!inTauri) return [];
  return await invoke<FileSuggestion[]>("search_files", { query });
}

export interface ScreenRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** A capture: a small thumbnail for the input bar and a larger preview for hover. */
export interface Shot {
  thumb: string;
  preview: string;
}

export async function cropScreenshot(rect: ScreenRect, viewport: { width: number; height: number }): Promise<Shot> {
  if (!inTauri) return { thumb: "", preview: "" };
  return await invoke<Shot>("crop_screenshot", {
    ...rect,
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
    pixelRatio: window.devicePixelRatio || 1,
  });
}

export interface InteractiveRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export async function setInteractiveRegions(
  regions: InteractiveRect[],
  overlayRevision: number,
): Promise<void> {
  if (!inTauri) return;
  const sequence = ++interactiveSequence;
  try {
    await invoke("set_interactive_regions", { regions, overlayRevision, sequence });
  } catch (err) {
    console.error("set_interactive_regions error:", err);
  }
}

export interface UpdateStatus {
  current_version: string;
  current_sha: string;
  update_available: boolean;
  latest_sha: string;
  latest_message: string;
}

export async function checkForUpdates(): Promise<UpdateStatus> {
  if (!inTauri) {
    return {
      current_version: "v1.local",
      current_sha: "local",
      update_available: false,
      latest_sha: "local",
      latest_message: "",
    };
  }
  return await invoke<UpdateStatus>("check_for_updates");
}

/** Starts a background update. Progress arrives as `update-progress` events and the result as `update-done`. */
export async function updateFromSource(): Promise<string> {
  if (!inTauri) throw new Error("Source updates are available in the installed Linux app.");
  return await invoke<string>("update_from_source");
}

export async function updateFromPr(prNumber: number): Promise<string> {
  if (!inTauri) throw new Error("Pull request builds are available in the installed Linux app.");
  return await invoke<string>("update_from_pr", { prNumber });
}

export interface UpdateEvent {
  ok: boolean;
  message: string;
}

export async function openThemeConfig(): Promise<void> {
  if (!inTauri) return;
  await invoke("open_theme_config");
}

export async function restartApp(): Promise<void> {
  if (!inTauri) return;
  await invoke("restart_app");
}

export interface QtPalette {
  name: string | null;
  dark: boolean | null;
  window: string | null;
  window_text: string | null;
  base: string | null;
  text: string | null;
  alternate_base: string | null;
  button: string | null;
  button_text: string | null;
  highlight: string | null;
  highlighted_text: string | null;
  link: string | null;
  tooltip_base: string | null;
  tooltip_text: string | null;
}

/** Non-color knobs from ~/.config/screen-ai/theme.conf. `null` means "use the built-in default". */
export interface ThemeTokens {
  config_path: string;
  radius: number | null;
  inner_radius: number | null;
  control_radius: number | null;
  border_width: number | null;
  active_border: string | null;
  inactive_border: string | null;
  urgent_color: string | null;
  gap: number | null;
  font: string | null;
  mono: string | null;
  font_size: number | null;
  motion_reduced: boolean;
  speed: number;
  shadow: string | null;
}

export interface SystemTheme {
  dark: boolean;
  accent: string | null;
  palette: QtPalette | null;
  /** First layer that supplied colors: explicit, matugen, qt, gtk, or builtin. */
  source: string;
  tokens: ThemeTokens;
}

const FALLBACK_TOKENS: ThemeTokens = {
  config_path: "",
  radius: null,
  inner_radius: null,
  control_radius: null,
  border_width: null,
  active_border: null,
  inactive_border: null,
  urgent_color: null,
  gap: null,
  font: null,
  mono: null,
  font_size: null,
  motion_reduced: false,
  speed: 1,
  shadow: null,
};

export function fallbackSystemTheme(): SystemTheme {
  return { dark: true, accent: null, palette: null, source: "builtin", tokens: FALLBACK_TOKENS };
}

export async function getSystemTheme(): Promise<SystemTheme> {
  if (!inTauri) return fallbackSystemTheme();
  try {
    return await invoke<SystemTheme>("get_system_theme");
  } catch {
    return fallbackSystemTheme();
  }
}

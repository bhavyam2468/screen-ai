import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { listen } from "@tauri-apps/api/event";
import Dock, { Panel } from "./components/Dock";
import { MotionScaleProvider } from "./lib/motion";
import type { Msg } from "./components/ChatPanel";
import {
  DEFAULT_SETTINGS,
  PROVIDERS,
  Settings,
  SettingsSection,
  askAi,
  cropScreenshot,
  getInitialState,
  getSettings,
  inTauri,
  overlayHidden,
  quitApp,
  saveSettings,
  takeKeyboard,
  checkForUpdates,
  getSystemTheme,
  fallbackSystemTheme,
  openThemeConfig,
  restartApp,
  updateFromSource,
  UpdateEvent,
  normalizeSettings,
  selectProvider,
  settingsForSave,
  updateProviderProfile,
  SystemTheme,
  Shot,
  type ShotReady,
} from "./lib/store";

// Some "free" router models are safety classifiers and only ever say this.
const VERDICT = /^\s*(user\s+|content\s+)?safety\s*:?\s*(safe|unsafe)\b/i;

/** `--surface-*-rgb` variables the Qt bridge sets inline; the stylesheet owns them otherwise. */
const SURFACE_RGB_VARS = [
  "--surface-card-rgb",
  "--surface-sunken-rgb",
  "--surface-base-rgb",
  "--surface-raised-rgb",
  "--surface-raised-hi-rgb",
  "--surface-hover-window-rgb",
  "--surface-hover-base-rgb",
  "--surface-hover-raised-rgb",
  "--surface-code-rgb",
];

function colorToRgb(color: string | null | undefined): string | null {
  const match = color?.match(/^#?([0-9a-f]{6})$/i);
  if (!match) return null;
  const value = match[1];
  return `${parseInt(value.slice(0, 2), 16)}, ${parseInt(value.slice(2, 4), 16)}, ${parseInt(value.slice(4, 6), 16)}`;
}

function normalizeHex(color: string | null | undefined, fallback: string): string {
  return color && colorToRgb(color) ? (color.startsWith("#") ? color : `#${color}`) : fallback;
}

function mixHex(first: string, second: string, amount: number): string {
  const a = colorToRgb(first)?.split(",").map(Number);
  const b = colorToRgb(second)?.split(",").map(Number);
  if (!a || !b) return first;
  const mixed = a.map((channel, index) => Math.round(channel * (1 - amount) + b[index] * amount));
  return `#${mixed.map((channel) => channel.toString(16).padStart(2, "0")).join("")}`;
}

function rgba(color: string, alpha: number): string {
  return `rgba(${colorToRgb(color) ?? "0, 0, 0"}, ${alpha})`;
}

function contrastingText(color: string): string {
  const rgb = colorToRgb(color)?.split(",").map(Number);
  if (!rgb) return "#ffffff";
  const luminance = (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255;
  return luminance > 0.56 ? "#111827" : "#ffffff";
}

export default function App() {
  const [visible, setVisible] = useState(false);
  const [panel, setPanel] = useState<Panel>("none");
  const [settingsSection, setSettingsSection] = useState<SettingsSection>("model");
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [thumb, setThumb] = useState<string | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [modelQuery, setModelQuery] = useState("");
  const [desktopBackground, setDesktopBackground] = useState<string | null>(null);
  const [sessionRevision, setSessionRevision] = useState(0);
  const sessionRevisionRef = useRef<number | null>(null);
  const [snipping, setSnipping] = useState(false);
  const [commandNotice, setCommandNotice] = useState<string | null>(null);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [streaming, setStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasUpdate, setHasUpdate] = useState(false);
  const [sysTheme, setSysTheme] = useState<SystemTheme>(fallbackSystemTheme);

  useEffect(() => {
    getSystemTheme().then(setSysTheme).catch(() => {});
    checkForUpdates()
      .then((res) => {
        if (res.update_available) setHasUpdate(true);
      })
      .catch(() => {});
  }, []);

  const msgRef = useRef<Msg[]>([]);
  const settingsRef = useRef(settings);
  settingsRef.current = settings;
  const update = (fn: (m: Msg[]) => Msg[]) => {
    const next = fn(msgRef.current);
    msgRef.current = next;
    setMessages(next);
  };

  const afterSettings = (): Panel => (msgRef.current.length ? "chat" : "none");

  const summon = useCallback((p: {
    thumb?: string;
    preview?: string;
    background?: string;
    view?: string;
    overlay_revision?: number;
  }) => {
    const revision = p.overlay_revision ?? 0;
    if (sessionRevisionRef.current !== null && revision <= sessionRevisionRef.current) return;
    sessionRevisionRef.current = revision;
    getSettings().then((next) => {
      settingsRef.current = next;
      setSettings(next);
    });
    getSystemTheme().then(setSysTheme).catch(() => {});
    setThumb(p.thumb || null);
    setPreview(p.preview || null);
    setDesktopBackground(p.background || null);
    setSessionRevision(p.overlay_revision ?? 0);
    update(() => []);
    setError(null);
    setCommandNotice(null);
    setSnipping(false);
    setStreaming(false);
    if (p.view === "settings") {
      setSettingsSection("model");
      setPanel("settings");
    } else {
      setPanel("none");
    }
    setVisible(true);
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const init = await getInitialState();
        const normalized = normalizeSettings(init.settings);
        settingsRef.current = normalized;
        setSettings(normalized);
        if (init.shown) {
          summon({
            thumb: init.thumb,
            preview: init.preview,
            background: init.background,
            view: init.view,
            overlay_revision: init.overlay_revision,
          });
        }
      } catch {
        getSettings().then(setSettings);
      }
    })();

    if (!inTauri) {
      setVisible(true);
      return;
    }
    const unsubs: (() => void)[] = [];
    (async () => {
      unsubs.push(
        await listen<SystemTheme>("theme-changed", (e) => {
          setSysTheme(e.payload);
          // `[appearance]` in theme.conf also carries the panel's theme, position
          // and opacity, so an edit to the file has to refresh the settings — not
          // only the stylesheet variables — for the change to be live.
          void getSettings().then((next) => {
            settingsRef.current = next;
            setSettings(next);
          });
        })
      );
      // The card is raised as soon as the screen is captured; the thumbnail,
      // hover preview, and backdrop image follow a moment after.
      unsubs.push(
        await listen<ShotReady>("shot-ready", (e) => {
          if ((e.payload.overlay_revision ?? 0) !== (sessionRevisionRef.current ?? 0)) return;
          if (e.payload.thumb) setThumb(e.payload.thumb);
          if (e.payload.preview) setPreview(e.payload.preview);
          if (e.payload.background) setDesktopBackground(e.payload.background);
        })
      );
      unsubs.push(await listen<string>("update-progress", (e) => setCommandNotice(e.payload)));
      unsubs.push(
        await listen<UpdateEvent>("update-done", (e) => {
          if (!e.payload.ok) {
            setCommandNotice(e.payload.message);
            return;
          }
          // The build replaced the binary on disk, but this process is still the
          // old one. Restart into the new build instead of leaving "Update"
          // looking like it did nothing.
          setCommandNotice("Update installed — restarting Screen AI…");
          window.setTimeout(() => {
            void restartApp().catch(() =>
              setCommandNotice("Update installed. Quit and relaunch Screen AI to use it.")
            );
          }, 1200);
        })
      );
      unsubs.push(await listen<{
        thumb: string;
        preview: string;
        background: string;
        view: string;
        overlay_revision: number;
      }>("summon", (e) => summon(e.payload)));
      unsubs.push(await listen("request-hide", () => setVisible(false)));
      unsubs.push(await listen("show-settings", () => {
        setSettingsSection("model");
        setPanel("settings");
      }));
      unsubs.push(
        await listen<string>("ai-chunk", (e) =>
          update((m) => {
            if (!m.length || m[m.length - 1].role !== "assistant") return m;
            const copy = m.slice();
            const last = copy[copy.length - 1];
            copy[copy.length - 1] = { ...last, text: last.text + e.payload };
            return copy;
          })
        )
      );
      unsubs.push(
        await listen("ai-done", () => {
          setStreaming(false);
          const last = msgRef.current[msgRef.current.length - 1];
          if (last?.role === "assistant" && VERDICT.test(last.text)) {
            update((m) => m.slice(0, -1).concat({ role: "assistant", text: "" }));
            setError(
              `“${settingsRef.current.model}” is a safety classifier, not a chat model. Open settings and pick a different model.`
            );
          }
        })
      );
      unsubs.push(
        await listen<string>("ai-error", (e) => {
          setError(e.payload);
          setStreaming(false);
        })
      );
    })();
    return () => unsubs.forEach((u) => u());
  }, [summon]);

  const submit = useCallback(async (prompt: string, base?: Msg[]) => {
    const s = settingsRef.current;
    if (s.provider !== "ollama" && !s.api_key.trim()) {
      setSettingsSection("model");
      setPanel("settings");
      return;
    }
    const history = (base ?? msgRef.current).filter((m) => m.text);
    update(() => [...history, { role: "user", text: prompt }, { role: "assistant", text: "" }]);
    setPanel("chat");
    setError(null);
    setStreaming(true);

    if (!inTauri) {
      const demo =
        "Preview reply.\n\n| Key | Action |\n|---|---|\n| `Esc` | dismiss |\n| `Ctrl+,` | settings |";
      let i = 0;
      const t = setInterval(() => {
        i += 3;
        update((m) => m.slice(0, -1).concat({ role: "assistant", text: demo.slice(0, i) }));
        if (i >= demo.length) {
          clearInterval(t);
          setStreaming(false);
        }
      }, 14);
      return;
    }
    try {
      await askAi(prompt, history.map(({ role, text }) => ({ role, text })));
    } catch (err) {
      setError(String(err));
      setStreaming(false);
    }
  }, []);

  const retry = useCallback(() => {
    const m = msgRef.current;
    const lastUser = [...m].reverse().find((x) => x.role === "user");
    if (!lastUser) return;
    const idx = m.lastIndexOf(lastUser);
    submit(lastUser.text, m.slice(0, idx));
  }, [submit]);

  const persistFromCommand = async (nextValue: Settings) => {
    const next = settingsForSave(nextValue);
    settingsRef.current = next;
    setSettings(next);
    try {
      await saveSettings(next);
      setCommandNotice(null);
    } catch (err) {
      setCommandNotice(`Could not save: ${String(err)}`);
    }
    setPanel(afterSettings());
  };

  const save = useCallback(async (value: Settings) => {
    const next = settingsForSave(value);
    settingsRef.current = next;
    setSettings(next);
    try {
      await saveSettings(next);
      setCommandNotice(null);
      setPanel(afterSettings());
    } catch (err) {
      setCommandNotice(`Could not save settings: ${String(err)}`);
    }
  }, []);

  const openSettings = (section: SettingsSection = "model", query = "") => {
    setModelQuery(query);
    setSettingsSection(section);
    setPanel("settings");
  };

  const providerFor = (name: string) =>
    PROVIDERS.find((provider) => provider.id === name.toLowerCase() || provider.label.toLowerCase() === name.toLowerCase());

  const openConfigFile = useCallback(() => {
    openThemeConfig()
      .then(() => setCommandNotice("Opened theme.conf. Changes apply on save."))
      .catch((err) => setCommandNotice(String(err)));
  }, []);

  /**
   * Snipping covers the whole screen, so it must own the keyboard again: the
   * overlay hands the keyboard back whenever another window takes focus, and a
   * click that started the snip can arrive after that hand-back.
   */
  const startSnip = useCallback(() => {
    void takeKeyboard();
    setSnipping(true);
  }, []);

  const runSlashCommand = async (raw: string) => {
    const [command = "", ...args] = raw.trim().replace(/^\/+/, "").split(/\s+/);
    const name = command.toLowerCase();
    const current = settingsRef.current;
    const providerArg = args[0] ? providerFor(args[0]) : undefined;

    if (name === "model") {
      if (!args.length) return openSettings("model");
      // Anything that does not start with a provider name is a model search.
      if (!providerArg) return openSettings("model", args.join(" "));
      if (providerArg && args.length === 1) {
        const next = selectProvider(current, providerArg.id);
        await persistFromCommand(next);
        return;
      }
      if (providerArg) {
        const selected = selectProvider(current, providerArg.id);
        const next = updateProviderProfile(selected, providerArg.id, { model: args.slice(1).join(" ") });
        await persistFromCommand(next);
        return;
      }
      const next = updateProviderProfile(current, current.provider, { model: args.join(" ") });
      await persistFromCommand(next);
      return;
    }

    if (name === "provider") {
      if (!args.length) return openSettings("model");
      if (!providerArg) {
        setCommandNotice(`Unknown provider “${args[0]}”. Try /provider gemini, openai, openrouter, or ollama.`);
        return;
      }
      const next = selectProvider(current, providerArg.id);
      await persistFromCommand(next);
      return;
    }

    if (name === "key" || name === "api-key") {
      if (!args.length) return openSettings("model");
      const provider = providerArg ?? PROVIDERS.find((item) => item.id === current.provider);
      const key = providerArg ? args.slice(1).join(" ") : args.join(" ");
      if (!provider) return openSettings("model");
      if (!key) {
        if (provider.id !== current.provider) {
          const selected = selectProvider(current, provider.id);
          await persistFromCommand(selected);
        }
        openSettings("model");
        return;
      }
      const next = updateProviderProfile(current, provider.id, { api_key: key });
      await persistFromCommand(next);
      return;
    }

    if (name === "theme") {
      if (!args.length) return openSettings("appearance");
      const requested = args[0].toLowerCase();
      const theme = requested === "matugen" || requested === "qt/matugen" ? "qt" : requested === "system" ? "auto" : requested;
      if (!["auto", "dark", "light", "qt"].includes(theme)) {
        setCommandNotice("Theme options: auto, dark, light, or qt. Example: /theme qt");
        return;
      }
      await persistFromCommand({ ...current, theme: theme as Settings["theme"] });
      return;
    }

    if (name === "settings" || name === "preferences") {
      const section = args[0]?.toLowerCase();
      openSettings(section === "appearance" || section === "theme" ? "appearance" : section === "update" || section === "updates" ? "updates" : "model");
      return;
    }

    if (name === "update" || name === "updates") {
      if (!inTauri) {
        setCommandNotice("Updates are available in the installed Linux app.");
        return;
      }
      try {
        setCommandNotice("Updating in the background…");
        await updateFromSource();
      } catch (err) {
        setCommandNotice(`Update did not start: ${String(err)}`);
      }
      return;
    }

    if (name === "config") {
      openConfigFile();
      return;
    }

    if (name === "new") {
      update(() => []);
      setError(null);
      setPanel("none");
      setCommandNotice("Started a new chat.");
      return;
    }

    if (name === "capture" || name === "snip") {
      startSnip();
      return;
    }

    if (name === "hide" || name === "dismiss") {
      setVisible(false);
      return;
    }

    if (name === "exit" || name === "quit") {
      if (inTauri) await quitApp();
      else setVisible(false);
      return;
    }

    setCommandNotice(`Unknown command “/${name}”. Type / to browse commands.`);
  };

  const dismiss = useCallback(() => setVisible(false), []);

  const cropSelection = async (rect: { x: number; y: number; width: number; height: number }) => {
    if (!inTauri) {
      setCommandNotice("Screen-region capture is available in the installed Linux app.");
      setSnipping(false);
      return;
    }
    try {
      const shot: Shot = await cropScreenshot(rect, { width: window.innerWidth, height: window.innerHeight });
      if (shot.thumb) {
        setThumb(shot.thumb);
        setPreview(shot.preview || null);
      }
    } catch (err) {
      setCommandNotice(`Could not crop screenshot: ${String(err)}`);
    } finally {
      setSnipping(false);
    }
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (snipping) {
          setSnipping(false);
          return;
        }
        if (panel === "settings") setPanel(afterSettings());
        else setVisible(false);
      }
      if ((e.ctrlKey || e.metaKey) && e.key === ",") {
        e.preventDefault();
        if (panel === "settings") setPanel(afterSettings());
        else openSettings("model");
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [panel, snipping]);

  useEffect(() => {
    if (!commandNotice) return;
    const timer = window.setTimeout(() => setCommandNotice(null), 4200);
    return () => window.clearTimeout(timer);
  }, [commandNotice]);

  // theme.conf [shape]/[type]/[motion] knobs become CSS variables. Values not set
  // in the file fall back to the stylesheet defaults.
  useEffect(() => {
    const root = document.documentElement;
    const t = sysTheme.tokens;
    const radius = t.radius ?? 18;
    const innerRadius = t.inner_radius ?? Math.max(4, radius - 4);
    const controlRadius = t.control_radius ?? Math.max(4, radius - 8);
    const borderWidth = t.border_width ?? 2;
    const gap = t.gap ?? 24;

    root.style.setProperty("--radius-card", `${radius}px`);
    root.style.setProperty("--radius-inner", `${innerRadius}px`);
    root.style.setProperty("--radius-control", `${controlRadius}px`);
    root.style.setProperty("--border-width", `${borderWidth}px`);
    root.style.setProperty("--dock-gap", `${gap}px`);
    // `[appearance] shadow_intensity = 0` arrives as the literal `none`, which
    // cannot be composed into the focused card's `box-shadow` list — a `none`
    // entry makes the whole declaration invalid, ring included. A transparent
    // zero-size shadow is the same thing visually and stays list-safe.
    const shadow = (t.shadow ?? "").trim();
    const noShadow = shadow === "none";
    if (shadow) {
      root.style.setProperty("--card-shadow", noShadow ? "0 0 0 0 transparent" : shadow);
      // With no shadow at all, the focus glow goes too: it is a shadow as well.
      if (noShadow) root.style.setProperty("--focus-glow", "transparent");
      else root.style.removeProperty("--focus-glow");
    } else {
      root.style.removeProperty("--card-shadow");
      root.style.removeProperty("--focus-glow");
    }

    if (t.font) root.style.setProperty("--ui-font", `"${t.font}", "Geist Variable", system-ui, sans-serif`);
    else root.style.removeProperty("--ui-font");
    if (t.mono) root.style.setProperty("--ui-mono", `"${t.mono}", ui-monospace, monospace`);
    else root.style.removeProperty("--ui-mono");
    if (t.font_size) root.style.setProperty("--ui-size", `${t.font_size}px`);
    else root.style.removeProperty("--ui-size");
    root.style.setProperty("--motion-scale", String(t.speed));
    if (t.motion_reduced) root.dataset.motion = "reduced";
    else delete root.dataset.motion;
  }, [sysTheme]);

  // The card's surfaces all scale from one alpha so nothing inside it stays
  // solid while the card itself goes translucent. theme.conf `[appearance]`
  // feeds the same three variables: opacity through the settings (it wins over
  // settings.json), blur and noise straight from the tokens.
  const surfaceEffects = useMemo(() => {
    const percent = Math.min(100, Math.max(0, settings.bg_opacity ?? 100));
    return {
      alpha: Math.max(4, percent) / 100,
      blur: Math.max(0, Math.min(64, sysTheme.tokens.blur ?? 0)),
      noise: Math.max(0, Math.min(100, sysTheme.tokens.noise ?? 0)),
    };
  }, [settings.bg_opacity, sysTheme.tokens.blur, sysTheme.tokens.noise]);

  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty("--surface-alpha", surfaceEffects.alpha.toFixed(3));
    root.style.setProperty("--card-blur", `${surfaceEffects.blur}px`);
    // Grain reads strongest at 100; the ceiling keeps it from eating the text.
    root.style.setProperty("--card-noise", (surfaceEffects.noise ? (surfaceEffects.noise / 100) * 0.3 : 0).toFixed(3));
  }, [surfaceEffects]);

  const qtPalette = settings.theme === "qt" ? sysTheme.palette : null;
  const qtDark = qtPalette?.dark ?? sysTheme.dark;
  const dark = settings.theme === "dark" || (settings.theme !== "light" && qtDark);

  useEffect(() => {
    const root = document.documentElement;
    const t = sysTheme.tokens;
    const fallbackWindow = dark ? "#151f2d" : "#fafcff";
    const fallbackText = dark ? "#e9eef6" : "#263246";
    const fallbackAccent = dark ? "#82adff" : "#3973d1";
    const hasQtPalette = Boolean(
      qtPalette &&
        [
          qtPalette.window,
          qtPalette.window_text,
          qtPalette.base,
          qtPalette.text,
          qtPalette.button,
          qtPalette.highlight,
          qtPalette.link,
        ].some(Boolean)
    );

    const windowColor = normalizeHex(qtPalette?.window || qtPalette?.base, fallbackWindow);
    const windowText = normalizeHex(qtPalette?.window_text || qtPalette?.text, fallbackText);
    const baseColor = normalizeHex(qtPalette?.base || qtPalette?.window, windowColor);
    const baseText = normalizeHex(qtPalette?.text || qtPalette?.window_text, windowText);
    const buttonColor = normalizeHex(qtPalette?.button || qtPalette?.base, baseColor);
    const buttonText = normalizeHex(qtPalette?.button_text || qtPalette?.window_text, windowText);
    const alternateBase = normalizeHex(qtPalette?.alternate_base, baseColor);
    const accent = normalizeHex(qtPalette?.highlight || sysTheme.accent, fallbackAccent);
    const accentText = normalizeHex(qtPalette?.highlighted_text, contrastingText(accent));
    const link = normalizeHex(qtPalette?.link, accent);

    const activeBorder = t.active_border || accent;
    const inactiveBorder = t.inactive_border || (dark ? "rgba(169, 190, 220, 0.18)" : "rgba(24, 35, 55, 0.15)");

    root.dataset.theme = dark ? "dark" : "light";
    root.dataset.palette = hasQtPalette ? "qt" : "default";
    root.style.setProperty("--window-rgb", colorToRgb(windowColor) || colorToRgb(fallbackWindow)!);
    root.style.setProperty("--accent", accent);
    root.style.setProperty("--accent-rgb", colorToRgb(accent)!);
    root.style.setProperty("--accent-text", accentText);
    root.style.setProperty("--sel-fg", accentText);
    root.style.setProperty("--focus-ring", rgba(accent, 0.72));
    root.style.setProperty("--focus-glow", rgba(accent, 0.2));
    root.style.setProperty("--active-border", activeBorder);
    root.style.setProperty("--inactive-border", inactiveBorder);
    // The desktop's own "needs attention" hue, used for request errors.
    if (t.urgent_color) root.style.setProperty("--error", t.urgent_color);
    else root.style.removeProperty("--error");

    if (hasQtPalette) {
      root.style.setProperty("--qt-window", windowColor);
      root.style.setProperty("--qt-window-text", windowText);
      root.style.setProperty("--qt-base", baseColor);
      root.style.setProperty("--qt-text", baseText);
      root.style.setProperty("--qt-alternate-base", alternateBase);
      root.style.setProperty("--qt-button", buttonColor);
      root.style.setProperty("--qt-button-text", buttonText);
      root.style.setProperty("--qt-highlight", accent);
      root.style.setProperty("--qt-highlighted-text", accentText);
      root.style.setProperty("--qt-link", link);
      root.style.setProperty("--qt-tooltip-base", normalizeHex(qtPalette?.tooltip_base, windowColor));
      root.style.setProperty("--qt-tooltip-text", normalizeHex(qtPalette?.tooltip_text, windowText));
      root.style.setProperty("--qt-window-text-rgb", colorToRgb(windowText)!);
      root.style.setProperty("--qt-button-text-rgb", colorToRgb(buttonText)!);
      root.style.setProperty("--qt-text-rgb", colorToRgb(baseText)!);
      root.style.setProperty("--qt-highlight-rgb", colorToRgb(accent)!);
      // Surface opacity is multiplied into every plate, and CSS can only do that
      // to a color it has as `rgba(r, g, b, …)` — hence the channel triplets
      // alongside the hex values.
      root.style.setProperty("--surface-card-rgb", colorToRgb(windowColor) || colorToRgb(fallbackWindow)!);
      root.style.setProperty("--surface-sunken-rgb", colorToRgb(windowColor) || colorToRgb(fallbackWindow)!);
      root.style.setProperty("--surface-base-rgb", colorToRgb(baseColor) || colorToRgb(fallbackWindow)!);
      root.style.setProperty("--surface-raised-rgb", colorToRgb(buttonColor) || colorToRgb(fallbackWindow)!);
      root.style.setProperty("--surface-raised-hi-rgb", colorToRgb(mixHex(buttonColor, buttonText, 0.14))!);
      root.style.setProperty("--surface-hover-window-rgb", colorToRgb(mixHex(windowColor, windowText, 0.055))!);
      root.style.setProperty("--surface-hover-base-rgb", colorToRgb(mixHex(baseColor, baseText, 0.06))!);
      root.style.setProperty("--surface-hover-raised-rgb", colorToRgb(mixHex(buttonColor, buttonText, 0.08))!);
      root.style.setProperty("--surface-code-rgb", colorToRgb(alternateBase)!);
      root.style.setProperty("--qt-window-hover", mixHex(windowColor, windowText, 0.055));
      root.style.setProperty("--qt-base-hover", mixHex(baseColor, baseText, 0.06));
      root.style.setProperty("--qt-button-hover", mixHex(buttonColor, buttonText, 0.08));
      root.style.setProperty("--qt-button-raised", mixHex(buttonColor, buttonText, 0.14));
      root.style.setProperty("--qt-highlight-hover", mixHex(accent, accentText, 0.1));
      root.style.setProperty("--qt-base-border", rgba(baseText, 0.14));
    } else {
      // Without a Qt palette the built-in surfaces come from the stylesheet, so
      // any triplets left over from a Qt session have to go back out of the way.
      for (const name of SURFACE_RGB_VARS) root.style.removeProperty(name);
    }
  }, [dark, qtPalette, sysTheme]);

  const align =
    settings.position === "bottom-left"
      ? "items-start"
      : settings.position === "bottom-right"
      ? "items-end"
      : "items-center";

  const paddingStyle: React.CSSProperties = {
    paddingBottom: "var(--dock-gap, 24px)",
    paddingLeft: settings.position === "bottom-left" ? "var(--dock-gap, 24px)" : undefined,
    paddingRight: settings.position === "bottom-right" ? "var(--dock-gap, 24px)" : undefined,
  };

  return (
    <MotionScaleProvider scale={sysTheme.tokens.speed}>
      <div
        className={`fixed inset-0 flex flex-col justify-end pointer-events-none ${align}`}
        style={{
          ...paddingStyle,
          ...(desktopBackground ? {
            backgroundImage: `url(${desktopBackground})`,
            backgroundPosition: "center",
            backgroundRepeat: "no-repeat",
            backgroundSize: "cover",
          } : {}),
        }}
      >
        <AnimatePresence onExitComplete={() => {
          void overlayHidden().catch(() => {}).finally(() => setDesktopBackground(null));
        }}>
          {visible && (
            <Dock
              key="dock"
              sessionRevision={sessionRevision}
              panel={panel}
              settingsSection={settingsSection}
              messages={messages}
              streaming={streaming}
              error={error}
              notice={commandNotice}
              thumb={thumb}
              preview={preview}
              modelQuery={modelQuery}
              snipping={snipping}
              settings={settings}
              hasUpdate={hasUpdate}
              blur={surfaceEffects.blur}
              noise={surfaceEffects.noise}
              onSubmit={(prompt) => {
                if (prompt.trimStart().startsWith("/")) void runSlashCommand(prompt);
                else void submit(prompt);
              }}
              onSettingsSectionChange={setSettingsSection}
              onToggleSettings={() => (panel === "settings" ? setPanel(afterSettings()) : openSettings("model"))}
              onSaveSettings={save}
              onStartSnip={startSnip}
              onOpenConfig={openConfigFile}
              onCancelSnip={() => setSnipping(false)}
              onSelectSnip={cropSelection}
              onRetry={retry}
              onDismiss={dismiss}
            />
          )}
        </AnimatePresence>
      </div>
    </MotionScaleProvider>
  );
}

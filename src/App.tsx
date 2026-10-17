import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { listen } from "@tauri-apps/api/event";
import Dock, { Panel } from "./components/Dock";
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
  checkForUpdates,
  getSystemTheme,
  normalizeSettings,
  selectProvider,
  settingsForSave,
  updateProviderProfile,
  SystemTheme,
} from "./lib/store";

// Some "free" router models are safety classifiers and only ever say this.
const VERDICT = /^\s*(user\s+|content\s+)?safety\s*:?\s*(safe|unsafe)\b/i;

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
  const [desktopBackground, setDesktopBackground] = useState<string | null>(null);
  const [sessionRevision, setSessionRevision] = useState(0);
  const sessionRevisionRef = useRef<number | null>(null);
  const [snipping, setSnipping] = useState(false);
  const [commandNotice, setCommandNotice] = useState<string | null>(null);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [streaming, setStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasUpdate, setHasUpdate] = useState(false);
  const [sysTheme, setSysTheme] = useState<SystemTheme>({ dark: true, accent: null, palette: null });

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
      unsubs.push(await listen<{
        thumb: string;
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

  const openSettings = (section: SettingsSection = "model") => {
    setSettingsSection(section);
    setPanel("settings");
  };

  const providerFor = (name: string) =>
    PROVIDERS.find((provider) => provider.id === name.toLowerCase() || provider.label.toLowerCase() === name.toLowerCase());

  const runSlashCommand = async (raw: string) => {
    const [command = "", ...args] = raw.trim().replace(/^\/+/, "").split(/\s+/);
    const name = command.toLowerCase();
    const current = settingsRef.current;
    const providerArg = args[0] ? providerFor(args[0]) : undefined;

    if (name === "model") {
      if (!args.length) return openSettings("model");
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
      openSettings("updates");
      return;
    }

    if (name === "capture" || name === "snip") {
      setSnipping(true);
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
      const nextThumb = await cropScreenshot(rect, { width: window.innerWidth, height: window.innerHeight });
      if (nextThumb) setThumb(nextThumb);
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

  const qtPalette = settings.theme === "qt" ? sysTheme.palette : null;
  const qtDark = qtPalette?.dark ?? sysTheme.dark;
  const dark = settings.theme === "dark" || (settings.theme !== "light" && qtDark);

  useEffect(() => {
    const root = document.documentElement;
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

    root.dataset.theme = dark ? "dark" : "light";
    root.dataset.palette = hasQtPalette ? "qt" : "default";
    root.style.setProperty("--window-rgb", colorToRgb(windowColor) || colorToRgb(fallbackWindow)!);
    root.style.setProperty("--accent", accent);
    root.style.setProperty("--accent-rgb", colorToRgb(accent)!);
    root.style.setProperty("--accent-text", accentText);
    root.style.setProperty("--sel-fg", accentText);
    root.style.setProperty("--focus-ring", rgba(accent, 0.72));
    root.style.setProperty("--focus-glow", rgba(accent, 0.2));

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
      root.style.setProperty("--qt-window-hover", mixHex(windowColor, windowText, 0.055));
      root.style.setProperty("--qt-base-hover", mixHex(baseColor, baseText, 0.06));
      root.style.setProperty("--qt-button-hover", mixHex(buttonColor, buttonText, 0.08));
      root.style.setProperty("--qt-button-raised", mixHex(buttonColor, buttonText, 0.14));
      root.style.setProperty("--qt-highlight-hover", mixHex(accent, accentText, 0.1));
      root.style.setProperty("--qt-base-border", rgba(baseText, 0.14));
    }
  }, [dark, qtPalette, sysTheme]);

  const align =
    settings.position === "bottom-left"
      ? "items-start pl-6"
      : settings.position === "bottom-right"
      ? "items-end pr-6"
      : "items-center";

  return (
    <div
      className={`fixed inset-0 flex flex-col justify-end pb-6 pointer-events-none ${align}`}
      style={desktopBackground ? {
        backgroundImage: `url(${desktopBackground})`,
        backgroundPosition: "center",
        backgroundRepeat: "no-repeat",
        backgroundSize: "cover",
      } : undefined}
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
            snipping={snipping}
            settings={settings}
            hasUpdate={hasUpdate}
            onSubmit={(prompt) => {
              if (prompt.trimStart().startsWith("/")) void runSlashCommand(prompt);
              else void submit(prompt);
            }}
            onSettingsSectionChange={setSettingsSection}
            onToggleSettings={() => (panel === "settings" ? setPanel(afterSettings()) : openSettings("model"))}
            onSaveSettings={save}
            onStartSnip={() => setSnipping(true)}
            onCancelSnip={() => setSnipping(false)}
            onSelectSnip={cropSelection}
            onRetry={retry}
            onDismiss={dismiss}
          />
        )}
      </AnimatePresence>
    </div>
  );
}

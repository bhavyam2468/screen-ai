import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { listen } from "@tauri-apps/api/event";
import Dock, { Panel } from "./components/Dock";
import type { Msg } from "./components/ChatPanel";
import {
  DEFAULT_SETTINGS,
  Settings,
  askAi,
  getInitialState,
  getSettings,
  inTauri,
  overlayHidden,
  saveSettings,
  checkForUpdates,
  getSystemTheme,
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
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [thumb, setThumb] = useState<string | null>(null);
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

  const summon = useCallback((p: { thumb?: string; view?: string }) => {
    getSettings().then(setSettings);
    getSystemTheme().then(setSysTheme).catch(() => {});
    setThumb(p.thumb || null);
    update(() => []);
    setError(null);
    setStreaming(false);
    setPanel(p.view === "settings" ? "settings" : "none");
    setVisible(true);
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const init = await getInitialState();
        setSettings(init.settings);
        if (init.shown) summon({ thumb: init.thumb, view: init.view });
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
      unsubs.push(await listen<{ thumb: string; view: string }>("summon", (e) => summon(e.payload)));
      unsubs.push(await listen("request-hide", () => setVisible(false)));
      unsubs.push(await listen("show-settings", () => setPanel("settings")));
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

  const save = useCallback(async (s: Settings) => {
    setSettings(s);
    await saveSettings(s);
    setPanel(afterSettings());
  }, []);

  const dismiss = useCallback(() => setVisible(false), []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (panel === "settings") setPanel(afterSettings());
        else setVisible(false);
      }
      if ((e.ctrlKey || e.metaKey) && e.key === ",") {
        e.preventDefault();
        setPanel(panel === "settings" ? afterSettings() : "settings");
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [panel]);

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
    <div className={`fixed inset-0 flex flex-col justify-end pb-6 pointer-events-none ${align}`}>
      <AnimatePresence onExitComplete={() => overlayHidden()}>
        {visible && (
          <Dock
            key="dock"
            panel={panel}
            messages={messages}
            streaming={streaming}
            error={error}
            thumb={thumb}
            settings={settings}
            systemTheme={sysTheme}
            hasUpdate={hasUpdate}
            onSubmit={(p) => submit(p)}
            onToggleSettings={() => setPanel(panel === "settings" ? afterSettings() : "settings")}
            onSaveSettings={save}
            onCloseSettings={() => setPanel(afterSettings())}
            onRetry={retry}
            onDismiss={dismiss}
          />
        )}
      </AnimatePresence>
    </div>
  );
}

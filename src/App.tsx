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

export default function App() {
  const [visible, setVisible] = useState(false);
  const [panel, setPanel] = useState<Panel>("none");
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [thumb, setThumb] = useState<string | null>(null);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [streaming, setStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasUpdate, setHasUpdate] = useState(false);
  const [sysTheme, setSysTheme] = useState<SystemTheme>({ dark: true, accent: null });

  useEffect(() => {
    getSystemTheme().then(setSysTheme).catch(() => {});
    checkForUpdates()
      .then((res) => {
        if (res.has_update) setHasUpdate(true);
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

  const dark = settings.theme === "dark" || (settings.theme !== "light" && sysTheme.dark);

  useEffect(() => {
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    document.documentElement.style.setProperty("--accent", sysTheme.accent || (dark ? "#ffffff" : "#17171c"));
  }, [dark, sysTheme.accent]);

  const align =
    settings.position === "bottom-left"
      ? "items-start pl-6"
      : settings.position === "bottom-right"
      ? "items-end pr-6"
      : "items-center";

  const fontClass =
    settings.font_family === "jetbrains-mono"
      ? "font-mono"
      : settings.font_family === "system"
      ? "font-sans"
      : "font-serif";

  return (
    <div className={`fixed inset-0 flex flex-col justify-end pb-6 pointer-events-none ${align} ${fontClass}`}>
      <AnimatePresence onExitComplete={() => overlayHidden()}>
        {visible && (
          <Dock
            key="dock"
            panel={panel}
            messages={messages}
            streaming={streaming}
            error={error}
            thumb={thumb}
            dark={dark}
            settings={settings}
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

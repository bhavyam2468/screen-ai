import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowUp, Settings2, Loader2 } from "lucide-react";
import ChatPanel, { Msg } from "./ChatPanel";
import SettingsPanel from "./SettingsPanel";
import { Settings, setInteractiveRegions } from "../lib/store";

export type Panel = "none" | "chat" | "settings";

const EASE = [0.22, 1, 0.36, 1] as const;

interface Props {
  panel: Panel;
  messages: Msg[];
  streaming: boolean;
  error: string | null;
  thumb: string | null;
  dark: boolean;
  settings: Settings;
  hasUpdate?: boolean;
  onSubmit: (prompt: string) => void;
  onToggleSettings: () => void;
  onSaveSettings: (s: Settings) => void;
  onCloseSettings: () => void;
  onRetry: () => void;
  onDismiss: () => void;
}

/** Animates its height to follow its content, so panels slide open/closed. */
function Reveal({ children, instant }: { children: React.ReactNode; instant: boolean }) {
  const inner = useRef<HTMLDivElement>(null);
  const [h, setH] = useState(0);
  useLayoutEffect(() => {
    const el = inner.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setH(el.offsetHeight));
    ro.observe(el);
    setH(el.offsetHeight);
    return () => ro.disconnect();
  }, []);
  return (
    <motion.div
      initial={{ height: 0, opacity: 0 }}
      animate={{ height: h, opacity: 1 }}
      exit={{ height: 0, opacity: 0 }}
      transition={{ duration: instant ? 0 : 0.34, ease: EASE }}
      className="overflow-hidden"
    >
      <div ref={inner}>{children}</div>
    </motion.div>
  );
}

export default function Dock(p: Props) {
  const [value, setValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const cardRef = useRef<HTMLDivElement>(null);
  const opacity = (p.settings.bg_opacity ?? 100) / 100;
  const reduced = useMemo(
    () =>
      typeof window !== "undefined" &&
      !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,
    []
  );

  // Keep the compositor's input region glued to the card: everything outside
  // it passes clicks through to the apps underneath.
  const pushRegion = useRef<() => void>(() => {});
  useEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    let raf = 0;
    const push = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const r = el.getBoundingClientRect();
        const pad = 6;
        setInteractiveRegions([
          {
            x: Math.max(0, Math.floor(r.left - pad)),
            y: Math.max(0, Math.floor(r.top - pad)),
            width: Math.ceil(r.width + pad * 2),
            height: Math.ceil(r.height + pad * 2),
          },
        ]);
      });
    };
    pushRegion.current = push;
    const ro = new ResizeObserver(push);
    ro.observe(el);
    window.addEventListener("resize", push);
    push();
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      window.removeEventListener("resize", push);
    };
  }, []);

  // Grab keyboard focus whenever the overlay is (re)summoned.
  useEffect(() => {
    const focus = () => inputRef.current?.focus();
    const t = setTimeout(focus, 90);
    window.addEventListener("focus", focus);
    return () => {
      clearTimeout(t);
      window.removeEventListener("focus", focus);
    };
  }, []);

  useEffect(() => {
    if (p.panel !== "settings") inputRef.current?.focus();
  }, [p.panel]);

  const submit = () => {
    const v = value.trim();
    if (!v || p.streaming) return;
    p.onSubmit(v);
    setValue("");
  };

  const open = p.panel !== "none";
  const canSend = value.trim().length > 0 && !p.streaming;

  return (
    <motion.div
      ref={cardRef}
      initial={{ opacity: 0, y: 26, scale: 0.96, filter: "blur(6px)" }}
      animate={{ opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }}
      exit={{
        opacity: 0,
        y: 18,
        scale: 0.97,
        filter: "blur(4px)",
        transition: { duration: reduced ? 0 : 0.18, ease: EASE },
      }}
      transition={reduced ? { duration: 0 } : { type: "spring", stiffness: 380, damping: 32 }}
      onAnimationComplete={() => pushRegion.current()}
      style={{ backgroundColor: `rgba(${p.dark ? "34,36,42" : "247,247,249"},${opacity})` }}
      className="dock-card pointer-events-auto w-[540px] max-w-[calc(100vw-24px)] rounded-xl border border-white/15 shadow-2xl overflow-hidden"
    >
      <AnimatePresence initial={false}>
      {open && (
        <Reveal key="panel" instant={reduced}>
          <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={p.panel}
            initial={reduced ? false : { opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={reduced ? { opacity: 0 } : { opacity: 0, y: -8 }}
            transition={{ duration: reduced ? 0 : 0.18, ease: EASE }}
          >
            {p.panel === "settings" ? (
              <SettingsPanel settings={p.settings} onSave={p.onSaveSettings} onClose={p.onCloseSettings} />
            ) : (
              <ChatPanel
                messages={p.messages}
                streaming={p.streaming}
                error={p.error}
                model={p.settings.model}
                onClose={p.onDismiss}
                onRetry={p.onRetry}
              />
            )}
            </motion.div>
          </AnimatePresence>
        </Reveal>
      )}
      </AnimatePresence>

      <div
        className={`dock-inputbar flex items-center gap-2.5 px-3 py-2 transition-[border-color] duration-300 border-t ${
          open ? "border-white/10" : "border-transparent"
        }`}
      >
        <div className="shrink-0 w-7 h-7 rounded-lg overflow-hidden bg-neutral-800 border border-white/30 flex items-center justify-center">
          {p.thumb ? (
            <motion.img
              key="thumb"
              src={p.thumb}
              alt=""
              draggable={false}
              initial={reduced ? false : { scale: 0.5, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ type: "spring", stiffness: 500, damping: 28 }}
              className="w-full h-full object-cover"
            />
          ) : (
            <Loader2 size={13} className="text-white/50 animate-spin" />
          )}
        </div>

        <input
          ref={inputRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") submit();
          }}
          placeholder={p.messages.length ? "Ask a follow-up…" : "Ask about your screen…"}
          spellCheck={false}
          className="flex-1 bg-transparent text-[13px] placeholder:text-white/30 text-white"
        />

        <button
          onClick={p.onToggleSettings}
          className={`relative p-1 rounded-md transition-colors duration-150 ${
            p.panel === "settings" ? "text-white" : "text-white/40 hover:text-white"
          }`}
        >
          <Settings2 size={15} strokeWidth={1.8} />
          {p.hasUpdate && (
            <span className="absolute top-0.5 right-0.5 w-1.5 h-1.5 rounded-full bg-amber-400 ring-2 ring-black" />
          )}
        </button>

        <motion.button
          onClick={submit}
          disabled={!canSend}
          whileTap={reduced ? undefined : { scale: 0.8 }}
          className="p-1 rounded-md text-white/40 hover:text-white disabled:opacity-25 disabled:hover:text-white/40 transition-colors duration-150"
        >
          <ArrowUp size={16} strokeWidth={2.4} />
        </motion.button>
      </div>
    </motion.div>
  );
}

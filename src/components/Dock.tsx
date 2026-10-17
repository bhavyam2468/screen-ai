import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import {
  ArrowUp,
  Check,
  ChevronRight,
  Crosshair,
  FileText,
  FolderOpen,
  Loader2,
  Settings2,
  X,
} from "lucide-react";
import ChatPanel, { Msg } from "./ChatPanel";
import SettingsPanel from "./SettingsPanel";
import {
  FileSuggestion,
  ScreenRect,
  Settings,
  SettingsSection,
  searchLocalFiles,
  setInteractiveRegions,
} from "../lib/store";

export type Panel = "none" | "chat" | "settings";

const EASE = [0.22, 1, 0.36, 1] as const;
const LAYOUT_SPRING = { type: "spring", stiffness: 360, damping: 35, mass: 0.88 } as const;

/** One row in the slash palette. Commands are flat and each has a short description. */
type PaletteItem = { id: string; label: string; hint?: string; value: string };
type SlashCommand = { name: string; hint: string };

/**
 * Top-level commands. Add new ones here and handle them in App.runSlashCommand.
 * Keep hints short: they are shown only when they help.
 */
const SLASH_COMMANDS: SlashCommand[] = [
  { name: "model", hint: "Search and pick a model" },
  { name: "provider", hint: "Switch AI provider" },
  { name: "key", hint: "Set the API key" },
  { name: "theme", hint: "auto, dark, light, or qt" },
  { name: "settings", hint: "Open settings" },
  { name: "config", hint: "Edit theme.conf" },
  { name: "update", hint: "Update from GitHub" },
  { name: "capture", hint: "Select a screen region" },
  { name: "new", hint: "Start a new chat" },
  { name: "hide", hint: "Dismiss the overlay" },
  { name: "exit", hint: "Quit Screen AI" },
];

interface Props {
  sessionRevision: number;
  panel: Panel;
  settingsSection: SettingsSection;
  messages: Msg[];
  streaming: boolean;
  error: string | null;
  notice: string | null;
  thumb: string | null;
  snipping: boolean;
  settings: Settings;
  hasUpdate?: boolean;
  onSubmit: (prompt: string) => void;
  onSettingsSectionChange: (section: SettingsSection) => void;
  onToggleSettings: () => void;
  onSaveSettings: (settings: Settings) => void;
  onStartSnip: () => void;
  onCancelSnip: () => void;
  onSelectSnip: (rect: ScreenRect) => void;
  preview: string | null;
  modelQuery: string;
  onRetry: () => void;
  onDismiss: () => void;
}

/** Measures once per content change and lets the card use one coordinated height transition. */
function Reveal({ children, instant }: { children: React.ReactNode; instant: boolean }) {
  const inner = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(0);

  useLayoutEffect(() => {
    const element = inner.current;
    if (!element) return;
    const measure = () => setHeight(element.offsetHeight);
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    measure();
    return () => observer.disconnect();
  }, []);

  return (
    <motion.div
      initial={{ height: 0, opacity: 0 }}
      animate={{ height, opacity: 1 }}
      exit={{ height: 0, opacity: 0 }}
      transition={
        instant
          ? { duration: 0 }
          : { height: { duration: 0.3, ease: EASE }, opacity: { duration: 0.17, ease: "easeOut" } }
      }
      className="overflow-hidden"
    >
      <div ref={inner}>{children}</div>
    </motion.div>
  );
}

function findFileTrigger(value: string, caret: number) {
  const before = value.slice(0, caret);
  const braced = /(?:^|\s)@\{([^}\n]*)$/.exec(before);
  const plain = braced ? null : /(?:^|\s)@([^\s]*)$/.exec(before);
  const match = braced ?? plain;
  if (!match) return null;
  return {
    query: match[1],
    start: match.index + match[0].lastIndexOf("@"),
  };
}

function isSafePathToken(path: string) {
  return /^[\w./~+-]+$/u.test(path);
}

function FilePicker({
  items,
  loading,
  activeIndex,
  onChoose,
  onHighlight,
}: {
  items: FileSuggestion[];
  loading: boolean;
  activeIndex: number;
  onChoose: (item: FileSuggestion) => void;
  onHighlight: (index: number) => void;
}) {
  return (
    <div className="omnibox-panel" role="listbox" aria-label="Local files" aria-busy={loading}>
      {loading ? (
        <div className="omnibox-loading"><Loader2 size={14} className="animate-spin" /></div>
      ) : (
        <div className="omnibox-list">
          {items.map((item, index) => {
            const Icon = item.is_dir ? FolderOpen : FileText;
            return (
              <button
                key={item.path}
                type="button"
                role="option"
                aria-selected={activeIndex === index}
                className={`omnibox-row ${activeIndex === index ? "is-active" : ""}`}
                onMouseDown={(event) => event.preventDefault()}
                onMouseEnter={() => onHighlight(index)}
                onClick={() => onChoose(item)}
              >
                <span className="omnibox-icon"><Icon size={14} /></span>
                <span className="omnibox-label">{item.name}</span>
                <span className="omnibox-hint">{item.path.replace(/^\/home\/[^/]+/, "~")}</span>
                {item.is_dir && <ChevronRight size={12} className="omnibox-more" />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function Dock(p: Props) {
  const [value, setValue] = useState("");
  const [caret, setCaret] = useState(0);
  const [highlighted, setHighlighted] = useState(0);
  const [dismissed, setDismissed] = useState(false);
  const [forcedCommands, setForcedCommands] = useState(false);
  const [forcedQuery, setForcedQuery] = useState("");
  const [fileItems, setFileItems] = useState<FileSuggestion[]>([]);
  const [searchingFiles, setSearchingFiles] = useState(false);
  const [selection, setSelection] = useState<ScreenRect | null>(null);
  const selectionAnchor = useRef<{ x: number; y: number } | null>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const cardRef = useRef<HTMLDivElement>(null);
  const previewTimer = useRef<number>(0);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [previewPos, setPreviewPos] = useState<{ left: number; top?: number; bottom?: number }>({ left: 12, top: 12 });
  const opacity = (p.settings.bg_opacity ?? 100) / 100;
  const reduced = useReducedMotion() ?? false;

  const fileTrigger = useMemo(() => findFileTrigger(value, caret), [value, caret]);
  const fileQuery = fileTrigger?.query ?? null;
  const commandText = value.trimStart();
  const commandMatch = commandText.match(/^\/([a-z-]*)$/i);
  const argumentMatch = commandText.match(/^\/([a-z-]+)\s+([^\n]*)$/i);

  const paletteItems = useMemo<PaletteItem[]>(() => {
    const toItem = (command: SlashCommand): PaletteItem => ({
      id: command.name,
      label: `/${command.name}`,
      hint: command.hint,
      value: `/${command.name}`,
    });
    if (commandMatch) {
      const query = commandMatch[1].toLowerCase();
      return SLASH_COMMANDS.filter((item) => item.name.startsWith(query)).map(toItem);
    }
    if (!argumentMatch) {
      if (!forcedCommands) return [];
      const query = forcedQuery.trim().toLowerCase();
      return SLASH_COMMANDS.filter((item) => item.name.includes(query)).map(toItem);
    }
    const command = argumentMatch[1].toLowerCase();
    const raw = argumentMatch[2].trim();
    const definition = SLASH_COMMANDS.find((item) => item.name === (command === "api-key" ? "key" : command));
    if (!definition) return [];
    if (!raw) return [toItem(definition)];
    if (command === "model") {
      // A model search opens Settings → Model with the search filled in.
      return [{ id: "model-search", label: `Search models for “${raw}”`, hint: "Open Model settings", value: `/model ${raw}` }];
    }
    return [{ id: `${definition.name}-run`, label: `/${command} ${raw}`, hint: definition.hint, value: `/${command} ${raw}` }];
  }, [argumentMatch, commandMatch, forcedCommands, forcedQuery]);

  const forcedQueryMode = forcedCommands && !commandMatch && !argumentMatch;
  const showCommandPalette = (forcedCommands || paletteItems.length > 0) && !dismissed;
  const showFilePicker = fileTrigger !== null && !showCommandPalette && !dismissed;
  const activeIndex = Math.min(highlighted, Math.max(0, (showFilePicker ? fileItems.length : paletteItems.length) - 1));
  const open = p.panel !== "none";

  useEffect(() => {
    setHighlighted(0);
    setDismissed(false);
  }, [value]);

  useEffect(() => {
    setHighlighted(0);
  }, [forcedQuery]);

  useEffect(() => {
    if (fileQuery === null || dismissed || showCommandPalette) {
      setFileItems([]);
      setSearchingFiles(false);
      return;
    }
    let active = true;
    setSearchingFiles(true);
    setFileItems([]);
    const timer = window.setTimeout(() => {
      searchLocalFiles(fileQuery)
        .then((items) => { if (active) setFileItems(items); })
        .catch(() => { if (active) setFileItems([]); })
        .finally(() => { if (active) setSearchingFiles(false); });
    }, 100);
    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [fileQuery, dismissed, showCommandPalette]);

  useLayoutEffect(() => {
    const input = inputRef.current;
    if (!input) return;
    input.style.height = "0px";
    const maxHeight = Math.min(116, Math.max(42, window.innerHeight * 0.18));
    const nextHeight = Math.min(input.scrollHeight, maxHeight);
    input.style.height = `${nextHeight}px`;
    input.style.overflowY = input.scrollHeight > maxHeight ? "auto" : "hidden";
  }, [value]);

  // Let clicks pass through everywhere but the card, except while choosing a crop.
  useEffect(() => {
    const element = cardRef.current;
    if (p.snipping) {
      setInteractiveRegions(
        [{ x: 0, y: 0, width: window.innerWidth, height: window.innerHeight }],
        p.sessionRevision,
      );
      return;
    }
    if (!element) return;
    let frame = 0;
    const push = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const rect = element.getBoundingClientRect();
        const pad = 6;
        setInteractiveRegions([{
          x: Math.max(0, Math.floor(rect.left - pad)),
          y: Math.max(0, Math.floor(rect.top - pad)),
          width: Math.ceil(rect.width + pad * 2),
          height: Math.ceil(rect.height + pad * 2),
        }], p.sessionRevision);
      });
    };
    const observer = new ResizeObserver(push);
    observer.observe(element);
    window.addEventListener("resize", push);
    push();
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener("resize", push);
    };
  }, [p.snipping, p.sessionRevision]);

  // The overlay is summoned focused; when a panel closes, return focus to the one input.
  useEffect(() => {
    if (p.panel !== "settings" && !p.snipping) inputRef.current?.focus();
  }, [p.panel, p.snipping]);

  useEffect(() => {
    if (!p.preview || p.snipping) setPreviewOpen(false);
  }, [p.preview, p.snipping]);

  useEffect(() => {
    if (p.snipping || p.panel === "settings") {
      setForcedCommands(false);
      setForcedQuery("");
      setDismissed(true);
    }
  }, [p.panel, p.snipping]);

  // Ctrl/Cmd+K opens the command palette directly in the input bar.
  useEffect(() => {
    const onGlobalKey = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k" && !p.snipping) {
        event.preventDefault();
        inputRef.current?.focus();
        if (forcedCommands) {
          setForcedCommands(false);
          setDismissed(true);
        } else {
          setForcedCommands(true);
          setForcedQuery("");
          setDismissed(false);
        }
      }
    };
    window.addEventListener("keydown", onGlobalKey);
    return () => window.removeEventListener("keydown", onGlobalKey);
  }, [p.snipping, forcedCommands]);

  const submit = () => {
    const prompt = value.trim();
    if (!prompt || p.streaming) return;
    p.onSubmit(prompt);
    setValue("");
    setCaret(0);
    setDismissed(false);
    setForcedCommands(false);
    setForcedQuery("");
    setFileItems([]);
  };

  const choosePaletteItem = (item: PaletteItem) => {
    const keepDraft = forcedCommands && !value.trimStart().startsWith("/");
    if (!keepDraft) {
      setValue("");
      setCaret(0);
    }
    setForcedCommands(false);
    setForcedQuery("");
    setDismissed(false);
    p.onSubmit(item.value);
  };

  const chooseFile = (item: FileSuggestion) => {
    if (!fileTrigger) return;
    const path = `${item.path}${item.is_dir ? "/" : ""}`;
    const mention = isSafePathToken(path)
      ? `@${path}`
      : item.is_dir
        ? `@{${path}`
        : `@{${path}}`;
    const tail = item.is_dir ? "" : " ";
    const next = value.slice(0, fileTrigger.start) + mention + tail + value.slice(caret);
    const nextCaret = fileTrigger.start + mention.length + tail.length;
    setValue(next);
    setCaret(nextCaret);
    setDismissed(false);
    setFileItems([]);
    requestAnimationFrame(() => {
      inputRef.current?.focus();
      inputRef.current?.setSelectionRange(nextCaret, nextCaret);
    });
  };

  // Hovering the thumbnail for a moment shows the full capture above (or below) the card.
  const openPreviewSoon = () => {
    if (!p.preview || p.snipping) return;
    window.clearTimeout(previewTimer.current);
    previewTimer.current = window.setTimeout(() => {
      const rect = cardRef.current?.getBoundingClientRect();
      if (!rect) return;
      const above = rect.top > window.innerHeight * 0.45;
      setPreviewPos({
        left: Math.max(12, Math.min(rect.left, window.innerWidth - 12 - Math.min(640, window.innerWidth - 24))),
        ...(above ? { bottom: window.innerHeight - rect.top + 12 } : { top: rect.bottom + 12 }),
      });
      setPreviewOpen(true);
    }, 350);
  };
  const closePreview = () => {
    window.clearTimeout(previewTimer.current);
    setPreviewOpen(false);
  };

  const onInputKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    const suggestionsOpen = showCommandPalette || showFilePicker;
    const suggestionCount = showFilePicker ? fileItems.length : paletteItems.length;
    if (suggestionsOpen && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
      event.preventDefault();
      setHighlighted((index) => {
        if (!suggestionCount) return 0;
        return event.key === "ArrowDown"
          ? (index + 1) % suggestionCount
          : (index - 1 + suggestionCount) % suggestionCount;
      });
      return;
    }
    if (suggestionsOpen && (event.key === "Tab" || (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing))) {
      if (suggestionCount) {
        event.preventDefault();
        if (showFilePicker) chooseFile(fileItems[activeIndex]);
        else choosePaletteItem(paletteItems[activeIndex]);
        return;
      }
      if (event.key === "Enter" && forcedQueryMode) {
        event.preventDefault();
        return;
      }
    }
    if (forcedQueryMode && !event.nativeEvent.isComposing && !event.ctrlKey && !event.metaKey && !event.altKey) {
      if (event.key === "Enter" || event.key === "ArrowLeft" || event.key === "ArrowRight") {
        event.preventDefault();
        return;
      }
      if (event.key === "Backspace") {
        event.preventDefault();
        setForcedQuery((query) => query.slice(0, -1));
        return;
      }
      if (event.key.length === 1) {
        event.preventDefault();
        setForcedQuery((query) => query + event.key);
        return;
      }
    }
    if (suggestionsOpen && event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      setDismissed(true);
      setForcedCommands(false);
      setForcedQuery("");
      return;
    }
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      submit();
    }
  };

  return (
    <>
      <motion.div
        ref={cardRef}
        layout
        initial={reduced ? false : { opacity: 0, y: 8 }}
        animate={{ opacity: p.snipping ? 0 : 1, y: 0 }}
        exit={{ opacity: 0, y: 4, transition: { duration: reduced ? 0 : 0.13, ease: EASE } }}
        transition={reduced ? { duration: 0 } : { ...LAYOUT_SPRING, opacity: { duration: 0.16, ease: "easeOut" } }}
        onLayoutAnimationComplete={() => {
          const rect = cardRef.current?.getBoundingClientRect();
          if (!rect || p.snipping) return;
          setInteractiveRegions([{
            x: Math.max(0, Math.floor(rect.left - 6)),
            y: Math.max(0, Math.floor(rect.top - 6)),
            width: Math.ceil(rect.width + 12),
            height: Math.ceil(rect.height + 12),
          }], p.sessionRevision);
        }}
        style={{
          backgroundColor: `rgba(var(--window-rgb),${opacity})`,
          width: showCommandPalette ? "min(760px, calc(100vw - 24px))" : "min(540px, calc(100vw - 24px))",
          visibility: p.snipping ? "hidden" : "visible",
        }}
        className="dock-card pointer-events-auto relative z-10 max-w-[calc(100vw-24px)] overflow-hidden rounded-[var(--radius-card)] border border-white/15 shadow-[0_24px_80px_-28px_rgba(4,10,20,0.72)]"
      >
        <AnimatePresence initial={false}>
          {open && (
            <Reveal key="panel-reveal" instant={reduced}>
              <AnimatePresence mode="wait" initial={false}>
                <motion.div
                  key={p.panel}
                  initial={reduced ? false : { opacity: 0, y: 7 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={reduced ? { opacity: 0 } : { opacity: 0, y: -4 }}
                  transition={reduced ? { duration: 0 } : { duration: 0.19, ease: EASE }}
                >
                  {p.panel === "settings" ? (
                    <SettingsPanel
                      settings={p.settings}
                      section={p.settingsSection}
                      onSectionChange={p.onSettingsSectionChange}
                      onSave={p.onSaveSettings}
                      modelQuery={p.modelQuery}
                    />
                  ) : (
                    <ChatPanel
                      messages={p.messages}
                      streaming={p.streaming}
                      error={p.error}
                      onClose={p.onDismiss}
                      onRetry={p.onRetry}
                    />
                  )}
                </motion.div>
              </AnimatePresence>
            </Reveal>
          )}
        </AnimatePresence>

        <AnimatePresence initial={false}>
          {(showCommandPalette || showFilePicker) && (
            <motion.div
              key={showFilePicker ? "file-picker" : "command-picker"}
              initial={{ height: 0, opacity: 0, y: 4 }}
              animate={{ height: "auto", opacity: 1, y: 0 }}
              exit={{ height: 0, opacity: 0, y: 3 }}
              transition={reduced ? { duration: 0 } : { height: { duration: 0.26, ease: EASE }, opacity: { duration: 0.16, ease: "easeOut" }, y: { duration: 0.2, ease: EASE } }}
              className="overflow-hidden"
            >
              {showFilePicker ? (
                <FilePicker
                  items={fileItems}
                  loading={searchingFiles}
                  activeIndex={activeIndex}
                  onChoose={chooseFile}
                  onHighlight={setHighlighted}
                />
              ) : (
                <div className="omnibox-panel">
                  {forcedQueryMode && forcedQuery && <div className="omnibox-query">{forcedQuery}</div>}
                  <div className="omnibox-list" role="listbox" aria-label="Commands">
                    {paletteItems.map((item, index) => (
                      <button
                        key={item.id}
                        type="button"
                        role="option"
                        aria-selected={activeIndex === index}
                        className={`omnibox-row ${activeIndex === index ? "is-active" : ""}`}
                        onMouseDown={(event) => event.preventDefault()}
                        onMouseEnter={() => setHighlighted(index)}
                        onClick={() => choosePaletteItem(item)}
                      >
                        <span className="omnibox-label">{item.label}</span>
                        {item.hint && <span className="omnibox-desc">{item.hint}</span>}
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>

        <AnimatePresence initial={false}>
          {p.notice && !p.snipping && (
            <motion.div
              key="notice"
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              transition={reduced ? { duration: 0 } : { duration: 0.18, ease: EASE }}
              className="overflow-hidden"
            >
              <div className="dock-notice"><Check size={12} /><span>{p.notice}</span></div>
            </motion.div>
          )}
        </AnimatePresence>

        <div className={`dock-inputbar flex items-end gap-2.5 px-3.5 py-3 transition-colors ${open ? "border-t border-white/10" : "border-t border-transparent"}`}>
          <button
            type="button"
            onClick={p.onStartSnip}
            onMouseEnter={openPreviewSoon}
            onMouseLeave={closePreview}
            onFocus={openPreviewSoon}
            onBlur={closePreview}
            aria-label="Select a region from this screenshot"
            className="shot-button group relative mb-0.5 flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-[var(--radius-inner)] border border-white/15 bg-neutral-800 transition-[border-color,transform] duration-200 hover:-translate-y-px hover:border-white/30"
          >
            {p.thumb ? (
              <>
                <img src={p.thumb} alt="" draggable={false} className="h-full w-full object-cover" />
                <span className="shot-hover"><Crosshair size={13} /></span>
              </>
            ) : (
              <Crosshair size={14} className="text-white/45" />
            )}
            {!p.thumb && <Loader2 size={11} className="absolute bottom-0.5 right-0.5 animate-spin text-white/30" />}
          </button>

          <textarea
            ref={inputRef}
            rows={1}
            value={value}
            onChange={(event) => {
              setValue(event.target.value);
              setCaret(event.target.selectionStart);
            }}
            onSelect={(event) => setCaret((event.target as HTMLTextAreaElement).selectionStart)}
            onKeyDown={onInputKeyDown}
            placeholder="Ask…"
            aria-label="Ask about your screen"
            aria-expanded={showCommandPalette || showFilePicker}
            spellCheck={false}
            className="dock-textarea min-w-0 flex-1 resize-none bg-transparent px-1 py-1.5 text-[length:var(--ui-size,13px)] leading-[1.45] text-white placeholder:text-white/30"
          />

          <button
            type="button"
            onClick={p.onToggleSettings}
            aria-label={p.panel === "settings" ? "Close settings" : "Open settings"}
            className={`mb-0.5 relative flex h-7 w-7 shrink-0 items-center justify-center rounded-[var(--radius-inner)] transition-colors duration-150 ${
              p.panel === "settings" ? "text-white" : "text-white/40 hover:bg-white/5 hover:text-white"
            }`}
          >
            <Settings2 size={15} strokeWidth={1.8} />
            {p.hasUpdate && <span className="absolute right-1 top-1 h-1.5 w-1.5 rounded-full bg-amber-400 ring-2 ring-black" />}
          </button>

          <motion.button
            type="button"
            onClick={submit}
            disabled={!value.trim() || p.streaming}
            whileTap={reduced ? undefined : { scale: 0.94 }}
            aria-label="Send prompt"
            className={`mb-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-[var(--radius-inner)] transition-colors duration-150 disabled:opacity-35 ${
              value.trim() && !p.streaming ? "accent-action" : "text-white/40"
            }`}
          >
            <ArrowUp size={16} strokeWidth={2.4} />
          </motion.button>
        </div>
      </motion.div>

      <AnimatePresence>
        {previewOpen && p.preview && !p.snipping && (
          <motion.div
            key="shot-preview"
            className="shot-preview"
            style={previewPos}
            initial={reduced ? false : { opacity: 0, scale: 0.97, y: 4 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, transition: { duration: 0.1 } }}
            transition={reduced ? { duration: 0 } : { duration: 0.16, ease: EASE }}
          >
            <img src={p.preview} alt="Full screenshot preview" draggable={false} />
          </motion.div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {p.snipping && (
          <motion.div
            key="screen-snipping"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={reduced ? { duration: 0 } : { duration: 0.12, ease: "easeOut" }}
            className="screen-snipping"
            style={{ cursor: "crosshair" }}
            onPointerDown={(event) => {
              if (event.button !== 0) return;
              const anchor = { x: event.clientX, y: event.clientY };
              selectionAnchor.current = anchor;
              setSelection({ ...anchor, width: 0, height: 0 });
              event.currentTarget.setPointerCapture(event.pointerId);
            }}
            onPointerMove={(event) => {
              const anchor = selectionAnchor.current;
              if (!anchor || !event.currentTarget.hasPointerCapture(event.pointerId)) return;
              setSelection({
                x: Math.min(anchor.x, event.clientX),
                y: Math.min(anchor.y, event.clientY),
                width: Math.abs(event.clientX - anchor.x),
                height: Math.abs(event.clientY - anchor.y),
              });
            }}
            onPointerUp={(event) => {
              const anchor = selectionAnchor.current;
              selectionAnchor.current = null;
              if (!anchor) return;
              const finalSelection = {
                x: Math.min(anchor.x, event.clientX),
                y: Math.min(anchor.y, event.clientY),
                width: Math.abs(event.clientX - anchor.x),
                height: Math.abs(event.clientY - anchor.y),
              };
              if (finalSelection.width < 6 || finalSelection.height < 6) {
                setSelection(null);
                return;
              }
              if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
              p.onSelectSnip(finalSelection);
              setSelection(null);
            }}
            onPointerCancel={() => { selectionAnchor.current = null; setSelection(null); }}
          >
            <div className="snip-shade" />
            {selection && selection.width > 0 && selection.height > 0 && (
              <div
                className="snip-selection"
                style={{ left: selection.x, top: selection.y, width: selection.width, height: selection.height }}
              />
            )}
            <div className="snip-hud" onPointerDown={(event) => event.stopPropagation()}>
              <button type="button" onClick={p.onCancelSnip} aria-label="Cancel screenshot selection"><X size={13} /></button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}

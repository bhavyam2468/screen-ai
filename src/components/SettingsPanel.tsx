import { useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  X,
  Check,
  Eye,
  EyeOff,
  AlignStartVertical,
  AlignCenterVertical,
  AlignEndVertical,
  Power,
  RefreshCw,
  Search,
} from "lucide-react";
import { Settings, PROVIDERS, ReplyPosition, quitApp, fetchModels } from "../lib/store";

interface Props {
  settings: Settings;
  onSave: (s: Settings) => void;
  onClose: () => void;
}

const POSITIONS: { id: ReplyPosition; icon: typeof AlignStartVertical; label: string }[] = [
  { id: "bottom-left", icon: AlignStartVertical, label: "Left" },
  { id: "bottom-center", icon: AlignCenterVertical, label: "Center" },
  { id: "bottom-right", icon: AlignEndVertical, label: "Right" },
];

// Safety classifiers (Llama Guard & co) answer "safe"/"unsafe" instead of chatting.
const NOT_CHAT = /guard|moderat|safety|shield|classif/i;

const LABEL = "text-[10px] uppercase tracking-[0.2em] text-white/40 mb-1.5 font-semibold";
const FIELD =
  "w-full rounded-lg bg-neutral-900 border border-white/10 px-3 py-2 text-[13px] placeholder:text-white/25 text-white focus:border-white/30 transition-colors";

export default function SettingsPanel({ settings, onSave, onClose }: Props) {
  const [draft, setDraft] = useState<Settings>({ ...settings });
  const [showKey, setShowKey] = useState(false);
  const [fetching, setFetching] = useState(false);
  const [fetched, setFetched] = useState<string[]>([]);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");

  const preset = PROVIDERS.find((p) => p.id === draft.provider) ?? PROVIDERS[0];
  const dirty = JSON.stringify(draft) !== JSON.stringify(settings);

  const pickProvider = (id: string) => {
    const p = PROVIDERS.find((x) => x.id === id)!;
    setDraft((d) => ({ ...d, provider: id, base_url: p.id === "custom" ? d.base_url : p.base_url }));
    setFetched([]);
    setFetchError(null);
  };

  const doFetch = async () => {
    setFetching(true);
    setFetchError(null);
    try {
      const list = (await fetchModels(draft.provider, draft.base_url, draft.api_key)).filter(
        (m) => !NOT_CHAT.test(m)
      );
      if (!list.length) setFetchError("No models returned by endpoint.");
      else {
        setFetched(list);
        if (!draft.model || !list.includes(draft.model)) setDraft((d) => ({ ...d, model: list[0] }));
      }
    } catch (err) {
      setFetchError(String(err));
    } finally {
      setFetching(false);
    }
  };

  const shown = fetched.filter((m) => m.toLowerCase().includes(filter.toLowerCase()));

  return (
    <div className="flex flex-col max-h-[min(580px,calc(100vh-160px))]">
      <div className="flex items-center justify-between px-3.5 py-2.5 shrink-0">
        <span className="text-white text-[12px] font-semibold tracking-[0.2em] uppercase">Settings</span>
        <div className="flex items-center gap-0.5">
          <button
            onClick={() => quitApp()}
            className="w-6 h-6 rounded-md flex items-center justify-center text-white/40 hover:text-rose-400 transition-colors"
          >
            <Power size={13} />
          </button>
          <button
            onClick={onClose}
            className="w-6 h-6 rounded-md flex items-center justify-center text-white/40 hover:text-white transition-colors"
          >
            <X size={14} />
          </button>
        </div>
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto px-3.5 pb-3 space-y-4">
        <div>
          <p className={LABEL}>Provider</p>
          <div className="flex flex-wrap gap-1.5">
            {PROVIDERS.map((p) => (
              <button
                key={p.id}
                onClick={() => pickProvider(p.id)}
                className={`px-3 py-1.5 rounded-lg text-[12px] border transition-colors ${
                  draft.provider === p.id
                    ? "bg-white text-black font-semibold border-white"
                    : "bg-neutral-900 border-white/10 text-white/60 hover:text-white hover:bg-neutral-800"
                }`}
              >
                {p.label}
              </button>
            ))}
          </div>
        </div>

        {preset.needsKey && (
          <div>
            <p className={LABEL}>API Key</p>
            <div className="flex items-center gap-2 rounded-lg bg-neutral-900 border border-white/10 px-3 py-2 focus-within:border-white/30 transition-colors">
              <input
                type={showKey ? "text" : "password"}
                value={draft.api_key}
                onChange={(e) => setDraft({ ...draft, api_key: e.target.value })}
                placeholder="Enter API key…"
                spellCheck={false}
                className="flex-1 bg-transparent text-[13px] placeholder:text-white/25 text-white"
              />
              <button onClick={() => setShowKey(!showKey)} className="text-white/30 hover:text-white transition-colors">
                {showKey ? <EyeOff size={15} /> : <Eye size={15} />}
              </button>
            </div>
          </div>
        )}

        {(draft.provider === "custom" || draft.provider === "openrouter" || draft.provider === "ollama") && (
          <div>
            <p className={LABEL}>Base URL</p>
            <input
              value={draft.base_url}
              onChange={(e) => setDraft({ ...draft, base_url: e.target.value })}
              placeholder="https://…"
              spellCheck={false}
              className={FIELD}
            />
          </div>
        )}

        <div>
          <div className="flex items-center justify-between mb-1.5">
            <p className="text-[10px] uppercase tracking-[0.2em] text-white/40 font-semibold">Model</p>
            <button
              onClick={doFetch}
              disabled={fetching}
              className="flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-neutral-900 hover:bg-neutral-800 border border-white/15 text-[11px] text-white/70 hover:text-white transition-colors"
            >
              <RefreshCw size={11} className={fetching ? "animate-spin" : ""} />
              {fetching ? "Fetching…" : "Fetch Models"}
            </button>
          </div>
          <input
            value={draft.model}
            onChange={(e) => setDraft({ ...draft, model: e.target.value })}
            placeholder="model id"
            spellCheck={false}
            className={FIELD + " mb-2"}
          />
          {fetchError && (
            <p className="text-[11px] text-rose-400 bg-rose-500/10 border border-rose-500/20 rounded-lg p-2 mb-2">
              {fetchError}
            </p>
          )}
          {fetched.length > 0 && (
            <div className="rounded-lg bg-neutral-950 border border-white/10 p-2 space-y-1.5">
              <div className="flex items-center gap-1.5 px-2 py-1 rounded-md bg-neutral-900 border border-white/10">
                <Search size={12} className="text-white/30" />
                <input
                  value={filter}
                  onChange={(e) => setFilter(e.target.value)}
                  placeholder="Search…"
                  className="w-full bg-transparent text-[11.5px] text-white placeholder:text-white/25"
                />
                <span className="text-[10px] text-white/40">{shown.length}</span>
              </div>
              <div className="max-h-36 overflow-y-auto space-y-1 pr-1">
                {shown.slice(0, 60).map((m) => (
                  <button
                    key={m}
                    onClick={() => setDraft({ ...draft, model: m })}
                    className={`w-full text-left px-2.5 py-1.5 rounded-md text-[12px] transition-colors truncate block ${
                      draft.model === m
                        ? "bg-white text-black font-semibold"
                        : "text-white/60 hover:text-white hover:bg-neutral-900"
                    }`}
                  >
                    {m}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        <div>
          <div className="flex items-center justify-between mb-1.5">
            <p className="text-[10px] uppercase tracking-[0.2em] text-white/40 font-semibold">Opacity</p>
            <span className="text-[11px] text-white/60">{draft.bg_opacity ?? 100}%</span>
          </div>
          <input
            type="range"
            min={0}
            max={100}
            step={1}
            value={draft.bg_opacity ?? 100}
            onChange={(e) => setDraft({ ...draft, bg_opacity: Number(e.target.value) })}
            className="w-full h-1.5 bg-neutral-800 rounded-lg appearance-none cursor-pointer accent-white"
          />
        </div>

        <div>
          <p className={LABEL}>Position</p>
          <div className="grid grid-cols-3 gap-2">
            {POSITIONS.map(({ id, icon: Icon, label }) => (
              <button
                key={id}
                onClick={() => setDraft({ ...draft, position: id })}
                className={`py-2 rounded-lg border flex flex-col items-center justify-center gap-1 transition-colors ${
                  draft.position === id
                    ? "bg-white text-black font-semibold border-white"
                    : "bg-neutral-900 border-white/10 text-white/40 hover:text-white hover:bg-neutral-800"
                }`}
              >
                <Icon size={16} />
                <span className="text-[10.5px]">{label}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="p-3 border-t border-white/10 shrink-0">
        <button
          onClick={() => onSave(draft)}
          className={`w-full py-2 rounded-lg text-[13px] flex items-center justify-center gap-2 transition-colors ${
            dirty
              ? "bg-white text-black font-semibold hover:bg-neutral-200"
              : "bg-neutral-900 text-white/50 border border-white/10 hover:text-white"
          }`}
        >
          <Check size={14} /> {dirty ? "Save" : "Done"}
        </button>
      </div>
    </div>
  );
}

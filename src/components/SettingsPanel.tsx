import { useEffect, useState } from "react";
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
  Download,
  GitPullRequest,
  Moon,
  Sun,
  SunMoon,
  Palette,
} from "lucide-react";
import {
  Settings,
  PROVIDERS,
  ReplyPosition,
  ThemeMode,
  SystemTheme,
  quitApp,
  fetchModels,
  checkForUpdates,
  updateFromSource,
  updateFromPr,
  restartApp,
  UpdateStatus,
} from "../lib/store";

interface Props {
  settings: Settings;
  systemTheme: SystemTheme;
  onSave: (s: Settings) => void;
  onClose: () => void;
}

const POSITIONS: { id: ReplyPosition; icon: typeof AlignStartVertical; label: string }[] = [
  { id: "bottom-left", icon: AlignStartVertical, label: "Left" },
  { id: "bottom-center", icon: AlignCenterVertical, label: "Center" },
  { id: "bottom-right", icon: AlignEndVertical, label: "Right" },
];

const THEMES: { id: ThemeMode; icon: typeof Moon; label: string }[] = [
  { id: "auto", icon: SunMoon, label: "Auto" },
  { id: "dark", icon: Moon, label: "Dark" },
  { id: "light", icon: Sun, label: "Light" },
  { id: "qt", icon: Palette, label: "Qt / Matugen" },
];

// Safety classifiers (Llama Guard & co) answer "safe"/"unsafe" instead of chatting.
const NOT_CHAT = /guard|moderat|safety|shield|classif/i;

const LABEL = "text-[10.5px] uppercase tracking-[0.14em] text-white/45 mb-1.5 font-semibold";
const FIELD =
  "w-full rounded-lg bg-neutral-800 border border-white/10 px-3 py-2 text-[13px] placeholder:text-white/25 text-white focus:border-white/30 transition-colors";

export default function SettingsPanel({ settings, systemTheme, onSave, onClose }: Props) {
  const [draft, setDraft] = useState<Settings>({ ...settings });
  const [showKey, setShowKey] = useState(false);
  const [fetching, setFetching] = useState(false);
  const [fetched, setFetched] = useState<string[]>([]);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");

  const [checkingUpdate, setCheckingUpdate] = useState(false);
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus | null>(null);
  const [updatingSource, setUpdatingSource] = useState(false);
  const [updateError, setUpdateError] = useState<string | null>(null);
  const [updateSuccess, setUpdateSuccess] = useState(false);
  const [updateMessage, setUpdateMessage] = useState<string | null>(null);
  const [prNumber, setPrNumber] = useState("");
  const [buildingPr, setBuildingPr] = useState(false);

  useEffect(() => {
    checkUpdates();
  }, []);

  const checkUpdates = async () => {
    setCheckingUpdate(true);
    setUpdateError(null);
    try {
      const info = await checkForUpdates();
      setUpdateStatus(info);
    } catch (err) {
      setUpdateError(String(err));
    } finally {
      setCheckingUpdate(false);
    }
  };

  const triggerUpdate = async () => {
    setUpdatingSource(true);
    setUpdateError(null);
    setUpdateMessage(null);
    try {
      const message = await updateFromSource();
      setUpdateMessage(message);
      setUpdateSuccess(true);
    } catch (err) {
      setUpdateError(String(err));
    } finally {
      setUpdatingSource(false);
    }
  };

  const buildPullRequest = async () => {
    const number = Number(prNumber.trim());
    if (!Number.isSafeInteger(number) || number < 1) {
      setUpdateError("Enter a valid Screen AI pull request number.");
      return;
    }

    setBuildingPr(true);
    setUpdateError(null);
    setUpdateMessage(null);
    try {
      const message = await updateFromPr(number);
      setUpdateMessage(message);
      setUpdateSuccess(true);
    } catch (err) {
      setUpdateError(String(err));
    } finally {
      setBuildingPr(false);
    }
  };

  const doRestart = async () => {
    try {
      await restartApp();
    } catch (err) {
      setUpdateError(String(err));
    }
  };

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
            aria-label="Quit Screen AI"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-white/45 hover:text-rose-400 hover:bg-rose-500/10 transition-colors"
          >
            <Power size={13} />
          </button>
          <button
            onClick={onClose}
            aria-label="Close settings"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-white/45 hover:text-white hover:bg-white/5 transition-colors"
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
                    : "bg-neutral-800 border-white/10 text-white/60 hover:text-white hover:bg-neutral-700"
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
            <div className="flex items-center gap-2 rounded-lg bg-neutral-800 border border-white/10 px-3 py-2 focus-within:border-white/30 transition-colors">
              <input
                type={showKey ? "text" : "password"}
                value={draft.api_key}
                onChange={(e) => setDraft({ ...draft, api_key: e.target.value })}
                placeholder="Enter API key…"
                spellCheck={false}
                className="flex-1 bg-transparent text-[13px] placeholder:text-white/25 text-white"
              />
              <button onClick={() => setShowKey(!showKey)} aria-label={showKey ? "Hide API key" : "Show API key"} className="text-white/35 hover:text-white transition-colors">
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
              className="flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-neutral-800 hover:bg-neutral-700 border border-white/15 text-[11px] text-white/70 hover:text-white transition-colors"
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
            <div className="rounded-lg bg-neutral-900 border border-white/10 p-2 space-y-1.5">
              <div className="flex items-center gap-1.5 px-2 py-1 rounded-md bg-neutral-800 border border-white/10">
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
                        : "text-white/60 hover:text-white hover:bg-neutral-800"
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
            className="w-full h-1.5 bg-neutral-700 rounded-lg appearance-none cursor-pointer accent-white"
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
                    : "bg-neutral-800 border-white/10 text-white/40 hover:text-white hover:bg-neutral-700"
                }`}
              >
                <Icon size={16} />
                <span className="text-[10.5px]">{label}</span>
              </button>
            ))}
          </div>
        </div>

        <div>
          <p className={LABEL}>Theme</p>
          <div className="grid grid-cols-4 gap-2">
            {THEMES.map(({ id, icon: Icon, label }) => (
              <button
                key={id}
                onClick={() => setDraft({ ...draft, theme: id })}
                title={id === "qt" ? "Use the detected KDE, qt5ct, or qt6ct color palette" : label}
                className={`py-2 rounded-lg border flex flex-col items-center justify-center gap-1 transition-colors ${
                  (draft.theme ?? "auto") === id
                    ? "bg-white text-black font-semibold border-white"
                    : "bg-neutral-800 border-white/10 text-white/40 hover:text-white hover:bg-neutral-700"
                }`}
              >
                <Icon size={16} />
                <span className="text-[10.5px]">{label}</span>
              </button>
            ))}
          </div>
          {draft.theme === "qt" ? (
            <p className="mt-2 text-[10.5px] leading-relaxed text-white/40">
              {systemTheme.palette?.name
                ? `Using the detected “${systemTheme.palette.name}” palette. Colors refresh when the overlay is summoned.`
                : systemTheme.palette
                ? "A Qt color palette was detected and refreshes when the overlay is summoned."
                : "No KDE or qt5ct/qt6ct palette was detected. Qt mode will fall back to your desktop's light/dark and accent colors."}
            </p>
          ) : (
            <p className="mt-2 text-[10.5px] leading-relaxed text-white/40">
              Auto follows the desktop mode and accent. Qt / Matugen maps detected system palette colors into the overlay.
            </p>
          )}
        </div>

        <div className="pt-3 border-t border-white/10">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <p className={LABEL}>Updates</p>
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-[12px] text-white/90 font-mono">
                  {updateStatus?.current_version || (checkingUpdate ? "Checking…" : "Version unavailable")}
                </span>
                <span
                  className={`px-1.5 py-0.5 rounded text-[10px] border ${
                    updateStatus?.update_available
                      ? "bg-amber-500/15 text-amber-300 border-amber-500/25"
                      : "bg-white/5 text-white/50 border-white/10"
                  }`}
                >
                  {updateStatus?.update_available
                    ? "Update available"
                    : updateStatus
                    ? "Up to date"
                    : checkingUpdate
                    ? "Checking source"
                    : "Source status unavailable"}
                </span>
              </div>
            </div>
            <button
              type="button"
              onClick={checkUpdates}
              disabled={checkingUpdate || updatingSource || buildingPr}
              aria-label="Check for source updates"
              className="shrink-0 px-2.5 py-1.5 rounded-lg bg-neutral-800 border border-white/10 hover:border-white/25 text-[11px] text-white/70 hover:text-white flex items-center gap-1.5 transition-colors disabled:opacity-50"
            >
              <RefreshCw size={11} className={checkingUpdate ? "animate-spin text-white" : ""} />
              <span>{checkingUpdate ? "Checking…" : "Check"}</span>
            </button>
          </div>

          {updateStatus?.update_available && (
            <div className="mt-2 p-2.5 rounded-lg bg-amber-400/[0.06] border border-amber-300/10">
              <p className="text-[11px] text-white/75 leading-relaxed break-words" title={updateStatus.latest_message}>
                {updateStatus.latest_message}
              </p>
              <p className="mt-1 text-[10px] font-mono text-white/40">main · {updateStatus.latest_sha.slice(0, 8)}</p>
            </div>
          )}

          {updateSuccess ? (
            <div className="mt-2.5 space-y-2">
              <p className="text-[11px] text-emerald-300">Build complete. Restart Screen AI to apply it.</p>
              <button
                type="button"
                onClick={doRestart}
                aria-live="polite"
                className="w-full py-2 rounded-lg bg-emerald-400 hover:bg-emerald-300 text-neutral-950 font-semibold text-[12px] flex items-center justify-center gap-1.5 transition-colors"
              >
                <RefreshCw size={12} /> Restart app
              </button>
            </div>
          ) : (
            <button
              type="button"
              onClick={triggerUpdate}
              disabled={checkingUpdate || updatingSource || buildingPr}
              aria-live="polite"
              className="w-full mt-2.5 py-2 rounded-lg bg-white hover:bg-neutral-200 text-black font-semibold text-[12px] flex items-center justify-center gap-1.5 transition-colors disabled:opacity-50"
            >
              {updatingSource ? (
                <>
                  <RefreshCw size={12} className="animate-spin" />
                  <span>Pulling and building on this device…</span>
                </>
              ) : (
                <>
                  <Download size={12} />
                  <span>{updateStatus?.update_available ? "Pull & build update" : "Pull & rebuild latest"}</span>
                </>
              )}
            </button>
          )}
          {!updateSuccess && (
            <div className="mt-3 p-2.5 rounded-lg bg-neutral-900 border border-white/10 space-y-2">
              <p className={LABEL}>Build a pull request</p>
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  min={1}
                  step={1}
                  value={prNumber}
                  onChange={(e) => setPrNumber(e.target.value)}
                  placeholder="PR number"
                  aria-label="Screen AI pull request number"
                  className={`${FIELD} min-w-0 flex-1`}
                  disabled={buildingPr || updatingSource || checkingUpdate}
                />
                <button
                  type="button"
                  onClick={buildPullRequest}
                  disabled={!prNumber.trim() || buildingPr || updatingSource || checkingUpdate}
                  className="shrink-0 px-3 py-2 rounded-lg bg-neutral-800 border border-white/10 hover:border-white/25 text-[12px] text-white/80 hover:text-white flex items-center gap-1.5 transition-colors disabled:opacity-50"
                >
                  {buildingPr ? (
                    <RefreshCw size={12} className="animate-spin" />
                  ) : (
                    <GitPullRequest size={13} />
                  )}
                  {buildingPr ? "Building…" : "Build PR"}
                </button>
              </div>
              <p className="text-[10px] leading-relaxed text-white/35">
                Pulls this repository’s PR and builds it locally, replacing the installed app. Only build PRs you trust.
              </p>
            </div>
          )}
          <p className="mt-1.5 text-[10px] leading-relaxed text-white/35">
            GitHub source is compiled locally. No prebuilt app binary is downloaded.
          </p>
          {updateMessage && <p className="text-[10px] text-emerald-300/80 mt-1">{updateMessage}</p>}
          {updateError && <p className="text-[11px] text-rose-400 mt-2 break-words">{updateError}</p>}
        </div>
      </div>

      <div className="p-3 border-t border-white/10 shrink-0">
        <button
          onClick={() => onSave(draft)}
          className={`w-full py-2 rounded-lg text-[13px] flex items-center justify-center gap-2 transition-colors ${
            dirty
              ? "bg-white text-black font-semibold hover:bg-neutral-200"
              : "bg-neutral-800 text-white/50 border border-white/10 hover:text-white"
          }`}
        >
          <Check size={14} /> {dirty ? "Save" : "Done"}
        </button>
      </div>
    </div>
  );
}

import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import {
  AlignCenterVertical,
  AlignEndVertical,
  AlignStartVertical,
  Download,
  Eye,
  EyeOff,
  GitPullRequest,
  RefreshCw,
  Search,
} from "lucide-react";
import {
  PROVIDERS,
  ProviderProfile,
  ReplyPosition,
  Settings,
  SettingsSection,
  ThemeMode,
  UpdateStatus,
  checkForUpdates,
  fetchModels,
  normalizeSettings,
  restartApp,
  settingsForSave,
  updateFromPr,
  updateFromSource,
  inTauri,
  UpdateEvent,
} from "../lib/store";

interface Props {
  settings: Settings;
  section: SettingsSection;
  onSectionChange: (section: SettingsSection) => void;
  onSave: (settings: Settings) => void;
  /** Pre-fills the model search, e.g. from `/model claude`. */
  modelQuery?: string;
}

const SECTIONS: { id: SettingsSection; label: string }[] = [
  { id: "model", label: "Model" },
  { id: "appearance", label: "Appearance" },
  { id: "updates", label: "Updates" },
];

const POSITIONS: { id: ReplyPosition; icon: typeof AlignStartVertical; label: string }[] = [
  { id: "bottom-left", icon: AlignStartVertical, label: "Left" },
  { id: "bottom-center", icon: AlignCenterVertical, label: "Center" },
  { id: "bottom-right", icon: AlignEndVertical, label: "Right" },
];

const THEMES: { id: ThemeMode; label: string }[] = [
  { id: "auto", label: "Auto" },
  { id: "dark", label: "Dark" },
  { id: "light", label: "Light" },
  { id: "qt", label: "Qt / Matugen" },
];

const NOT_CHAT = /guard|moderat|safety|shield|classif/i;
const LABEL = "mb-1 block text-[10px] uppercase tracking-wide text-white/45";
const FIELD =
  "w-full rounded-[var(--radius-inner)] border border-white/10 bg-neutral-800 px-2.5 py-1.5 text-[12px] text-white focus:border-white/30 transition-colors";
const IDLE_BUTTON = "border-white/10 bg-neutral-800 text-white/60 hover:bg-neutral-700 hover:text-white";
const ACTIVE_BUTTON = "border-white bg-white font-medium text-black";

function profileFrom(settings: Settings): ProviderProfile {
  return settings.provider_profiles[settings.provider] ?? {
    api_key: settings.api_key,
    base_url: settings.base_url,
    model: settings.model,
  };
}

export default function SettingsPanel({ settings, section, onSectionChange, onSave, modelQuery = "" }: Props) {
  const normalizedSettings = normalizeSettings(settings);
  const [draft, setDraft] = useState<Settings>(normalizedSettings);
  const [showKey, setShowKey] = useState(false);
  const [fetching, setFetching] = useState(false);
  const [fetched, setFetched] = useState<string[]>([]);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [filter, setFilter] = useState(modelQuery);
  const [updateLine, setUpdateLine] = useState("");
  const [checkingUpdate, setCheckingUpdate] = useState(false);
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus | null>(null);
  const [updatingSource, setUpdatingSource] = useState(false);
  const [updateError, setUpdateError] = useState<string | null>(null);
  const [updateSuccess, setUpdateSuccess] = useState(false);
  const [prNumber, setPrNumber] = useState("");
  const [buildingPr, setBuildingPr] = useState(false);
  const tabsRef = useRef<HTMLDivElement>(null);

  useEffect(() => setDraft(normalizeSettings(settings)), [settings]);
  useEffect(() => {
    tabsRef.current?.querySelector<HTMLButtonElement>(`[data-section="${section}"]`)?.focus();
  }, [section]);
  useEffect(() => {
    void checkUpdates();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const checkUpdates = async () => {
    setCheckingUpdate(true);
    setUpdateError(null);
    try {
      setUpdateStatus(await checkForUpdates());
    } catch (err) {
      setUpdateError(String(err));
    } finally {
      setCheckingUpdate(false);
    }
  };

  // Updates run in the background. The Rust side streams lines and reports the result once.
  useEffect(() => {
    if (!inTauri) return;
    const unsubs: (() => void)[] = [];
    (async () => {
      unsubs.push(await listen<string>("update-progress", (event) => setUpdateLine(event.payload)));
      unsubs.push(
        await listen<UpdateEvent>("update-done", (event) => {
          setUpdatingSource(false);
          setBuildingPr(false);
          setUpdateLine("");
          if (event.payload.ok) setUpdateSuccess(true);
          else setUpdateError(event.payload.message);
        })
      );
    })();
    return () => unsubs.forEach((unsub) => unsub());
  }, []);

  const triggerUpdate = async () => {
    setUpdatingSource(true);
    setUpdateError(null);
    setUpdateSuccess(false);
    try {
      await updateFromSource();
    } catch (err) {
      setUpdateError(String(err));
      setUpdatingSource(false);
    }
  };

  const buildPullRequest = async () => {
    const number = Number(prNumber.trim());
    if (!Number.isSafeInteger(number) || number < 1) {
      setUpdateError("Invalid pull request.");
      return;
    }
    setBuildingPr(true);
    setUpdateError(null);
    setUpdateSuccess(false);
    try {
      await updateFromPr(number);
    } catch (err) {
      setUpdateError(String(err));
      setBuildingPr(false);
    }
  };

  const activeProfile = profileFrom(draft);
  const preset = PROVIDERS.find((provider) => provider.id === draft.provider) ?? PROVIDERS[0];
  const dirty = JSON.stringify(settingsForSave(draft)) !== JSON.stringify(normalizedSettings);

  const editProfile = (patch: Partial<ProviderProfile>) => {
    setDraft((current) => {
      const profile = { ...profileFrom(current), ...patch };
      return {
        ...current,
        ...profile,
        provider_profiles: { ...current.provider_profiles, [current.provider]: profile },
      };
    });
  };

  const pickProvider = (id: string) => {
    setDraft((current) => {
      const profiles = { ...current.provider_profiles };
      profiles[current.provider] = profileFrom(current);
      const next = profiles[id] ?? {
        api_key: "",
        base_url: PROVIDERS.find((provider) => provider.id === id)?.base_url ?? "",
        model: "",
      };
      profiles[id] = next;
      return { ...current, provider: id, ...next, provider_profiles: profiles };
    });
    setShowKey(false);
    setFetched([]);
    setFetchError(null);
    setFilter("");
  };

  const doFetch = async () => {
    setFetching(true);
    setFetchError(null);
    try {
      const list = (await fetchModels(draft.provider, activeProfile.base_url, activeProfile.api_key)).filter(
        (model) => !NOT_CHAT.test(model),
      );
      if (!list.length) setFetchError("No models.");
      else {
        setFetched(list);
        if (!activeProfile.model || !list.includes(activeProfile.model)) editProfile({ model: list[0] });
      }
    } catch (err) {
      setFetchError(String(err));
    } finally {
      setFetching(false);
    }
  };

  const shownModels = fetched.filter((model) => model.toLowerCase().includes(filter.toLowerCase()));

  return (
    <section className="settings-panel flex max-h-[min(520px,calc(100vh-32px))] flex-col" aria-label="Settings">
      <div
        ref={tabsRef}
        role="tablist"
        aria-label="Sections"
        className="grid shrink-0 grid-cols-3 gap-1.5 border-b border-white/10 p-2.5"
        onKeyDown={(event) => {
          if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
          event.preventDefault();
          const currentIndex = SECTIONS.findIndex((item) => item.id === section);
          const step = event.key === "ArrowRight" ? 1 : -1;
          onSectionChange(SECTIONS[(currentIndex + step + SECTIONS.length) % SECTIONS.length].id);
        }}
      >
        {SECTIONS.map(({ id, label }) => (
          <button
            key={id}
            type="button"
            data-section={id}
            role="tab"
            aria-selected={section === id}
            onClick={() => onSectionChange(id)}
            className={`rounded-[var(--radius-inner)] border px-2 py-1.5 text-[11px] transition-colors ${
              section === id ? ACTIVE_BUTTON : IDLE_BUTTON
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      <div className="settings-body min-h-0 flex-1 overflow-y-auto px-4 py-3.5">
        {section === "model" && (
          <div className="space-y-3">
            <div className="grid grid-cols-4 gap-1">
              {PROVIDERS.map((provider) => (
                <button
                  key={provider.id}
                  type="button"
                  onClick={() => pickProvider(provider.id)}
                  aria-pressed={draft.provider === provider.id}
                  className={`min-w-0 truncate rounded-[var(--radius-inner)] border px-1.5 py-1.5 text-[10.5px] transition-colors ${
                    draft.provider === provider.id ? ACTIVE_BUTTON : IDLE_BUTTON
                  }`}
                >
                  {provider.label}
                </button>
              ))}
            </div>

            {preset.needsKey && (
              <div>
                <label className={LABEL} htmlFor="provider-api-key">{preset.label} key</label>
                <div className="flex items-center gap-1.5 rounded-[var(--radius-inner)] border border-white/10 bg-neutral-800 px-2.5 py-1.5 focus-within:border-white/25">
                  <input
                    id="provider-api-key"
                    type={showKey ? "text" : "password"}
                    value={activeProfile.api_key}
                    onChange={(event) => editProfile({ api_key: event.target.value })}
                    autoComplete="off"
                    spellCheck={false}
                    className="min-w-0 flex-1 bg-transparent text-[12px] text-white"
                  />
                  <button
                    type="button"
                    onClick={() => setShowKey((shown) => !shown)}
                    aria-label={showKey ? "Hide key" : "Show key"}
                    className="rounded p-1 text-white/40 hover:text-white"
                  >
                    {showKey ? <EyeOff size={14} /> : <Eye size={14} />}
                  </button>
                </div>
              </div>
            )}

            {(draft.provider === "custom" || draft.provider === "openrouter" || draft.provider === "ollama") && (
              <div>
                <label className={LABEL} htmlFor="provider-base-url">URL</label>
                <input
                  id="provider-base-url"
                  value={activeProfile.base_url}
                  onChange={(event) => editProfile({ base_url: event.target.value })}
                  spellCheck={false}
                  className={FIELD}
                />
              </div>
            )}

            <div>
              <div className="mb-1 flex items-end justify-between gap-2">
                <label className={LABEL} htmlFor="provider-model">Model</label>
                <button
                  type="button"
                  onClick={() => void doFetch()}
                  disabled={fetching}
                  aria-label="Fetch models"
                  className="mb-1 grid h-6 w-6 place-items-center rounded-[var(--radius-control)] text-white/50 hover:bg-white/5 hover:text-white disabled:opacity-50"
                >
                  <RefreshCw size={12} className={fetching ? "animate-spin" : ""} />
                </button>
              </div>
              <input
                id="provider-model"
                value={activeProfile.model}
                onChange={(event) => editProfile({ model: event.target.value })}
                spellCheck={false}
                className={`${FIELD} font-mono`}
              />
              {fetchError && <p className="mt-1 text-[10px] text-rose-400">{fetchError}</p>}
              {fetched.length > 0 && (
                <div className="mt-1.5 rounded-[var(--radius-inner)] border border-white/10 bg-neutral-900 p-1.5">
                  <div className="mb-1 flex items-center gap-1.5 rounded-[var(--radius-control)] bg-neutral-800 px-2">
                    <Search size={11} className="text-white/35" />
                    <input
                      value={filter}
                      onChange={(event) => setFilter(event.target.value)}
                      placeholder="Filter"
                      aria-label="Filter models"
                      className="w-full bg-transparent py-1 text-[10.5px] text-white placeholder:text-white/30"
                    />
                  </div>
                  <div className="max-h-24 overflow-y-auto">
                    {shownModels.slice(0, 40).map((model) => (
                      <button
                        key={model}
                        type="button"
                        onClick={() => editProfile({ model })}
                        className={`block w-full truncate rounded px-2 py-1 text-left font-mono text-[10px] ${
                          activeProfile.model === model ? "bg-white text-black" : "text-white/60 hover:bg-neutral-800"
                        }`}
                      >
                        {model}
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div className="flex items-center gap-3 border-t border-white/10 pt-2">
              <label className="text-[10px] text-white/45" htmlFor="provider-token-limit">Tokens</label>
              <input
                id="provider-token-limit"
                type="number"
                min={128}
                max={32768}
                step={128}
                value={draft.max_tokens}
                onChange={(event) => setDraft({ ...draft, max_tokens: Math.max(128, Number(event.target.value) || 128) })}
                className={`${FIELD} min-w-0 flex-1 text-right font-mono [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none`}
              />
            </div>
          </div>
        )}

        {section === "appearance" && (
          <div className="space-y-3">
            <div className="grid grid-cols-4 gap-1">
              {THEMES.map(({ id, label }) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setDraft({ ...draft, theme: id })}
                  aria-pressed={(draft.theme ?? "auto") === id}
                  className={`rounded-[var(--radius-inner)] border px-1.5 py-2 text-[10.5px] transition-colors ${
                    (draft.theme ?? "auto") === id ? ACTIVE_BUTTON : IDLE_BUTTON
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-3 border-t border-white/10 pt-2">
              <label className="text-[10px] text-white/45" htmlFor="overlay-opacity">Opacity</label>
              <input
                id="overlay-opacity"
                type="range"
                min={25}
                max={100}
                step={1}
                value={draft.bg_opacity ?? 100}
                onChange={(event) => setDraft({ ...draft, bg_opacity: Number(event.target.value) })}
                className="h-1.5 min-w-0 flex-1 cursor-pointer appearance-none rounded-[var(--radius-inner)] bg-neutral-700 accent-white"
              />
              <span className="w-9 text-right font-mono text-[10px] text-white/50">{draft.bg_opacity ?? 100}%</span>
            </div>

            <div>
              <p className={LABEL}>Position</p>
              <div className="grid grid-cols-3 gap-1">
                {POSITIONS.map(({ id, icon: Icon, label }) => (
                  <button
                    key={id}
                    type="button"
                    onClick={() => setDraft({ ...draft, position: id })}
                    aria-label={label}
                    aria-pressed={draft.position === id}
                    className={`flex items-center justify-center gap-1.5 rounded-[var(--radius-inner)] border py-1.5 text-[10px] transition-colors ${
                      draft.position === id ? ACTIVE_BUTTON : IDLE_BUTTON
                    }`}
                  >
                    <Icon size={13} />{label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {section === "updates" && (
          <div className="space-y-2">
            <div className="flex items-center gap-1.5">
              <span className="font-mono text-[10.5px] text-white/65">
                {updateStatus?.current_version || (checkingUpdate ? "…" : "—")}
              </span>
              <span className={`flex-1 text-right text-[10px] ${updateStatus?.update_available ? "text-amber-300" : "text-white/40"}`}>
                {updateStatus?.update_available ? "Available" : updateStatus ? "Current" : ""}
              </span>
              <button
                type="button"
                onClick={() => void checkUpdates()}
                disabled={checkingUpdate || updatingSource || buildingPr}
                aria-label="Check for updates"
                className="grid h-7 w-7 place-items-center rounded-[var(--radius-control)] text-white/45 hover:bg-white/5 hover:text-white disabled:opacity-50"
              >
                <RefreshCw size={12} className={checkingUpdate ? "animate-spin" : ""} />
              </button>
              {updateSuccess ? (
                <button
                  type="button"
                  onClick={() => void restartApp()}
                  aria-label="Restart"
                  className="grid h-7 w-7 place-items-center rounded-[var(--radius-control)] bg-white text-black"
                >
                  <RefreshCw size={12} />
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => void triggerUpdate()}
                  disabled={checkingUpdate || updatingSource || buildingPr}
                  aria-label={updatingSource ? "Updating" : "Update"}
                  className="grid h-7 w-7 place-items-center rounded-[var(--radius-control)] bg-white text-black disabled:opacity-50"
                >
                  {updatingSource ? <RefreshCw size={12} className="animate-spin" /> : <Download size={12} />}
                </button>
              )}
            </div>

            <details className="rounded-[var(--radius-inner)] border border-white/10 px-2.5 py-2 text-[10.5px] text-white/55">
              <summary className="cursor-pointer">PR</summary>
              <div className="mt-2 flex gap-1.5">
                <input
                  type="number"
                  min={1}
                  step={1}
                  value={prNumber}
                  onChange={(event) => setPrNumber(event.target.value)}
                  placeholder="#"
                  aria-label="Pull request number"
                  className={`${FIELD} min-w-0 flex-1`}
                  disabled={buildingPr || updatingSource || checkingUpdate}
                />
                <button
                  type="button"
                  onClick={() => void buildPullRequest()}
                  disabled={!prNumber.trim() || buildingPr || updatingSource || checkingUpdate}
                  aria-label="Build pull request"
                  className="grid h-8 w-8 shrink-0 place-items-center rounded-[var(--radius-inner)] border border-white/10 bg-neutral-800 text-white/60 disabled:opacity-50"
                >
                  {buildingPr ? <RefreshCw size={12} className="animate-spin" /> : <GitPullRequest size={13} />}
                </button>
              </div>
              <p className="mt-1.5 text-[9px]">Runs PR code.</p>
            </details>

            {updateLine && (updatingSource || buildingPr) && (
              <p className="truncate font-mono text-[10px] text-white/45" title={updateLine}>{updateLine}</p>
            )}
            {updateError && <p className="break-words text-[10px] text-rose-400">{updateError}</p>}
          </div>
        )}
      </div>

      {dirty && (
        <footer className="flex shrink-0 justify-end border-t border-white/10 px-4 py-2.5">
          <button
            type="button"
            onClick={() => onSave(settingsForSave(draft))}
            className="accent-action rounded-[var(--radius-inner)] px-3 py-1.5 text-[11px] font-semibold"
          >
            Save
          </button>
        </footer>
      )}
    </section>
  );
}

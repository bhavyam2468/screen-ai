import { useEffect, useRef, useState } from "react";
import {
  AlignCenterVertical,
  AlignEndVertical,
  AlignStartVertical,
  Check,
  Download,
  Eye,
  EyeOff,
  GitPullRequest,
  KeyRound,
  Moon,
  Palette,
  Power,
  RefreshCw,
  Search,
  Settings2,
  Sun,
  SunMoon,
  X,
} from "lucide-react";
import {
  PROVIDERS,
  ProviderProfile,
  ReplyPosition,
  Settings,
  SettingsSection,
  SystemTheme,
  ThemeMode,
  UpdateStatus,
  normalizeSettings,
  quitApp,
  fetchModels,
  checkForUpdates,
  updateFromSource,
  updateFromPr,
  restartApp,
  settingsForSave,
} from "../lib/store";

interface Props {
  settings: Settings;
  section: SettingsSection;
  systemTheme: SystemTheme;
  onSectionChange: (section: SettingsSection) => void;
  onSave: (settings: Settings) => void;
  onClose: () => void;
}

const SECTIONS: { id: SettingsSection; label: string; hint: string; icon: typeof Settings2 }[] = [
  { id: "model", label: "Model", hint: "Provider, key & model", icon: KeyRound },
  { id: "appearance", label: "Appearance", hint: "Theme & position", icon: Palette },
  { id: "updates", label: "Updates", hint: "Check & install", icon: Download },
];

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

const NOT_CHAT = /guard|moderat|safety|shield|classif/i;
const LABEL = "text-[10.5px] uppercase tracking-[0.14em] text-white/45 mb-1.5 font-semibold";
const FIELD =
  "w-full rounded-lg bg-neutral-800 border border-white/10 px-3 py-2 text-[13px] placeholder:text-white/25 text-white focus:border-white/30 transition-colors";
const IDLE_BUTTON =
  "bg-neutral-800 border border-white/10 text-white/60 hover:text-white hover:bg-neutral-700";
const ACTIVE_BUTTON = "bg-white text-black font-semibold border-white";

function profileFrom(settings: Settings): ProviderProfile {
  return settings.provider_profiles[settings.provider] ?? {
    api_key: settings.api_key,
    base_url: settings.base_url,
    model: settings.model,
  };
}

export default function SettingsPanel({
  settings,
  section,
  systemTheme,
  onSectionChange,
  onSave,
  onClose,
}: Props) {
  const normalizedSettings = normalizeSettings(settings);
  const [draft, setDraft] = useState<Settings>(normalizedSettings);
  const [showKey, setShowKey] = useState(false);
  const [fetching, setFetching] = useState(false);
  const [fetched, setFetched] = useState<string[]>([]);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");
  const tabsRef = useRef<HTMLDivElement>(null);

  const [checkingUpdate, setCheckingUpdate] = useState(false);
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus | null>(null);
  const [updatingSource, setUpdatingSource] = useState(false);
  const [updateError, setUpdateError] = useState<string | null>(null);
  const [updateSuccess, setUpdateSuccess] = useState(false);
  const [updateMessage, setUpdateMessage] = useState<string | null>(null);
  const [prNumber, setPrNumber] = useState("");
  const [buildingPr, setBuildingPr] = useState(false);

  useEffect(() => setDraft(normalizeSettings(settings)), [settings]);
  useEffect(() => {
    tabsRef.current?.querySelector<HTMLButtonElement>(`[data-section="${section}"]`)?.focus();
  }, [section]);
  useEffect(() => {
    checkUpdates();
    // Initial status should be fetched once when the settings surface opens.
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

  const triggerUpdate = async () => {
    setUpdatingSource(true);
    setUpdateError(null);
    setUpdateMessage(null);
    try {
      setUpdateMessage(await updateFromSource());
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
      setUpdateMessage(await updateFromPr(number));
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
      if (!list.length) {
        setFetchError("No models returned by this provider.");
      } else {
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
  const submitSettings = () => {
    if (dirty) onSave(settingsForSave(draft));
    else onClose();
  };

  return (
    <section className="settings-panel flex flex-col max-h-[min(620px,calc(100vh-44px))]" aria-label="Settings">
      <header className="flex items-center justify-between gap-3 px-4 pt-3 pb-2 shrink-0">
        <div className="min-w-0">
          <p className="text-[12px] font-semibold tracking-[0.16em] uppercase text-white">Settings</p>
          <p className="mt-0.5 text-[10.5px] text-white/40">Saved on this device · <kbd>Ctrl ,</kbd> to toggle</p>
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => void quitApp()}
            aria-label="Quit Screen AI"
            title="Quit Screen AI"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-white/45 hover:text-rose-400 hover:bg-rose-500/10 transition-colors"
          >
            <Power size={13} />
          </button>
          <button
            onClick={onClose}
            aria-label="Close settings"
            title="Close settings"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-white/45 hover:text-white hover:bg-white/5 transition-colors"
          >
            <X size={14} />
          </button>
        </div>
      </header>

      <div
        ref={tabsRef}
        role="tablist"
        aria-label="Settings sections"
        className="grid grid-cols-3 gap-1.5 px-3.5 pb-2.5 shrink-0"
        onKeyDown={(event) => {
          if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
          event.preventDefault();
          const currentIndex = SECTIONS.findIndex((item) => item.id === section);
          const step = event.key === "ArrowRight" ? 1 : -1;
          const next = SECTIONS[(currentIndex + step + SECTIONS.length) % SECTIONS.length];
          onSectionChange(next.id);
        }}
      >
        {SECTIONS.map(({ id, label, hint, icon: Icon }) => (
          <button
            key={id}
            type="button"
            data-section={id}
            role="tab"
            aria-selected={section === id}
            onClick={() => onSectionChange(id)}
            className={`group flex min-w-0 items-center gap-2 rounded-xl border px-2.5 py-2 text-left transition-colors duration-150 ${
              section === id ? ACTIVE_BUTTON : IDLE_BUTTON
            }`}
          >
            <Icon size={15} className="shrink-0" />
            <span className="min-w-0">
              <span className="block truncate text-[11.5px] leading-tight">{label}</span>
              <span className="mt-0.5 hidden truncate text-[9px] opacity-55 sm:block">{hint}</span>
            </span>
          </button>
        ))}
      </div>

      <div className="settings-body min-h-0 flex-1 overflow-y-auto px-3.5 pb-3">
        {section === "model" && (
          <div className="space-y-3.5">
            <div>
              <div className="mb-2 flex items-end justify-between gap-3">
                <div>
                  <p className={LABEL}>Provider profile</p>
                  <p className="text-[10.5px] text-white/40">Each provider remembers its own key and model.</p>
                </div>
                <span className="shrink-0 rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[10px] text-white/50">
                  {Object.values(draft.provider_profiles).filter((profile) => profile.api_key.trim()).length} keys saved
                </span>
              </div>
              <div className="grid grid-cols-3 gap-1.5">
                {PROVIDERS.map((provider) => (
                  <button
                    key={provider.id}
                    type="button"
                    onClick={() => pickProvider(provider.id)}
                    aria-pressed={draft.provider === provider.id}
                    className={`min-w-0 rounded-lg border px-2.5 py-2 text-left text-[11.5px] transition-colors ${
                      draft.provider === provider.id ? ACTIVE_BUTTON : IDLE_BUTTON
                    }`}
                  >
                    <span className="block truncate font-medium">{provider.label}</span>
                    <span className="mt-0.5 block truncate text-[9.5px] opacity-55">
                      {draft.provider_profiles[provider.id]?.api_key ? "Key saved" : provider.needsKey ? "No key yet" : "Local"}
                    </span>
                  </button>
                ))}
              </div>
            </div>

            {preset.needsKey ? (
              <div>
                <label className={LABEL} htmlFor="provider-api-key">{preset.label} API key</label>
                <div className="flex items-center gap-2 rounded-lg border border-white/10 bg-neutral-800 px-3 py-2 transition-colors focus-within:border-white/25">
                  <input
                    id="provider-api-key"
                    type={showKey ? "text" : "password"}
                    value={activeProfile.api_key}
                    onChange={(event) => editProfile({ api_key: event.target.value })}
                    placeholder={`Paste your ${preset.label} key…`}
                    autoComplete="off"
                    spellCheck={false}
                    className="min-w-0 flex-1 bg-transparent text-[13px] text-white placeholder:text-white/25"
                  />
                  <button
                    type="button"
                    onClick={() => setShowKey((shown) => !shown)}
                    aria-label={showKey ? "Hide API key" : "Show API key"}
                    className="shrink-0 rounded-md p-1 text-white/40 transition-colors hover:text-white"
                  >
                    {showKey ? <EyeOff size={15} /> : <Eye size={15} />}
                  </button>
                </div>
                <p className="mt-1.5 text-[10px] text-white/35">Kept in Screen AI’s local config. It is not sent anywhere until you use this provider.</p>
              </div>
            ) : (
              <div className="rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-[11px] text-white/50">
                Ollama is local and does not need an API key.
              </div>
            )}

            {(draft.provider === "custom" || draft.provider === "openrouter" || draft.provider === "ollama") && (
              <div>
                <label className={LABEL} htmlFor="provider-base-url">Base URL</label>
                <input
                  id="provider-base-url"
                  value={activeProfile.base_url}
                  onChange={(event) => editProfile({ base_url: event.target.value })}
                  placeholder="https://…"
                  spellCheck={false}
                  className={FIELD}
                />
              </div>
            )}

            <div>
              <div className="mb-1.5 flex items-center justify-between gap-2">
                <label className={LABEL} htmlFor="provider-model">Model ID</label>
                <button
                  type="button"
                  onClick={() => void doFetch()}
                  disabled={fetching}
                  className="flex shrink-0 items-center gap-1.5 rounded-md border border-white/15 bg-neutral-800 px-2.5 py-1 text-[10.5px] text-white/70 transition-colors hover:bg-neutral-700 hover:text-white disabled:opacity-50"
                >
                  <RefreshCw size={11} className={fetching ? "animate-spin" : ""} />
                  {fetching ? "Fetching…" : "Fetch models"}
                </button>
              </div>
              <input
                id="provider-model"
                value={activeProfile.model}
                onChange={(event) => editProfile({ model: event.target.value })}
                placeholder="e.g. gpt-4o-mini"
                spellCheck={false}
                className={`${FIELD} font-mono`}
              />
              {fetchError && <p className="mt-1.5 rounded-lg border border-rose-500/20 bg-rose-500/10 p-2 text-[10.5px] text-rose-400">{fetchError}</p>}
              {fetched.length > 0 && (
                <div className="mt-2 space-y-1.5 rounded-lg border border-white/10 bg-neutral-900 p-2">
                  <div className="flex items-center gap-1.5 rounded-md border border-white/10 bg-neutral-800 px-2 py-1">
                    <Search size={12} className="text-white/35" />
                    <input
                      value={filter}
                      onChange={(event) => setFilter(event.target.value)}
                      placeholder="Filter models…"
                      aria-label="Filter models"
                      className="w-full bg-transparent text-[11px] text-white placeholder:text-white/25"
                    />
                    <span className="text-[10px] text-white/40">{shownModels.length}</span>
                  </div>
                  <div className="max-h-28 space-y-1 overflow-y-auto pr-1">
                    {shownModels.slice(0, 40).map((model) => (
                      <button
                        key={model}
                        type="button"
                        onClick={() => editProfile({ model })}
                        className={`block w-full truncate rounded-md px-2.5 py-1.5 text-left font-mono text-[10.5px] transition-colors ${
                          activeProfile.model === model ? ACTIVE_BUTTON : "text-white/60 hover:bg-neutral-800 hover:text-white"
                        }`}
                      >
                        {model}
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div className="grid grid-cols-[1fr_112px] items-center gap-3 rounded-xl border border-white/10 bg-white/5 px-3 py-2.5">
              <div>
                <p className="text-[11.5px] font-medium text-white/80">Response limit</p>
                <p className="mt-0.5 text-[10px] text-white/40">Maximum output tokens per answer.</p>
              </div>
              <input
                type="number"
                min={128}
                max={32768}
                step={128}
                value={draft.max_tokens}
                onChange={(event) => setDraft({ ...draft, max_tokens: Math.max(128, Number(event.target.value) || 128) })}
                aria-label="Maximum response tokens"
                className={`${FIELD} px-2 py-1.5 text-right font-mono text-[11.5px]`}
              />
            </div>
          </div>
        )}

        {section === "appearance" && (
          <div className="space-y-4">
            <div>
              <p className={LABEL}>Color system</p>
              <div className="grid grid-cols-4 gap-1.5">
                {THEMES.map(({ id, icon: Icon, label }) => (
                  <button
                    key={id}
                    type="button"
                    onClick={() => setDraft({ ...draft, theme: id })}
                    aria-pressed={(draft.theme ?? "auto") === id}
                    title={id === "qt" ? "Use the detected KDE, qt5ct, or qt6ct palette" : label}
                    className={`flex min-w-0 flex-col items-center justify-center gap-1.5 rounded-xl border py-2.5 transition-colors ${
                      (draft.theme ?? "auto") === id ? ACTIVE_BUTTON : IDLE_BUTTON
                    }`}
                  >
                    <Icon size={16} />
                    <span className="truncate text-[10.5px]">{label}</span>
                  </button>
                ))}
              </div>
              {draft.theme === "qt" ? (
                <p className="mt-2 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-[10.5px] leading-relaxed text-white/45">
                  {systemTheme.palette?.name
                    ? `Following “${systemTheme.palette.name}”. Qt/KDE and Matugen colors refresh when the overlay opens.`
                    : systemTheme.palette
                      ? "A Qt palette was detected and refreshes when the overlay opens."
                      : "No KDE or qt5ct/qt6ct palette was detected. Qt mode falls back to your desktop mode and accent."}
                </p>
              ) : (
                <p className="mt-2 text-[10.5px] leading-relaxed text-white/40">Auto follows the desktop mode. Qt / Matugen maps detected Qt palette colors into Screen AI.</p>
              )}
            </div>

            <div className="rounded-xl border border-white/10 bg-white/5 p-3">
              <div className="mb-2 flex items-center justify-between gap-3">
                <div>
                  <p className="text-[11.5px] font-medium text-white/80">Overlay opacity</p>
                  <p className="mt-0.5 text-[10px] text-white/40">Keep the captured screen visible behind the panel.</p>
                </div>
                <span className="rounded-md bg-neutral-800 px-2 py-1 font-mono text-[10.5px] text-white/60">{draft.bg_opacity ?? 100}%</span>
              </div>
              <input
                type="range"
                min={25}
                max={100}
                step={1}
                value={draft.bg_opacity ?? 100}
                onChange={(event) => setDraft({ ...draft, bg_opacity: Number(event.target.value) })}
                aria-label="Overlay opacity"
                className="h-1.5 w-full cursor-pointer appearance-none rounded-lg bg-neutral-700 accent-white"
              />
            </div>

            <div>
              <p className={LABEL}>Input bar position</p>
              <div className="grid grid-cols-3 gap-1.5">
                {POSITIONS.map(({ id, icon: Icon, label }) => (
                  <button
                    key={id}
                    type="button"
                    onClick={() => setDraft({ ...draft, position: id })}
                    aria-pressed={draft.position === id}
                    className={`flex flex-col items-center justify-center gap-1.5 rounded-xl border py-2.5 transition-colors ${
                      draft.position === id ? ACTIVE_BUTTON : IDLE_BUTTON
                    }`}
                  >
                    <Icon size={16} />
                    <span className="text-[10.5px]">{label}</span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {section === "updates" && (
          <div className="space-y-3.5">
            <div className="rounded-xl border border-white/10 bg-white/5 p-3">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className={LABEL}>Source build</p>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-mono text-[11.5px] text-white/85">
                      {updateStatus?.current_version || (checkingUpdate ? "Checking…" : "Version unavailable")}
                    </span>
                    <span className={`rounded border px-1.5 py-0.5 text-[9.5px] ${
                      updateStatus?.update_available
                        ? "border-amber-500/25 bg-amber-500/15 text-amber-300"
                        : "border-white/10 bg-white/5 text-white/45"
                    }`}>
                      {updateStatus?.update_available ? "Update available" : updateStatus ? "Up to date" : checkingUpdate ? "Checking" : "Status unavailable"}
                    </span>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => void checkUpdates()}
                  disabled={checkingUpdate || updatingSource || buildingPr}
                  aria-label="Check for updates"
                  className="flex shrink-0 items-center gap-1.5 rounded-lg border border-white/10 bg-neutral-800 px-2.5 py-1.5 text-[10.5px] text-white/60 transition-colors hover:border-white/25 hover:text-white disabled:opacity-50"
                >
                  <RefreshCw size={11} className={checkingUpdate ? "animate-spin" : ""} />
                  Check
                </button>
              </div>
              {updateStatus?.update_available && (
                <div className="mt-2 rounded-lg border border-amber-300/10 bg-amber-400/[0.06] p-2.5">
                  <p className="break-words text-[10.5px] leading-relaxed text-white/70">{updateStatus.latest_message}</p>
                  <p className="mt-1 font-mono text-[9.5px] text-white/40">main · {updateStatus.latest_sha.slice(0, 8)}</p>
                </div>
              )}
              {updateSuccess ? (
                <div className="mt-2.5 space-y-2">
                  <p className="text-[10.5px] text-emerald-300">Build complete. Restart Screen AI to apply it.</p>
                  <button type="button" onClick={() => void doRestart()} className="accent-action flex w-full items-center justify-center gap-1.5 rounded-lg py-2 text-[11.5px] font-semibold transition-colors">
                    <RefreshCw size={12} /> Restart app
                  </button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => void triggerUpdate()}
                  disabled={checkingUpdate || updatingSource || buildingPr}
                  className="accent-action mt-2.5 flex w-full items-center justify-center gap-1.5 rounded-lg py-2 text-[11.5px] font-semibold transition-colors disabled:opacity-50"
                >
                  {updatingSource ? <RefreshCw size={12} className="animate-spin" /> : <Download size={12} />}
                  {updatingSource ? "Pulling and building on this device…" : updateStatus?.update_available ? "Pull & build update" : "Pull & rebuild latest"}
                </button>
              )}
              <p className="mt-2 text-[9.5px] leading-relaxed text-white/35">Updates pull GitHub source and compile locally; no prebuilt binary is downloaded.</p>
            </div>

            {!updateSuccess && (
              <div className="rounded-xl border border-white/10 bg-neutral-900 p-3">
                <p className={LABEL}>Build a pull request</p>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    min={1}
                    step={1}
                    value={prNumber}
                    onChange={(event) => setPrNumber(event.target.value)}
                    placeholder="PR number"
                    aria-label="Screen AI pull request number"
                    className={`${FIELD} min-w-0 flex-1`}
                    disabled={buildingPr || updatingSource || checkingUpdate}
                  />
                  <button
                    type="button"
                    onClick={() => void buildPullRequest()}
                    disabled={!prNumber.trim() || buildingPr || updatingSource || checkingUpdate}
                    className="flex shrink-0 items-center gap-1.5 rounded-lg border border-white/10 bg-neutral-800 px-3 py-2 text-[10.5px] text-white/75 transition-colors hover:border-white/25 hover:text-white disabled:opacity-50"
                  >
                    {buildingPr ? <RefreshCw size={12} className="animate-spin" /> : <GitPullRequest size={13} />}
                    {buildingPr ? "Building…" : "Build PR"}
                  </button>
                </div>
                <p className="mt-2 text-[9.5px] leading-relaxed text-white/35">Only build PRs you trust: this runs their source build scripts locally.</p>
              </div>
            )}

            {updateMessage && <p className="rounded-lg border border-emerald-500/15 bg-emerald-500/5 p-2 text-[10px] text-emerald-300/80">{updateMessage}</p>}
            {updateError && <p className="break-words rounded-lg border border-rose-500/20 bg-rose-500/10 p-2 text-[10.5px] text-rose-400">{updateError}</p>}
          </div>
        )}
      </div>

      <footer className="flex shrink-0 items-center gap-2 border-t border-white/10 px-3.5 py-2.5">
        <span className="min-w-0 flex-1 truncate text-[10px] text-white/35">
          {section === "model" ? `${preset.label} · ${activeProfile.model || "No model selected"}` : section === "appearance" ? "Theme and layout preferences" : "Local source updater"}
        </span>
        <button
          type="button"
          onClick={submitSettings}
          className={`flex items-center justify-center gap-1.5 rounded-lg px-3.5 py-2 text-[11.5px] transition-colors ${
            dirty ? "accent-action font-semibold" : "border border-white/10 bg-neutral-800 text-white/60 hover:text-white"
          }`}
        >
          <Check size={13} /> {dirty ? "Save changes" : "Done"}
        </button>
      </footer>
    </section>
  );
}

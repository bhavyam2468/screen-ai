import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { X, Copy, Check, RotateCcw, ArrowDown } from "lucide-react";

export interface Msg {
  role: "user" | "assistant";
  text: string;
}

interface Props {
  messages: Msg[];
  streaming: boolean;
  error: string | null;
  model: string;
  onClose: () => void;
  onRetry: () => void;
}

const MD_COMPONENTS: any = {
  h1: ({ node, ...p }: any) => (
    <h1 className="text-[18px] font-bold text-white tracking-tight mt-4 mb-2 pb-1.5 border-b border-white/10" {...p} />
  ),
  h2: ({ node, ...p }: any) => (
    <h2 className="text-[16px] font-bold text-white tracking-tight mt-3.5 mb-1.5" {...p} />
  ),
  h3: ({ node, ...p }: any) => (
    <h3 className="text-[14.5px] font-bold text-white tracking-tight mt-3 mb-1" {...p} />
  ),
  h4: ({ node, ...p }: any) => (
    <h4 className="text-[13.5px] font-bold text-white/95 mt-2 mb-1" {...p} />
  ),
  h5: ({ node, ...p }: any) => (
    <h5 className="text-[13px] font-bold text-white/90 mt-2 mb-1" {...p} />
  ),
  h6: ({ node, ...p }: any) => (
    <h6 className="text-[12.5px] font-bold text-white/85 mt-2 mb-1 uppercase tracking-wider" {...p} />
  ),
  strong: ({ node, ...p }: any) => (
    <strong className="font-bold text-white" {...p} />
  ),
  b: ({ node, ...p }: any) => (
    <b className="font-bold text-white" {...p} />
  ),
  em: ({ node, ...p }: any) => (
    <em className="italic text-white/95" {...p} />
  ),
  i: ({ node, ...p }: any) => (
    <i className="italic text-white/95" {...p} />
  ),
  p: ({ node, ...p }: any) => (
    <p className="my-2 leading-[1.7] text-white/90 first:mt-0 last:mb-0" {...p} />
  ),
  hr: ({ node, ...p }: any) => (
    <hr className="my-3 border-white/10" {...p} />
  ),
  li: ({ node, ...p }: any) => (
    <li className="my-0.5 text-white/90 leading-relaxed" {...p} />
  ),
  table: ({ node, ...p }: any) => (
    <div className="my-2.5 overflow-x-auto rounded-lg border border-white/15">
      <table className="w-full text-[12.5px] border-collapse font-sans" {...p} />
    </div>
  ),
  thead: ({ node, ...p }: any) => (
    <thead className="bg-neutral-800 text-white font-semibold" {...p} />
  ),
  th: ({ node, ...p }: any) => (
    <th className="px-3 py-1.5 text-left font-bold border-b border-r border-white/15 last:border-r-0" {...p} />
  ),
  td: ({ node, ...p }: any) => (
    <td className="px-3 py-1.5 border-t border-r border-white/10 last:border-r-0 text-white/80" {...p} />
  ),
  pre: ({ node, ...p }: any) => (
    <pre className="my-2 p-3 rounded-lg bg-neutral-900 border border-white/15 overflow-x-auto text-[12px] leading-relaxed text-white/90 font-mono" {...p} />
  ),
  code: ({ node, inline, className, ...p }: any) =>
    inline ? (
      <code className="px-1.5 py-0.5 rounded bg-neutral-800 border border-white/15 text-[11.5px] text-white/95 font-mono" {...p} />
    ) : (
      <code className={`font-mono ${className ?? ""}`} {...p} />
    ),
  ul: ({ node, ...p }: any) => <ul className="list-disc pl-5 space-y-1 my-2" {...p} />,
  ol: ({ node, ...p }: any) => <ol className="list-decimal pl-5 space-y-1 my-2" {...p} />,
  blockquote: ({ node, ...p }: any) => (
    <blockquote className="border-l-2 border-white/40 pl-3 my-2 text-white/75 italic" {...p} />
  ),
  a: ({ node, ...p }: any) => (
    <a className="md-link underline underline-offset-2 transition-colors" target="_blank" rel="noreferrer" {...p} />
  ),
};

function MsgIn({
  className,
  reduced,
  children,
}: {
  className?: string;
  reduced: boolean;
  children: React.ReactNode;
}) {
  return (
    <motion.div
      className={className}
      initial={reduced ? false : { opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={reduced ? { duration: 0 } : { duration: 0.16, ease: "easeOut" }}
    >
      {children}
    </motion.div>
  );
}

export default function ChatPanel({ messages, streaming, error, model, onClose, onRetry }: Props) {
  const [copied, setCopied] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const pinnedRef = useRef(true);
  const [canUp, setCanUp] = useState(false);
  const [canDown, setCanDown] = useState(false);
  const reduced = useReducedMotion() ?? false;

  const onScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    const gap = el.scrollHeight - el.scrollTop - el.clientHeight;
    pinnedRef.current = gap < 48;
    setCanUp(el.scrollTop > 24);
    setCanDown(gap > 24);
  };

  // Follow the stream only while pinned to the bottom — never yank the user.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    if (pinnedRef.current) el.scrollTop = el.scrollHeight;
    onScroll();
  }, [messages, error]);

  const jumpToLatest = () => {
    const el = scrollRef.current;
    if (!el) return;
    pinnedRef.current = true;
    el.scrollTo({ top: el.scrollHeight, behavior: reduced ? "auto" : "smooth" });
    setCanDown(false);
  };

  const last = [...messages].reverse().find((m) => m.role === "assistant" && m.text);

  const copy = async () => {
    if (!last) return;
    try {
      await navigator.clipboard.writeText(last.text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    } catch {
      /* clipboard unavailable */
    }
  };

  const btn =
    "w-6 h-6 rounded-md flex items-center justify-center text-white/40 hover:text-white transition-colors";

  return (
    <div className="flex flex-col">
      <div className="flex items-center gap-2 px-3.5 pt-2.5 pb-2 shrink-0">
        <span className="relative flex w-1.5 h-1.5">
          {streaming && (
            <span className="absolute inline-flex w-full h-full rounded-full bg-blue-300/35" />
          )}
          <span
            className={`relative inline-flex w-1.5 h-1.5 rounded-full transition-colors duration-300 ${
              streaming ? "bg-white" : error ? "bg-rose-400" : "bg-emerald-400"
            }`}
          />
        </span>
        <span className="text-[11px] text-white/40 truncate">{model}</span>
        <div className="flex-1" />
        {error && !streaming && (
          <button onClick={onRetry} aria-label="Retry response" className={btn}>
            <RotateCcw size={13} />
          </button>
        )}
        {last && (
          <button onClick={copy} aria-label="Copy latest response" className={btn}>
            {copied ? <Check size={13} className="text-emerald-400" /> : <Copy size={13} />}
          </button>
        )}
        <button onClick={onClose} aria-label="Close chat" className={btn}>
          <X size={14} />
        </button>
      </div>

      <div className="relative">
      <div
        ref={scrollRef}
        onScroll={onScroll}
        className={`chat-scroll px-3.5 pb-3 overflow-y-auto space-y-3 max-h-[min(520px,calc(100vh-160px))]${canUp ? " mask-top" : ""}${canDown ? " mask-bottom" : ""}`}
      >
        {messages.map((m, i) => {
          const isLast = i === messages.length - 1;
          if (m.role === "user") {
            return (
              <MsgIn key={i} className="flex justify-end" reduced={reduced}>
                <div className="max-w-[85%] rounded-xl bg-neutral-800 border border-white/10 px-3 py-1.5 text-[13px] text-white/90 select-text break-words">
                  {m.text}
                </div>
              </MsgIn>
            );
          }
          if (!m.text) {
            if (isLast && error) {
              return (
                <p key={i} className="text-[12.5px] text-rose-300/90 leading-relaxed select-text">
                  {error}
                </p>
              );
            }
            return (
              <MsgIn key={i} className="space-y-2 py-1" reduced={reduced}>
                {[88, 70, 52].map((w, k) => (
                  <div key={k} className="skeleton" style={{ width: `${w}%` }} />
                ))}
              </MsgIn>
            );
          }
          return (
            <MsgIn key={i} className={isLast && streaming ? "stream-cursor" : ""} reduced={reduced}>
              <ReactMarkdown remarkPlugins={[remarkGfm]} className="md-body" components={MD_COMPONENTS}>
                {m.text}
              </ReactMarkdown>
              {isLast && error && (
                <p className="mt-2 text-[12.5px] text-rose-300/90 select-text">{error}</p>
              )}
            </MsgIn>
          );
        })}
      </div>
      <AnimatePresence>
        {canDown && (
          <motion.button
            onClick={jumpToLatest}
            initial={{ opacity: 0, y: 8, x: "-50%" }}
            animate={{ opacity: 1, y: 0, x: "-50%" }}
            exit={{ opacity: 0, y: 8, x: "-50%" }}
            transition={{ duration: reduced ? 0 : 0.16, ease: "easeOut" }}
            className="absolute bottom-2 left-1/2 w-7 h-7 rounded-full bg-neutral-800 border border-white/15 text-white/70 hover:text-white shadow-lg flex items-center justify-center"
          >
            <ArrowDown size={13} />
          </motion.button>
        )}
      </AnimatePresence>
      </div>
    </div>
  );
}

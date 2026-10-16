import { useEffect, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { X, Copy, Check, RotateCcw } from "lucide-react";

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
    <thead className="bg-neutral-900 text-white font-semibold" {...p} />
  ),
  th: ({ node, ...p }: any) => (
    <th className="px-3 py-1.5 text-left font-bold border-b border-r border-white/15 last:border-r-0" {...p} />
  ),
  td: ({ node, ...p }: any) => (
    <td className="px-3 py-1.5 border-t border-r border-white/10 last:border-r-0 text-white/80" {...p} />
  ),
  pre: ({ node, ...p }: any) => (
    <pre className="my-2 p-3 rounded-lg bg-neutral-950 border border-white/15 overflow-x-auto text-[12px] leading-relaxed text-white/90 font-mono" {...p} />
  ),
  code: ({ node, inline, className, ...p }: any) =>
    inline ? (
      <code className="px-1.5 py-0.5 rounded bg-neutral-900 border border-white/15 text-[11.5px] text-white/95 font-mono" {...p} />
    ) : (
      <code className={`font-mono ${className ?? ""}`} {...p} />
    ),
  ul: ({ node, ...p }: any) => <ul className="list-disc pl-5 space-y-1 my-2" {...p} />,
  ol: ({ node, ...p }: any) => <ol className="list-decimal pl-5 space-y-1 my-2" {...p} />,
  blockquote: ({ node, ...p }: any) => (
    <blockquote className="border-l-2 border-white/40 pl-3 my-2 text-white/75 italic" {...p} />
  ),
  a: ({ node, ...p }: any) => (
    <a className="text-cyan-400 underline underline-offset-2 hover:text-cyan-300 transition-colors" target="_blank" rel="noreferrer" {...p} />
  ),
};

export default function ChatPanel({ messages, streaming, error, model, onClose, onRetry }: Props) {
  const [copied, setCopied] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages, error]);

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
            <span className="absolute inline-flex w-full h-full rounded-full bg-white opacity-70 animate-ping" />
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
          <button onClick={onRetry} className={btn}>
            <RotateCcw size={13} />
          </button>
        )}
        {last && (
          <button onClick={copy} className={btn}>
            {copied ? <Check size={13} className="text-emerald-400" /> : <Copy size={13} />}
          </button>
        )}
        <button onClick={onClose} className={btn}>
          <X size={14} />
        </button>
      </div>

      <div
        ref={scrollRef}
        className="px-3.5 pb-3 overflow-y-auto space-y-3 max-h-[min(520px,calc(100vh-160px))]"
      >
        {messages.map((m, i) => {
          const isLast = i === messages.length - 1;
          if (m.role === "user") {
            return (
              <div key={i} className="flex justify-end">
                <div className="max-w-[85%] rounded-xl bg-neutral-900 border border-white/10 px-3 py-1.5 text-[13px] text-white/90 select-text break-words">
                  {m.text}
                </div>
              </div>
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
              <div key={i} className="space-y-2 py-1">
                {[88, 70, 52].map((w, k) => (
                  <div
                    key={k}
                    className="h-[9px] rounded bg-white/10 animate-pulse"
                    style={{ width: `${w}%` }}
                  />
                ))}
              </div>
            );
          }
          return (
            <div key={i} className={isLast && streaming ? "stream-cursor" : ""}>
              <ReactMarkdown remarkPlugins={[remarkGfm]} className="md-body" components={MD_COMPONENTS}>
                {m.text}
              </ReactMarkdown>
              {isLast && error && (
                <p className="mt-2 text-[12.5px] text-rose-300/90 select-text">{error}</p>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

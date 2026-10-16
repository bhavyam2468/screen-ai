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
  table: ({ node, ...p }: any) => (
    <div className="my-2.5 overflow-x-auto rounded-lg border border-white/15">
      <table className="w-full text-[12px] border-collapse" {...p} />
    </div>
  ),
  thead: ({ node, ...p }: any) => (
    <thead className="bg-neutral-900 text-white/90" {...p} />
  ),
  th: ({ node, ...p }: any) => (
    <th className="px-3 py-1.5 text-left font-semibold border-b border-r border-white/15 last:border-r-0" {...p} />
  ),
  td: ({ node, ...p }: any) => (
    <td className="px-3 py-1.5 border-t border-r border-white/10 last:border-r-0 text-white/80" {...p} />
  ),
  pre: ({ node, ...p }: any) => (
    <pre className="my-2 p-3 rounded-lg bg-neutral-950 border border-white/15 overflow-x-auto text-[12px] leading-relaxed text-white/90" {...p} />
  ),
  code: ({ node, inline, className, ...p }: any) =>
    inline ? (
      <code className="px-1.5 py-0.5 rounded bg-neutral-900 border border-white/15 text-[11.5px] text-white/90" {...p} />
    ) : (
      <code className={className} {...p} />
    ),
  ul: ({ node, ...p }: any) => <ul className="list-disc pl-4 space-y-1 my-1.5" {...p} />,
  ol: ({ node, ...p }: any) => <ol className="list-decimal pl-4 space-y-1 my-1.5" {...p} />,
  blockquote: ({ node, ...p }: any) => (
    <blockquote className="border-l-2 border-white/40 pl-3 my-2 text-white/70 italic" {...p} />
  ),
  a: ({ node, ...p }: any) => <a className="underline underline-offset-2" {...p} />,
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

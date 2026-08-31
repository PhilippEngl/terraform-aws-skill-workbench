import { useEffect, useRef, useState } from 'react';
import { Send } from 'lucide-react';
import type { Message } from '../types';

interface ChatPaneProps {
  messages: Message[];
  isProcessing: boolean;
  modelIds: string[];
  onSend: (prompt: string, modelId: string) => void;
}

/** "us.anthropic.claude-sonnet-4-6" reads as "claude sonnet 4 6" in a picker. */
function shortModelName(modelId: string): string {
  return modelId.replace(/^[a-z]+\./, '').replace(/-/g, ' ');
}

export function ChatPane({ messages, isProcessing, modelIds, onSend }: ChatPaneProps) {
  const [prompt, setPrompt] = useState('');
  const [modelId, setModelId] = useState(modelIds[0] ?? '');
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  function submit() {
    if (!prompt.trim() || isProcessing) return;
    onSend(prompt, modelId);
    setPrompt('');
  }

  return (
    <div className="flex-1 flex flex-col min-h-0">
      <div className="flex-1 overflow-y-auto px-3 py-3 space-y-3">
        {messages.length === 0 && (
          <div className="text-xs text-gray-500 leading-relaxed space-y-2">
            <p>Ask the agent what skills and tools it can see. That is the fastest way to confirm a skill actually loaded.</p>
            <p>
              It has file operations and a browser. It has no shell — that is deliberate, so a
              skill cannot read anything outside its own prefix.
            </p>
          </div>
        )}

        {messages.map((message) => (
          <div
            key={message.id}
            className={`text-xs leading-relaxed ${
              message.role === 'user' ? 'text-gray-300' : 'text-gray-100'
            }`}
          >
            <div className="flex items-baseline gap-2 mb-1">
              <span
                className={`text-[11px] font-medium ${
                  message.role === 'user' ? 'text-gray-500' : 'text-emerald-400'
                }`}
              >
                {message.role === 'user' ? 'you' : 'agent'}
              </span>
              {message.modelId && (
                <span className="text-[11px] text-gray-600">{shortModelName(message.modelId)}</span>
              )}
            </div>
            <div
              className={`whitespace-pre-wrap rounded px-2.5 py-2 ${
                message.role === 'user' ? 'bg-white/[0.04]' : 'glass-subtle'
              }`}
            >
              {message.text}
            </div>
          </div>
        ))}

        {isProcessing && <p className="text-xs text-gray-500">Thinking…</p>}
        <div ref={endRef} />
      </div>

      <div className="border-t border-white/[0.06] p-3 shrink-0 space-y-2">
        <label className="flex items-center gap-2 text-[11px] text-gray-500">
          Model
          <select
            value={modelId}
            onChange={(event) => setModelId(event.target.value)}
            className="flex-1 bg-gray-900 border border-white/[0.08] rounded px-2 py-1 text-xs text-gray-300 focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
          >
            {modelIds.map((id) => (
              <option key={id} value={id}>
                {shortModelName(id)}
              </option>
            ))}
          </select>
        </label>

        <div className="flex gap-2">
          <textarea
            value={prompt}
            onChange={(event) => setPrompt(event.target.value)}
            onKeyDown={(event) => {
              // Enter sends, Shift+Enter breaks the line.
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                submit();
              }
            }}
            rows={2}
            placeholder="Ask the agent to use one of your skills…"
            aria-label="Message to the agent"
            className="flex-1 resize-none bg-gray-900 border border-white/[0.08] rounded px-2.5 py-2 text-xs text-gray-200 placeholder:text-gray-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
          />
          <button
            type="button"
            onClick={submit}
            disabled={isProcessing || !prompt.trim()}
            aria-label="Send message"
            className="self-end p-2 rounded bg-emerald-500/15 text-emerald-300 border border-emerald-500/25 hover:bg-emerald-500/25 disabled:opacity-40 disabled:cursor-not-allowed transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
          >
            <Send className="w-4 h-4" aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>
  );
}

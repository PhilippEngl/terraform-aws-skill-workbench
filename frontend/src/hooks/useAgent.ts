import { useState, useCallback, useRef } from 'react';
import { callProxy } from './proxy';
import type { Message, InvokeResult } from '../types';

interface UseAgentReturn {
  messages: Message[];
  isProcessing: boolean;
  /** Null until the first message, because the session is minted lazily. */
  sessionId: string | null;
  /** When the current session started, and therefore when its skills were fetched. */
  skillsLoadedAt: Date | null;
  /** True once a skill has been saved since the current session started. */
  skillsStale: boolean;
  send: (prompt: string, modelId: string) => Promise<void>;
  /** Mint a new session so the next message re-fetches skills. Keeps the transcript. */
  refreshSession: () => void;
  markSkillsStale: () => void;
  clear: () => void;
}

/**
 * The session is the unit of skill loading, which makes rotating it a first-class
 * action rather than an implementation detail.
 *
 * Skills are fetched once per session and then persist on disk for its duration, so
 * editing one has no effect on an open conversation. `refreshSession` mints a new
 * `runtimeSessionId` to force a re-fetch. The transcript is deliberately kept across
 * that boundary, and so is the agent's own memory: memory is scoped by `actorId`
 * rather than by session, so the user keeps their context while the skills reload.
 */
export function useAgent(): UseAgentReturn {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [skillsLoadedAt, setSkillsLoadedAt] = useState<Date | null>(null);
  const [skillsStale, setSkillsStale] = useState(false);

  // A synchronous lock, not the isProcessing state. State updates are async and can
  // lag a fast double-press, and two concurrent invocations on one session corrupt
  // the conversation history with a tool_use that has no matching tool_result.
  const inFlight = useRef(false);

  const send = useCallback(
    async (prompt: string, modelId: string) => {
      if (inFlight.current || !prompt.trim()) return;
      inFlight.current = true;
      setIsProcessing(true);

      setMessages((prev) => [
        ...prev,
        { id: crypto.randomUUID(), role: 'user', text: prompt, timestamp: Date.now() },
      ]);

      try {
        const result = await callProxy<InvokeResult>({
          action: 'invoke',
          prompt,
          model_id: modelId,
          // Omitted on the first message so the proxy mints one.
          session_id: sessionId ?? undefined,
        });

        if (result.session_id !== sessionId) {
          setSessionId(result.session_id);
          setSkillsLoadedAt(new Date());
          setSkillsStale(false);
        }

        setMessages((prev) => [
          ...prev,
          {
            id: crypto.randomUUID(),
            role: 'assistant',
            text: renderResponse(result.response),
            timestamp: Date.now(),
            modelId: result.model_id,
          },
        ]);
      } catch (e) {
        setMessages((prev) => [
          ...prev,
          {
            id: crypto.randomUUID(),
            role: 'assistant',
            text: e instanceof Error ? e.message : 'The request failed.',
            timestamp: Date.now(),
          },
        ]);
      } finally {
        setIsProcessing(false);
        inFlight.current = false;
      }
    },
    [sessionId]
  );

  const refreshSession = useCallback(() => {
    // Dropping the ID is enough: the next send omits it and the proxy mints a fresh
    // one, which is when skills are actually re-fetched. Setting skillsLoadedAt here
    // would be a lie — nothing has loaded until the next message.
    setSessionId(null);
    setSkillsLoadedAt(null);
    setSkillsStale(false);
  }, []);

  const markSkillsStale = useCallback(() => {
    // Only meaningful while a session is open. With no session the next message
    // loads current skills anyway, so there is nothing stale to warn about.
    setSkillsStale((prev) => prev || true);
  }, []);

  const clear = useCallback(() => {
    setMessages([]);
    setSessionId(null);
    setSkillsLoadedAt(null);
    setSkillsStale(false);
  }, []);

  return {
    messages,
    isProcessing,
    sessionId,
    skillsLoadedAt,
    skillsStale,
    send,
    refreshSession,
    markSkillsStale,
    clear,
  };
}

/**
 * The harness payload shape is not pinned down yet, so this is deliberately lenient:
 * pull the obvious text fields if present, otherwise show the JSON rather than
 * swallowing it. Tighten once a real response has been observed.
 */
function renderResponse(response: unknown): string {
  if (typeof response === 'string') return response;
  if (response && typeof response === 'object') {
    const obj = response as Record<string, unknown>;
    for (const field of ['responseText', 'text', 'output', 'message', 'result']) {
      if (typeof obj[field] === 'string') return obj[field] as string;
    }
    return JSON.stringify(response, null, 2);
  }
  return 'No response received from the agent.';
}

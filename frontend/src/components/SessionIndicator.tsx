import { RefreshCw, CircleAlert, CircleCheck, Circle } from 'lucide-react';

interface SessionIndicatorProps {
  sessionId: string | null;
  skillsLoadedAt: Date | null;
  skillsStale: boolean;
  isProcessing: boolean;
  onRefresh: () => void;
}

/**
 * Makes session-scoped skill loading visible, which is the one piece of AgentCore
 * semantics a user of this tool has to understand.
 *
 * Skills are fetched once per session. Saving a skill therefore does nothing to an
 * open conversation, and without this indicator the tool would look broken: you edit
 * a skill, ask the agent again, and get the old behaviour with no explanation.
 */
export function SessionIndicator({
  sessionId,
  skillsLoadedAt,
  skillsStale,
  isProcessing,
  onRefresh,
}: SessionIndicatorProps) {
  const state = !sessionId ? 'none' : skillsStale ? 'stale' : 'loaded';

  const label =
    state === 'none'
      ? 'no session — skills load on your next message'
      : state === 'stale'
        ? 'unsaved changes not yet loaded'
        : `skills loaded at ${skillsLoadedAt!.toLocaleTimeString([], {
            hour: '2-digit',
            minute: '2-digit',
          })}`;

  const tone =
    state === 'stale'
      ? 'text-amber-300'
      : state === 'loaded'
        ? 'text-emerald-300'
        : 'text-gray-400';

  const Icon = state === 'stale' ? CircleAlert : state === 'loaded' ? CircleCheck : Circle;

  return (
    <div className="flex items-center justify-between gap-3 px-3 py-2 border-b border-white/[0.06] shrink-0">
      <div className={`flex items-center gap-1.5 text-xs ${tone}`} role="status" aria-live="polite">
        <Icon className="w-3.5 h-3.5 shrink-0" aria-hidden="true" />
        <span>{label}</span>
      </div>

      <button
        type="button"
        onClick={onRefresh}
        disabled={isProcessing || state === 'none'}
        title={
          state === 'stale'
            ? 'Start a new session so your saved changes are loaded'
            : 'Start a new session and re-fetch skills'
        }
        className="flex items-center gap-1.5 text-xs px-2 py-1 rounded border border-white/[0.08] hover:bg-white/[0.06] disabled:opacity-40 disabled:cursor-not-allowed transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
      >
        <RefreshCw className="w-3.5 h-3.5" aria-hidden="true" />
        Refresh
      </button>
    </div>
  );
}

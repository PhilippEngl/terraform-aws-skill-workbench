import { FileText, FolderOpen, Plus, RotateCw } from 'lucide-react';
import type { Skill } from '../types';

interface SkillListProps {
  skills: Skill[];
  isLoading: boolean;
  error: string | null;
  activeSkill: string | null;
  activePath: string | null;
  onOpen: (skillName: string, path: string) => void;
  onCreate: () => void;
  onReload: () => void;
}

export function SkillList({
  skills,
  isLoading,
  error,
  activeSkill,
  activePath,
  onOpen,
  onCreate,
  onReload,
}: SkillListProps) {
  return (
    <aside className="w-56 shrink-0 glass-subtle border-r border-white/[0.06] flex flex-col">
      <div className="flex items-center justify-between px-3 py-2 border-b border-white/[0.06]">
        <span className="text-xs font-medium text-gray-300">Your skills</span>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={onReload}
            title="Reload the list from S3"
            className="p-1 rounded text-gray-400 hover:text-white hover:bg-white/[0.06] transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
          >
            <RotateCw className="w-3.5 h-3.5" aria-hidden="true" />
          </button>
          <button
            type="button"
            onClick={onCreate}
            title="New skill"
            className="p-1 rounded text-gray-400 hover:text-white hover:bg-white/[0.06] transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
          >
            <Plus className="w-3.5 h-3.5" aria-hidden="true" />
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto py-1">
        {isLoading && <p className="px-3 py-2 text-xs text-gray-500">Loading…</p>}

        {error && (
          <p className="px-3 py-2 text-xs text-red-400" role="alert">
            {error}
          </p>
        )}

        {!isLoading && !error && skills.length === 0 && (
          <p className="px-3 py-2 text-xs text-gray-500 leading-relaxed">
            No skills yet. Press + to write one, then Refresh in the chat pane to load it.
          </p>
        )}

        {skills.map((skill) => (
          <div key={skill.name} className="mb-1">
            <div className="flex items-center gap-1.5 px-3 py-1 text-xs text-gray-400">
              <FolderOpen className="w-3.5 h-3.5 shrink-0" aria-hidden="true" />
              <span className="truncate">{skill.name}</span>
            </div>

            {skill.files.map((path) => {
              const isActive = activeSkill === skill.name && activePath === path;
              return (
                <button
                  key={path}
                  type="button"
                  onClick={() => onOpen(skill.name, path)}
                  className={`w-full flex items-center gap-1.5 pl-7 pr-3 py-1 text-xs text-left transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400 ${
                    isActive ? 'bg-emerald-500/10 text-emerald-300' : 'text-gray-400 hover:bg-white/[0.04]'
                  }`}
                >
                  <FileText className="w-3 h-3 shrink-0" aria-hidden="true" />
                  <span className="truncate">{path}</span>
                </button>
              );
            })}
          </div>
        ))}
      </div>

      {/* Shared skills are deliberately not listed. The authenticated role has no
          access to that prefix at all, so there is nothing to fetch — the only way to
          observe them is the agent's behaviour. */}
      <p className="px-3 py-2 text-[11px] text-gray-600 border-t border-white/[0.06] leading-relaxed">
        Curated shared skills also load into every session. They are not readable here.
      </p>
    </aside>
  );
}

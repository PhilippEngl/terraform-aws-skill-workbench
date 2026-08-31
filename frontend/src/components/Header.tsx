import { LogOut, FlaskConical } from 'lucide-react';

interface HeaderProps {
  email: string;
  onSignOut: () => void;
}

export function Header({ email, onSignOut }: HeaderProps) {
  return (
    <header className="glass flex items-center justify-between px-5 py-3 border-b border-white/[0.06] shrink-0">
      <div className="flex items-center gap-2.5">
        <FlaskConical className="w-5 h-5 text-emerald-400" aria-hidden="true" />
        <h1 className="text-sm font-semibold tracking-tight">Skill Workbench</h1>
        <span className="text-xs text-gray-500 hidden sm:inline">
          author a skill, then try it against the harness
        </span>
      </div>

      <div className="flex items-center gap-3">
        <span className="text-xs text-gray-400 hidden sm:inline">{email}</span>
        <button
          type="button"
          onClick={onSignOut}
          className="flex items-center gap-1.5 text-xs text-gray-400 hover:text-white transition-colors rounded px-2 py-1 focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
        >
          <LogOut className="w-3.5 h-3.5" aria-hidden="true" />
          Sign out
        </button>
      </div>
    </header>
  );
}

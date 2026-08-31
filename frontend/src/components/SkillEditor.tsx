import { useMemo } from 'react';
import Editor from '@monaco-editor/react';
import { Save, CircleAlert } from 'lucide-react';
import type { OpenFile } from '../types';

interface SkillEditorProps {
  file: OpenFile | null;
  isSaving: boolean;
  saveError: string | null;
  onChange: (content: string) => void;
  onSave: () => void;
}

/**
 * Mirrors the proxy's validator, and is not a substitute for it.
 *
 * The authoritative check runs server-side, because a browser check is advice the
 * caller can skip. This exists to move the feedback from a round trip to a keystroke
 * — and it deliberately reports the same messages, so a rejection the browser missed
 * reads the same as one it caught.
 */
function validateFrontmatter(content: string, skillName: string): string | null {
  const lines = content.split('\n');
  if (lines[0]?.trim() !== '---') return 'SKILL.md must open with a --- frontmatter delimiter';

  const end = lines.findIndex((line, i) => i > 0 && line.trim() === '---');
  if (end === -1) return 'Frontmatter is never closed by a second ---';

  const fields = new Map<string, string>();
  for (const line of lines.slice(1, end)) {
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    if (line.includes('\t')) return 'Frontmatter contains a tab character, which is not valid YAML';
    const colon = line.indexOf(':');
    if (colon === -1) return `Frontmatter line is not a key: value pair: ${line.trim()}`;
    fields.set(line.slice(0, colon).trim(), line.slice(colon + 1).trim().replace(/^["']|["']$/g, ''));
  }

  for (const required of ['name', 'description']) {
    if (!fields.get(required)) return `Frontmatter is missing a non-empty ${required}`;
  }
  if (fields.get('name') !== skillName) {
    return `Frontmatter name "${fields.get('name')}" does not match the directory "${skillName}"`;
  }
  if (!lines.slice(end + 1).join('\n').trim()) return 'SKILL.md has frontmatter but no body';

  return null;
}

export function SkillEditor({ file, isSaving, saveError, onChange, onSave }: SkillEditorProps) {
  // Only SKILL.md carries frontmatter; references/ and scripts/ are opaque to the
  // service and must not be validated as though they were skills.
  const validationError = useMemo(() => {
    if (!file || file.path !== 'SKILL.md') return null;
    return validateFrontmatter(file.content, file.skillName);
  }, [file]);

  if (!file) {
    return (
      <div className="flex-1 flex items-center justify-center text-sm text-gray-500">
        Select a file, or press + to write a new skill.
      </div>
    );
  }

  const blocked = validationError !== null;

  return (
    <div className="flex-1 flex flex-col min-w-0">
      <div className="flex items-center justify-between gap-3 px-3 py-2 border-b border-white/[0.06] shrink-0">
        <span className="text-xs text-gray-400 truncate">
          {file.skillName}/{file.path}
          {file.dirty && <span className="text-amber-300 ml-1.5">•</span>}
        </span>

        <button
          type="button"
          onClick={onSave}
          disabled={isSaving || blocked || !file.dirty}
          title={blocked ? validationError! : 'Save to S3 via the proxy'}
          className="flex items-center gap-1.5 text-xs px-2.5 py-1 rounded bg-emerald-500/15 text-emerald-300 border border-emerald-500/25 hover:bg-emerald-500/25 disabled:opacity-40 disabled:cursor-not-allowed transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400"
        >
          <Save className="w-3.5 h-3.5" aria-hidden="true" />
          {isSaving ? 'Saving…' : 'Save'}
        </button>
      </div>

      {(validationError || saveError) && (
        <div
          className="flex items-start gap-1.5 px-3 py-2 text-xs text-amber-300 bg-amber-500/[0.07] border-b border-amber-500/20"
          role="alert"
        >
          <CircleAlert className="w-3.5 h-3.5 mt-px shrink-0" aria-hidden="true" />
          <span>{validationError ?? saveError}</span>
        </div>
      )}

      <Editor
        height="100%"
        language="markdown"
        theme="vs-dark"
        value={file.content}
        onChange={(value: string | undefined) => onChange(value ?? '')}
        options={{
          minimap: { enabled: false },
          fontSize: 13,
          wordWrap: 'on',
          lineNumbers: 'on',
          scrollBeyondLastLine: false,
          renderWhitespace: 'boundary',
          automaticLayout: true,
        }}
      />
    </div>
  );
}

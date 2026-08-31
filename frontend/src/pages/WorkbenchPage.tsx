import { useCallback, useState } from 'react';
import { SkillList } from '../components/SkillList';
import { SkillEditor } from '../components/SkillEditor';
import { ChatPane } from '../components/ChatPane';
import { SessionIndicator } from '../components/SessionIndicator';
import { useSkills } from '../hooks/useSkills';
import { useAgent } from '../hooks/useAgent';
import { config } from '../config';
import type { OpenFile } from '../types';

const NEW_SKILL_NAME_PATTERN = /^[a-z0-9][a-z0-9-]{0,63}$/;

export function WorkbenchPage() {
  const { skills, isLoading, error, refresh, readFile, save, starterSkill } = useSkills();
  const agent = useAgent();

  const [file, setFile] = useState<OpenFile | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const open = useCallback(
    async (skillName: string, path: string) => {
      setSaveError(null);
      try {
        const content = await readFile(skillName, path);
        setFile({ skillName, path, content, dirty: false });
      } catch (e) {
        setSaveError(e instanceof Error ? e.message : 'Could not read that file');
      }
    },
    [readFile]
  );

  const create = useCallback(() => {
    // A prompt rather than a modal. This is a developer tool and the name is the only
    // input; a dialog would be more code for no more clarity.
    const name = window.prompt('Skill name (kebab-case)');
    if (!name) return;

    if (!NEW_SKILL_NAME_PATTERN.test(name)) {
      setSaveError('Skill name must be kebab-case, start alphanumeric, 64 characters maximum');
      return;
    }

    setSaveError(null);
    // The starter content carries name: my-first-skill, which would fail the
    // name-matches-directory check, so it is substituted here rather than leaving the
    // user to fix a validation error on a file they did not write.
    setFile({
      skillName: name,
      path: 'SKILL.md',
      content: starterSkill.replace('name: my-first-skill', `name: ${name}`),
      dirty: true,
    });
  }, [starterSkill]);

  const onSave = useCallback(async () => {
    if (!file) return;
    setIsSaving(true);
    setSaveError(null);
    try {
      await save(file.skillName, file.path, file.content);
      setFile({ ...file, dirty: false });
      // The write landed but is not live: the open session already fetched its skills.
      // Flagging it here is what turns the indicator amber.
      agent.markSkillsStale();
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }, [file, save, agent]);

  return (
    <div className="flex-1 flex min-h-0">
      <SkillList
        skills={skills}
        isLoading={isLoading}
        error={error}
        activeSkill={file?.skillName ?? null}
        activePath={file?.path ?? null}
        onOpen={open}
        onCreate={create}
        onReload={() => void refresh()}
      />

      <SkillEditor
        file={file}
        isSaving={isSaving}
        saveError={saveError}
        onChange={(content) => setFile((prev) => (prev ? { ...prev, content, dirty: true } : prev))}
        onSave={() => void onSave()}
      />

      <section className="w-[26rem] shrink-0 flex flex-col glass-subtle border-l border-white/[0.06] min-h-0">
        <SessionIndicator
          sessionId={agent.sessionId}
          skillsLoadedAt={agent.skillsLoadedAt}
          skillsStale={agent.skillsStale}
          isProcessing={agent.isProcessing}
          onRefresh={agent.refreshSession}
        />
        <ChatPane
          messages={agent.messages}
          isProcessing={agent.isProcessing}
          modelIds={config.modelIds}
          onSend={(prompt, modelId) => void agent.send(prompt, modelId)}
        />
      </section>
    </div>
  );
}

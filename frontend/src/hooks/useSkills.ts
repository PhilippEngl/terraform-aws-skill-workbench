import { useState, useCallback, useEffect } from 'react';
import { callProxy } from './proxy';
import type { Skill, SaveSkillResult } from '../types';

const STARTER_SKILL = `---
name: my-first-skill
description: Replace this with what the skill does, then when to use it.
---

# My first skill

Write instructions to the agent, not documentation about the agent. Be imperative and
specific, and say what to report as well as what to do.

Save this, press Refresh to load it into a new session, then ask the agent what skills
it can see.
`;

interface UseSkillsReturn {
  skills: Skill[];
  isLoading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  readFile: (skillName: string, path: string) => Promise<string>;
  save: (skillName: string, path: string, content: string) => Promise<SaveSkillResult>;
  starterSkill: string;
}

/**
 * Every S3 access is mediated by the proxy. The browser holds only
 * `lambda:InvokeFunction` — no bucket grant, no prefix grant, no KMS grant.
 *
 * Reads were originally direct, with the authenticated role scoped by
 * `${cognito-identity.amazonaws.com:sub}`. That cannot work: the variable expands to the
 * *region-qualified* identity ID, `<region>:<uuid>`, while a usable S3 key segment
 * and a usable AgentCore `actorId` both want the bare UUID — and an IAM policy cannot
 * strip the region. Deriving the key inside the proxy from the request context removes
 * the mismatch rather than encoding it in two places that have to agree.
 *
 * Writes were always mediated, for a different reason: a malformed SKILL.md fails the
 * entire next invocation rather than being skipped, so frontmatter is validated first.
 */
export function useSkills(): UseSkillsReturn {
  const [skills, setSkills] = useState<Skill[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      // The proxy paginates and returns every key under the caller's own prefix, so
      // there is no truncation to handle here.
      const { prefix, keys } = await callProxy<{ prefix: string; keys: string[] }>({
        action: 'list_skills',
      });

      // users/<sub>/<skill-name>/<relative/path> → group by skill name.
      const grouped = new Map<string, string[]>();
      for (const key of keys) {
        const rest = key.slice(prefix.length);
        const slash = rest.indexOf('/');
        if (slash <= 0) continue;
        const name = rest.slice(0, slash);
        const path = rest.slice(slash + 1);
        if (!path) continue;
        if (!grouped.has(name)) grouped.set(name, []);
        grouped.get(name)!.push(path);
      }

      setSkills(
        [...grouped.entries()]
          .map(([name, files]) => ({ name, files: files.sort() }))
          .sort((a, b) => a.name.localeCompare(b.name))
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not list skills');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const readFile = useCallback(async (skillName: string, path: string): Promise<string> => {
    const { content } = await callProxy<{ key: string; content: string }>({
      action: 'read_file',
      skill_name: skillName,
      path,
    });
    return content;
  }, []);

  const save = useCallback(
    async (skillName: string, path: string, content: string): Promise<SaveSkillResult> => {
      const result = await callProxy<SaveSkillResult>({
        action: 'save_skill',
        skill_name: skillName,
        path,
        content,
      });
      await refresh();
      return result;
    },
    [refresh]
  );

  return { skills, isLoading, error, refresh, readFile, save, starterSkill: STARTER_SKILL };
}

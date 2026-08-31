export interface Message {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  timestamp: number;
  modelId?: string;
}

/** One authored skill directory under users/<sub>/. */
export interface Skill {
  /** Directory name, kebab-case. Also the frontmatter `name`. */
  name: string;
  /** Paths relative to the skill directory, e.g. "SKILL.md", "references/x.md". */
  files: string[];
}

/** An open editor buffer. `dirty` drives the save button and the session indicator. */
export interface OpenFile {
  skillName: string;
  path: string;
  content: string;
  dirty: boolean;
}

/**
 * Every proxy response. The proxy is invoked directly rather than through API
 * Gateway, so there is no statusCode/body envelope to unwrap — the discriminant is
 * `ok`, and a rejection carries a human-readable `error` meant to be shown verbatim.
 */
export type ProxyResponse<T> = ({ ok: true } & T) | { ok: false; error: string; request_id?: string };

export interface SaveSkillResult {
  key: string;
  bytes: number;
  /**
   * Always true. Skills are fetched once per session, so a save never affects the
   * open conversation — the UI has to tell the user to refresh rather than implying
   * the change is live.
   */
  requires_session_refresh: boolean;
}

export interface InvokeResult {
  session_id: string;
  model_id: string;
  skill_sources: string[];
  response: unknown;
}

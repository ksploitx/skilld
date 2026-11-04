/**
 * Shared TypeScript interfaces for the skilld platform.
 *
 * These types mirror the Pydantic models in apps/backend/app/schemas.py
 * field-for-field. When adding a field to one, add it to the other.
 *
 * Used by:
 *   - apps/extension   (browser extension)
 *   - apps/menubar     (future TypeScript bridge layer)
 */

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

export type SkillSource = "github" | "skills_sh";

// ---------------------------------------------------------------------------
// Core skill types
// ---------------------------------------------------------------------------

/**
 * Minimal skill representation returned in search result lists.
 * Does NOT include the full SKILL.md body (use SkillDetail for that).
 */
export interface SkillSummary {
  /** UUID v4 primary key */
  id: string;
  /** Display name, e.g. "Git Commit Message" */
  name: string;
  /** Folder name / slash-command identifier, e.g. "git-commit" */
  folder_name: string;
  /** Short description from SKILL.md frontmatter */
  description: string | null;
  /** Tag list, e.g. ["git", "commit"] */
  tags: string[];
  /** Where the skill was sourced from */
  source: SkillSource;
  /**
   * Canonical human-readable URL for this skill on its source platform.
   * e.g. https://github.com/owner/repo/tree/<sha>/.claude/skills/git-commit
   */
  source_url: string;
  /**
   * GitHub repository identifier, e.g. "anthropics/claude-code".
   * Used by the menubar app to fetch the full skill folder at install time.
   */
  repo: string;
  /**
   * Path within the repo to the skill folder, e.g. ".claude/skills/git-commit".
   * Combined with repo + commit_sha to construct the full GitHub API/raw URL.
   */
  repo_path: string;
  /**
   * Pinned commit SHA.  The menubar app uses repo + repo_path + commit_sha
   * to fetch the exact file tree from GitHub at install time, so installs
   * are reproducible and don't change under the user.
   */
  commit_sha: string;
  /** ISO 8601 timestamp */
  created_at: string;
  /** ISO 8601 timestamp */
  updated_at: string;
}

/**
 * Full skill detail including raw SKILL.md content.
 * Returned by GET /skills/{id}.
 */
export interface SkillDetail extends SkillSummary {
  /** Raw SKILL.md text (includes YAML frontmatter block). */
  skill_md: string;
}

// ---------------------------------------------------------------------------
// API response envelopes
// ---------------------------------------------------------------------------

/**
 * Paginated search response from GET /skills.
 */
export interface SkillSearchResponse {
  /** Total number of matching skills (ignoring limit/offset) */
  total: number;
  limit: number;
  offset: number;
  results: SkillSummary[];
}

// ---------------------------------------------------------------------------
// Query parameter helpers (used by both extension and menubar)
// ---------------------------------------------------------------------------

export interface SkillSearchParams {
  query?: string;
  tags?: string[];
  limit?: number;
  offset?: number;
}


export enum SkillSource {
  SKILLS_SH = 'skills_sh',
  GITHUB = 'github'
}

export interface Skill {
  id: string;
  name: string;
  description: string;
  tags: string[];
  source_url: string;
  raw_content: string;
  source: SkillSource;
  created_at: string;
  updated_at: string;
}

export interface SkillSearchResult {
  items: Skill[];
  total: number;
}

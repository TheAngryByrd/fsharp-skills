# Skills

Create skills with the [Agent Skills format](https://agentskills.io/home).
Use the [specification](https://agentskills.io/specification) for format requirements.

## Create a skill

1. Create `skills/<skill-name>/`.
2. Copy [SKILL.md.template](SKILL.md.template) to `skills/<skill-name>/SKILL.md`.
3. Replace all placeholders with instructions for the specific task.
4. Set `name` to the directory name. Use 1–64 lowercase letters, digits, or hyphens. Do not use consecutive, leading, or trailing hyphens.
5. Write a `description` of 1–1024 characters. State what the skill does and when to use it.
6. Add `scripts/`, `references/`, or `assets/` only when the skill needs them. Use relative links for supporting files.
7. If `skills-ref` is installed, run `skills-ref validate ./skills/<skill-name>` to check the format.

The template is a starting point, not an installable skill. Its body headings are suggestions, not specification requirements.
Keep each completed `SKILL.md` below 500 lines. Move detailed reference material to linked files.

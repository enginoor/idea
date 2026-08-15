# Work context

Update this file after every prompt so it acts as memory.

---

## Session log

### 2026-08-15 — Standing rule: sync after every prompt
- User asked that every change made in a session be committed and pushed to GitHub after every prompt. From now on, when a turn produces changes, commit them to main and push before the turn ends. Stage only the files that belong to that turn. Do not wait to be asked.

### 2026-08-15 — First build (agent.md, full app)

- User asked for an agent.md thinking document, real research before building, and a humanized, modern product. Rules: no em dashes, no decorative icons, no emojis anywhere.
- Researched the idea-management market (capture, develop, decide path vs collection boxes) and 2026 design trends. The thesis is written into agent.md.
- The repo was still empty (only context.md), so the full app was scaffolded from zero.
- Built idea: a quiet personal workspace for the second half of an idea.
  - Landing page at /: thesis hero, the box problem, the path, what the app refuses to be, privacy, final CTA.
  - Workspace at /workspace: one capture line, three columns (Inbox, Shaping, Decided), search, counts, start over. Keys: n focuses capture, / focuses search.
  - Idea page at /idea/:id: title, the thought, three shaping questions, verdict row (yes, not now, no), delete, send back to shaping.
  - Data: localStorage store behind useSyncExternalStore, seed ideas on first run, relative dates (today, yesterday, Aug 3).
- Stack: Vite 7, React 19, TypeScript strict, Tailwind CSS v4, react-router 7, framer-motion, Bun. Fonts: Newsreader variable for display, Inter variable for UI.
- Verified: bun tsc -b --noEmit is clean, bun run build is clean (dist output includes theme tokens and custom classes).
- The freebuff-preview CLI was not present in this session (command not found), so preview commands could not be saved with it. Standard scripts live in package.json: dev, build, preview, typecheck. The platform should auto-detect dev/build.
- Tradeoffs documented in agent.md: localStorage only, no auth, no backend. The upgrade path to Convex is the store module.

### 2026-08-15 — Initial inspection (repo connected)

- Connected repo: enginoor/idea (branch main, single commit 0c02e8a "Create context.md").
- The repository contained no application code, only context.md.
- No install/preview/build commands were configured at that time.

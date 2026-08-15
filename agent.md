# agent.md

This file is the working memory for this product. It exists so that any future session starts from the thinking that shaped this app instead of rediscovering it. Read it before you change code. If a change fights something written here, update this file first and say why in your response.

## What this product is

Name: idea. A personal workspace for the second half of an idea.

Writing a thought down takes ten seconds. Coming back to it, working it into something real, and deciding what it is worth takes everything else. Almost every idea tool only does the first half. It is a box that collects thoughts. This app is a path. A thought goes in, gets shaped, and leaves with a verdict.

The repo is enginoor/idea and the owner is a builder, so the product should feel like a notebook, not a project tracker. It should be quiet, honest, and fast.

## The problem, in research terms

Surveyed the idea management landscape on 2026-08-15. The strongest recurring criticism of idea tools is that they are collection boxes. Capture is called the easy ten percent; the other ninety is developing an idea until a decision can be made about it, and then deciding. Most tools nail capture, bolt on a status field, and call it a day. The lists become graveyards with good search. The tools that get praised are the ones that support the full path: capture, develop, decide.

Notebook culture agrees. People who keep field notes do not lack capture, they lack return. An idea written down and never touched again has produced exactly nothing.

So the thesis: idea is not a bigger box. It is the return path. Every feature either helps you capture faster, shape more honestly, or decide sooner. If a feature does none of those three, it does not belong.

## Product principles

1. Text first. Ideas are words, so the interface is words. No gradient cards, no dashboards, no avatar grids.
2. The tool stays quiet. Calm paper, ink, one rust accent. Nothing blinks, nothing pops, nothing begs for attention.
3. No gamification. No streaks, no badges, no points, no confetti. Thinking is not a game.
4. Honest copy. Write like a person talking to a person. No hype verbs, no fake urgency, no AI-slop phrasing.
5. Small surface. One capture line, three columns, one shaping page, three honest questions. Resist adding more.
6. Keyboard friendly. The capture line and search are one key away.
7. Nothing decorative. If an icon, color, or animation does not carry information, cut it. The one allowed flourish is the rust period in the wordmark.
8. Local and private by default. Ideas live in the browser. Nothing uploads unless the user chooses it.

## Voice and punctuation rules, hard rules

- No em dashes anywhere: UI copy, code comments, this file, chat replies. Use commas, periods, colons, or a new sentence.
- No emojis anywhere in the product.
- No decorative icons. An icon may earn a place only if a word would be worse, and so far none has.
- Banned words and phrases: unleash, supercharge, seamless, elevate, empower, journey, unlock, dive into, game changer, level up, AI-powered, state of the art, robust, cutting-edge, revolutionize, effortless, magic.
- Write short sentences. Prefer concrete nouns. Say a verdict, not a decision-making framework.
- Dates read like a person: today, yesterday, Aug 3.
- The product speaks as idea, lowercase, with a rust period.

## The model

An idea has three stages and three honest questions.

Stages:
- Inbox. Every thought lands here, unfiltered. No folders, no tags, no ceremony.
- Shaping. The idea is being worked. The three questions get answered.
- Decided. A verdict is written: yes, not now, or no.

The three questions, which are the shaping page:
1. Why does it matter?
2. What does it need?
3. What could go wrong?

An idea is not done when it is captured. It is done when it has a verdict. A yes becomes work elsewhere. Not now and no are still decisions, and writing them down is what lets an idea stop taking up space in your head.

## Design system

- Palette: warm paper #f3efe5, near-white cards #faf7ef, ink #221d15, soft ink #6f6657, faint ink #a09682, hairlines #e2dbc9. One accent, rust #a64a24, for the period, hover states, and the no verdict. Sage #55624a is reserved for the yes verdict.
- Type: Newsreader, a variable serif, for display and headlines. Inter for UI and body. Serif headlines set the notebook tone; sans keeps the interface quiet.
- Shape: sharp corners, hairline borders, generous whitespace. Nothing rounded, nothing glossy.
- Motion: short, slow fades and lifts on scroll. No spring bounces.
- The wordmark is the word idea plus a rust period. That period is the entire logo. Do not add a glyph, mark, or icon to it.

## Current state

Built 2026-08-15, first session with code:
- Full scaffold: Vite, React 19, TypeScript strict, Tailwind CSS v4, react-router, framer-motion. Bun scripts for dev, build, preview, typecheck.
- Landing page: thesis hero, the box problem, the path, what the app refuses to be, privacy, final CTA. Editorial and text-first.
- Workspace: capture line, three columns, search, counts, start over.
- Idea detail: title, the thought, the three shaping questions, the verdict row, delete, send back to shaping.
- Data: localStorage store behind a useSyncExternalStore hook, seed ideas on first run, relative dates.
- Everything persists in the browser. No account, no server.

## Known tradeoffs and the upgrade path

- Data is localStorage. Another browser or a cleared profile starts a fresh notebook. Backups are the browser.
- No auth, single user, no sync. Deliberate for the MVP, fake auth is worse than none.
- Upgrade path when the owner asks for real accounts: Convex for the backend, Convex Auth for login, port the store hook to a Convex query, then add export and import. Do not add this until asked.
- The platform default stack is Convex and this app is intentionally not using it yet. When the backend arrives, the store module is the single seam to replace.

## Roadmap, in priority order

1. Export the notebook as markdown. Highest trust value, cheapest to build.
2. A weekly review ritual: a page that gathers shaping ideas and asks the three questions again. The return path is the product.
3. Tags, but only as a single free-text line per idea, not a system.
4. Dark mode, using the same tokens.
5. Backend sync and auth, per the upgrade path.
6. Import from other tools. Last on purpose.

## Working notes for future sessions

- Run `bun install` after changing dependencies, `bun tsc -b --noEmit` to typecheck, `bun run build` to verify the production build.
- Do not add dependencies casually. This app needs react, react-dom, react-router-dom, framer-motion, the two fontsource packages, tailwindcss, vite, typescript. Everything else has to argue for itself.
- Keep copy in the tone above. Re-read any sentence that uses an em dash or a banned word.
- The seed ideas are the product demo. Keep them realistic and honest.
- When in doubt, make the tool quieter, not louder.

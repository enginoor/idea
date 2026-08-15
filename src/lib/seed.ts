import type { Idea } from "./types";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const now = Date.now();

type Seed = Omit<Idea, "createdAt" | "updatedAt" | "decidedAt"> & {
  createdAt: number;
  updatedAt?: number;
  decidedAt?: number | null;
};

function seed(partial: Seed): Idea {
  return {
    ...partial,
    updatedAt: partial.updatedAt ?? partial.createdAt,
    decidedAt: partial.decidedAt ?? null,
  };
}

export function seedIdeas(): Idea[] {
  return [
    seed({
      id: "seed-letter",
      title: "",
      thought:
        "A weekly letter to one friend. Instead of posting to the internet, write one real letter a week to someone I actually know. Small, private, and it has to matter.",
      stage: "inbox",
      why: "",
      needs: "",
      risks: "",
      verdict: null,
      verdictNote: "",
      createdAt: now - 5 * HOUR,
    }),
    seed({
      id: "seed-bookmark",
      title: "",
      thought:
        "A brass bookmark with a spring clip that holds one pen. The book and the pen never separate, so the next thought is always one reach away.",
      stage: "inbox",
      why: "",
      needs: "",
      risks: "",
      verdict: null,
      verdictNote: "",
      createdAt: now - DAY,
    }),
    seed({
      id: "seed-return-path",
      title: "Ship the return path, not a bigger box",
      thought:
        "Every idea tool I have tried fails at the same point: capture is easy, coming back is not. The whole product is the return path.",
      stage: "shaping",
      why: "Capture is the easy ten percent. If the return path is not in the first version, this app is a graveyard with good search.",
      needs:
        "A capture line that is one key away. A shaping page with three honest questions. A verdict row with real consequences.",
      risks:
        "The pull toward kanban columns, tags, and templates. It is a notebook, not a project tracker.",
      verdict: null,
      verdictNote: "",
      createdAt: now - 3 * DAY,
      updatedAt: now - 6 * HOUR,
    }),
    seed({
      id: "seed-name",
      title: "Keep the name idea and keep the period",
      thought:
        "The repo already owns the name. Keep it lowercase, keep the rust period. The period is the logo.",
      stage: "decided",
      why: "",
      needs: "",
      risks: "",
      verdict: "yes",
      verdictNote: "The wordmark is settled. Do not revisit it.",
      createdAt: now - 2 * DAY,
      updatedAt: now - 2 * DAY,
      decidedAt: now - DAY,
    }),
    seed({
      id: "seed-mobile",
      title: "A mobile app before the web version",
      thought:
        "Phones are where ideas actually happen, but a first version that runs everywhere and needs no install wins on reach.",
      stage: "decided",
      why: "",
      needs: "",
      risks: "",
      verdict: "no",
      verdictNote: "Not until the web version has earned its keep.",
      createdAt: now - 6 * DAY,
      updatedAt: now - 6 * DAY,
      decidedAt: now - 4 * DAY,
    }),
    seed({
      id: "seed-shape-of-design",
      title: "Read The Shape of Design before the about page",
      thought:
        "Chimero says the best tools make the work feel lighter. Write the about page with that in mind, then cut half of it.",
      stage: "decided",
      why: "",
      needs: "",
      risks: "",
      verdict: "later",
      verdictNote: "Worth doing, not worth doing this week.",
      createdAt: now - 9 * DAY,
      updatedAt: now - 9 * DAY,
      decidedAt: now - 2 * DAY,
    }),
  ];
}

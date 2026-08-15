import { useSyncExternalStore } from "react";
import type { Idea, Stage, Verdict } from "./types";
import { seedIdeas } from "./seed";

const STORAGE_KEY = "idea.notebook.v1";

let ideas: Idea[] = load();
const listeners = new Set<() => void>();

function load(): Idea[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Idea[];
      if (Array.isArray(parsed)) return parsed;
    }
  } catch {
    // storage unreadable, start fresh
  }
  return seedIdeas();
}

function persist(next: Idea[]) {
  ideas = next;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // storage unavailable, keep in memory for this session
  }
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useIdeas(): Idea[] {
  return useSyncExternalStore(subscribe, () => ideas);
}

export function byUpdatedDesc(a: Idea, b: Idea) {
  return b.updatedAt - a.updatedAt;
}

export function createIdea(thought: string): Idea {
  const idea: Idea = {
    id: crypto.randomUUID(),
    title: "",
    thought: thought.trim(),
    stage: "inbox",
    why: "",
    needs: "",
    risks: "",
    verdict: null,
    verdictNote: "",
    createdAt: Date.now(),
    updatedAt: Date.now(),
    decidedAt: null,
  };
  persist([idea, ...ideas]);
  return idea;
}

export function updateIdea(id: string, patch: Partial<Omit<Idea, "id">>) {
  persist(
    ideas.map((idea) =>
      idea.id === id ? { ...idea, ...patch, updatedAt: Date.now() } : idea
    )
  );
}

export function moveIdea(id: string, stage: Stage) {
  persist(
    ideas.map((idea) => {
      if (idea.id !== id) return idea;
      if (stage === "decided") return { ...idea, stage, updatedAt: Date.now() };
      return {
        ...idea,
        stage,
        verdict: null,
        decidedAt: null,
        updatedAt: Date.now(),
      };
    })
  );
}

export function decideIdea(id: string, verdict: Verdict) {
  const decidedAt = Date.now();
  persist(
    ideas.map((idea) =>
      idea.id === id
        ? {
            ...idea,
            stage: "decided",
            verdict,
            decidedAt,
            updatedAt: decidedAt,
          }
        : idea
    )
  );
}

export function deleteIdea(id: string) {
  persist(ideas.filter((idea) => idea.id !== id));
}

export function clearAll() {
  persist([]);
}

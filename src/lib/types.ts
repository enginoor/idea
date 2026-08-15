export type Stage = "inbox" | "shaping" | "decided";

export type Verdict = "yes" | "later" | "no";

export interface Idea {
  id: string;
  title: string;
  thought: string;
  stage: Stage;
  why: string;
  needs: string;
  risks: string;
  verdict: Verdict | null;
  verdictNote: string;
  createdAt: number;
  updatedAt: number;
  decidedAt: number | null;
}

export const STAGES: Stage[] = ["inbox", "shaping", "decided"];

export const STAGE_META: Record<Stage, { label: string; blurb: string }> = {
  inbox: {
    label: "Inbox",
    blurb: "Every idea lands here first. No judgement.",
  },
  shaping: {
    label: "Shaping",
    blurb: "Ideas being worked into something real.",
  },
  decided: {
    label: "Decided",
    blurb: "A verdict, written down.",
  },
};

export const VERDICT_META: Record<Verdict, { short: string; phrase: string }> = {
  yes: { short: "Yes", phrase: "Yes, do it" },
  later: { short: "Not now", phrase: "Not now" },
  no: { short: "No", phrase: "No" },
};

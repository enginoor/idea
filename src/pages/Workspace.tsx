import { useEffect, useMemo, useRef, useState } from "react";
import type { FormEvent } from "react";
import { AnimatePresence } from "framer-motion";
import { Wordmark } from "../components/Wordmark";
import { IdeaCard } from "../components/IdeaCard";
import { useIdeas, createIdea, clearAll, byUpdatedDesc } from "../lib/store";
import { STAGES, STAGE_META } from "../lib/types";
import type { Idea, Stage } from "../lib/types";

function matches(idea: Idea, q: string): boolean {
  return [idea.title, idea.thought, idea.why, idea.needs, idea.risks, idea.verdictNote]
    .join(" ")
    .toLowerCase()
    .includes(q);
}

function emptyFor(stage: Stage): string {
  if (stage === "inbox") return "Nothing in the inbox. The page is waiting.";
  if (stage === "shaping") return "Ideas you are working into something real will live here.";
  return "Every idea deserves a verdict. Decide when it is ready.";
}

export function Workspace() {
  const ideas = useIdeas();
  const [query, setQuery] = useState("");
  const captureRef = useRef<HTMLInputElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  const q = query.trim().toLowerCase();
  const visible = useMemo(
    () => (q ? ideas.filter((idea) => matches(idea, q)) : ideas),
    [ideas, q]
  );

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const el = document.activeElement;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA")) return;
      if (e.key === "n") {
        e.preventDefault();
        captureRef.current?.focus();
      }
      if (e.key === "/") {
        e.preventDefault();
        searchRef.current?.focus();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  function onCapture(e: FormEvent) {
    e.preventDefault();
    const value = captureRef.current?.value ?? "";
    if (!value.trim()) return;
    createIdea(value);
    if (captureRef.current) captureRef.current.value = "";
  }

  function onStartOver() {
    if (window.confirm("Delete every idea in the notebook? This cannot be undone.")) {
      clearAll();
    }
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 border-b border-line bg-paper/90 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-6 px-6">
          <Wordmark />
          <div className="flex items-center gap-6">
            <input
              ref={searchRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search"
              aria-label="Search ideas"
              className="w-36 border-b border-transparent bg-transparent py-1 text-sm text-ink outline-none transition-colors placeholder:text-ink-faint focus:border-ink-soft md:w-48"
            />
            <span className="hidden text-xs text-ink-faint sm:block">
              {ideas.length} {ideas.length === 1 ? "idea" : "ideas"}
            </span>
            <button
              onClick={onStartOver}
              className="text-xs text-ink-faint underline-offset-2 transition-colors hover:text-ink hover:underline"
            >
              Start over
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-6 pb-24">
        <section className="border-b border-line pb-12 pt-14">
          <form onSubmit={onCapture}>
            <input
              ref={captureRef}
              placeholder="What is the thought?"
              aria-label="Capture an idea"
              className="w-full bg-transparent font-display text-3xl font-medium leading-snug text-ink outline-none placeholder:text-ink-faint md:text-4xl"
            />
          </form>
          <p className="mt-4 text-xs text-ink-faint">
            Enter captures it into the inbox. Press n to focus this field, / to focus
            search.
          </p>
        </section>

        {q ? (
          <section className="pt-12">
            <p className="kicker">Results for {query}</p>
            <ul className="mt-6 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
              <AnimatePresence initial={false}>
                {visible.map((idea) => (
                  <IdeaCard key={idea.id} idea={idea} />
                ))}
              </AnimatePresence>
            </ul>
            {visible.length === 0 && (
              <p className="mt-10 text-sm text-ink-soft">Nothing matches. Try another word.</p>
            )}
          </section>
        ) : (
          <section className="grid gap-12 pt-12 md:grid-cols-3 md:gap-8">
            {STAGES.map((stage) => {
              const list = visible.filter((item) => item.stage === stage).sort(byUpdatedDesc);
              return (
                <div key={stage}>
                  <div className="flex items-baseline justify-between border-b border-line pb-3">
                    <h2 className="font-display text-2xl">{STAGE_META[stage].label}</h2>
                    <span className="text-xs text-ink-faint">{list.length}</span>
                  </div>
                  <p className="mt-3 text-sm leading-relaxed text-ink-soft">
                    {STAGE_META[stage].blurb}
                  </p>
                  <ul className="mt-6 space-y-4">
                    <AnimatePresence initial={false}>
                      {list.map((idea) => (
                        <IdeaCard key={idea.id} idea={idea} />
                      ))}
                    </AnimatePresence>
                  </ul>
                  {list.length === 0 && (
                    <p className="mt-6 text-sm leading-relaxed text-ink-faint">
                      {emptyFor(stage)}
                    </p>
                  )}
                </div>
              );
            })}
          </section>
        )}
      </main>
    </div>
  );
}

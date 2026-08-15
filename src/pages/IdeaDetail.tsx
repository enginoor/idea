import type { ReactNode } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { Wordmark } from "../components/Wordmark";
import { useIdeas, updateIdea, decideIdea, moveIdea, deleteIdea } from "../lib/store";
import { STAGE_META, VERDICT_META } from "../lib/types";
import type { Verdict } from "../lib/types";
import { formatDay } from "../lib/format";

function VerdictButton({
  tone,
  onClick,
  children,
}: {
  tone: "sage" | "ink" | "rust";
  onClick: () => void;
  children: ReactNode;
}) {
  const colors = {
    sage: "border-sage text-sage hover:bg-sage hover:text-paper",
    ink: "border-line-strong text-ink hover:border-ink",
    rust: "border-rust text-rust hover:bg-rust hover:text-paper",
  };
  return (
    <button
      onClick={onClick}
      className={`border px-5 py-2.5 text-sm font-medium transition-colors ${colors[tone]}`}
    >
      {children}
    </button>
  );
}

function verdictText(verdict: Verdict): string {
  if (verdict === "yes") return "text-sage";
  if (verdict === "later") return "text-ink-soft";
  return "text-rust";
}

export function IdeaDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const ideas = useIdeas();
  const idea = ideas.find((item) => item.id === id);

  if (!id || !idea) {
    return (
      <div className="mx-auto max-w-2xl px-6 py-24">
        <Wordmark />
        <h1 className="mt-10 font-display text-3xl">This idea is gone.</h1>
        <p className="mt-4 text-ink-soft">It may have been deleted.</p>
        <Link to="/workspace" className="btn-quiet mt-8">
          Back to the notebook
        </Link>
      </div>
    );
  }

  const ideaId = id;
  const patch = (p: Parameters<typeof updateIdea>[1]) => updateIdea(ideaId, p);

  function onDelete() {
    if (window.confirm("Delete this idea? It is gone for good.")) {
      deleteIdea(ideaId);
      navigate("/workspace");
    }
  }

  const decided = idea.stage === "decided";

  return (
    <div className="min-h-screen">
      <header className="border-b border-line">
        <div className="mx-auto flex h-16 max-w-2xl items-center justify-between px-6">
          <Link
            to="/workspace"
            className="text-sm text-ink-soft transition-colors hover:text-ink"
          >
            Back to the notebook
          </Link>
          <Wordmark />
          <button
            onClick={onDelete}
            className="text-sm text-ink-faint transition-colors hover:text-rust"
          >
            Delete
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-2xl px-6 pb-24 pt-14">
        <p className="kicker">
          {STAGE_META[idea.stage].label} · {formatDay(idea.createdAt)}
          {decided && idea.verdict ? ` · ${VERDICT_META[idea.verdict].short}` : ""}
        </p>
        <input
          value={idea.title}
          onChange={(e) => patch({ title: e.target.value })}
          placeholder="Give it a name"
          aria-label="Idea title"
          className="mt-6 w-full bg-transparent font-display text-4xl font-medium leading-tight text-ink outline-none placeholder:text-ink-faint"
        />

        <div className="mt-10">
          <p className="kicker">The thought</p>
          <textarea
            value={idea.thought}
            onChange={(e) => patch({ thought: e.target.value })}
            placeholder="What was the thought, in your own words?"
            rows={4}
            className="field mt-2"
          />
        </div>

        {!decided && (
          <section className="mt-14 border-t border-line pt-10">
            <p className="kicker">Shaping</p>
            <p className="mt-2 text-sm leading-relaxed text-ink-soft">
              Answer the three questions. A sentence becomes something a decision can be
              made about.
            </p>
            <div className="mt-8 space-y-8">
              <div>
                <label htmlFor="why" className="font-display text-xl">
                  Why does it matter?
                </label>
                <textarea
                  id="why"
                  value={idea.why}
                  onChange={(e) => patch({ why: e.target.value })}
                  placeholder="The reason it deserves your time."
                  rows={3}
                  className="field mt-2"
                />
              </div>
              <div>
                <label htmlFor="needs" className="font-display text-xl">
                  What does it need?
                </label>
                <textarea
                  id="needs"
                  value={idea.needs}
                  onChange={(e) => patch({ needs: e.target.value })}
                  placeholder="People, tools, money, time, a decision."
                  rows={3}
                  className="field mt-2"
                />
              </div>
              <div>
                <label htmlFor="risks" className="font-display text-xl">
                  What could go wrong?
                </label>
                <textarea
                  id="risks"
                  value={idea.risks}
                  onChange={(e) => patch({ risks: e.target.value })}
                  placeholder="Be honest. This is where ideas get real."
                  rows={3}
                  className="field mt-2"
                />
              </div>
            </div>
          </section>
        )}

        <section className="mt-14 border-t border-line pt-10">
          <p className="kicker">The verdict</p>
          <p className="mt-2 text-sm leading-relaxed text-ink-soft">
            {decided ? "This idea has a verdict." : "An idea is not done until it has one."}
          </p>
          {!decided && (
            <div className="mt-6 flex flex-wrap gap-3">
              <VerdictButton tone="sage" onClick={() => decideIdea(id, "yes")}>
                {VERDICT_META.yes.phrase}
              </VerdictButton>
              <VerdictButton tone="ink" onClick={() => decideIdea(id, "later")}>
                {VERDICT_META.later.phrase}
              </VerdictButton>
              <VerdictButton tone="rust" onClick={() => decideIdea(id, "no")}>
                {VERDICT_META.no.phrase}
              </VerdictButton>
            </div>
          )}
          {decided && idea.verdict && (
            <div className="mt-6">
              <p className={`font-display text-2xl ${verdictText(idea.verdict)}`}>
                {VERDICT_META[idea.verdict].phrase}
              </p>
              <div className="mt-6">
                <label htmlFor="verdictNote" className="kicker">
                  Why this verdict
                </label>
                <textarea
                  id="verdictNote"
                  value={idea.verdictNote}
                  onChange={(e) => patch({ verdictNote: e.target.value })}
                  placeholder="One honest line about the decision."
                  rows={2}
                  className="field mt-2"
                />
              </div>
              <button
                onClick={() => moveIdea(id, "shaping")}
                className="btn-quiet mt-8 px-4 py-2 text-xs"
              >
                Send back to shaping
              </button>
            </div>
          )}
        </section>
      </main>
    </div>
  );
}

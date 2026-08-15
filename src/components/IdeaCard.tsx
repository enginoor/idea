import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import type { Idea, Verdict } from "../lib/types";
import { VERDICT_META } from "../lib/types";
import { formatDay } from "../lib/format";

export function IdeaCard({ idea }: { idea: Idea }) {
  const title = idea.title || firstLine(idea.thought);
  const date = idea.stage === "decided" && idea.decidedAt ? idea.decidedAt : idea.createdAt;
  return (
    <motion.li
      layout
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -6 }}
      transition={{ duration: 0.2 }}
    >
      <Link
        to={`/idea/${idea.id}`}
        className="group block border border-line bg-card px-5 py-4 transition-colors hover:border-line-strong"
      >
        <div className="flex items-baseline justify-between gap-3">
          <span className="text-xs text-ink-faint">
            {idea.stage === "decided" ? `decided ${formatDay(date)}` : formatDay(date)}
          </span>
          {idea.stage === "decided" && idea.verdict && (
            <span className={`text-xs ${verdictColor(idea.verdict)}`}>
              {VERDICT_META[idea.verdict].short}
            </span>
          )}
        </div>
        <h3 className="mt-2 font-display text-lg leading-snug text-ink transition-colors group-hover:text-rust">
          {title}
        </h3>
        {idea.thought && idea.thought !== title && (
          <p className="mt-1 line-clamp-2 text-sm leading-relaxed text-ink-soft">{idea.thought}</p>
        )}
      </Link>
    </motion.li>
  );
}

function firstLine(text: string): string {
  const line = text.split("\n")[0] ?? "";
  if (line.length <= 90) return line;
  return `${line.slice(0, 90).trimEnd()}...`;
}

function verdictColor(verdict: Verdict): string {
  if (verdict === "yes") return "text-sage";
  if (verdict === "later") return "text-ink-faint";
  return "text-rust";
}

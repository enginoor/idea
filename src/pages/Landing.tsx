import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Wordmark } from "../components/Wordmark";

const steps = [
  {
    kicker: "01",
    title: "Capture",
    body: "The moment it happens, before it evaporates. One line, no folders, no tags, no ceremony.",
  },
  {
    kicker: "02",
    title: "Shape",
    body: "The hard part. Why does this matter? What does it need? What could go wrong? A sentence becomes something a decision can be made about.",
  },
  {
    kicker: "03",
    title: "Decide",
    body: "Yes. Not now. No. A real verdict, written down, so the idea stops hanging around in the background.",
  },
];

const refusals = [
  {
    title: "No streaks or badges",
    body: "Your thinking is not a game. Nothing counts, nothing tracks, nothing celebrates.",
  },
  {
    title: "No AI voice",
    body: "The words stay yours. No assistant rewriting your thoughts into corporate prose.",
  },
  {
    title: "No settings labyrinth",
    body: "No tags, templates, integrations and automations you will configure once and never touch again.",
  },
];

function Fade({
  children,
  delay = 0,
  className = "",
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 14 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-60px" }}
      transition={{ duration: 0.6, ease: "easeOut", delay }}
    >
      {children}
    </motion.div>
  );
}

export function Landing() {
  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-10 border-b border-line bg-paper/90 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
          <Wordmark />
          <Link to="/workspace" className="btn-quiet px-4 py-2 text-xs">
            Open the notebook
          </Link>
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-6 pb-24 pt-20 md:pt-28">
        <div className="max-w-3xl">
          <Fade>
            <p className="kicker">A notebook for the second half of an idea</p>
          </Fade>
          <Fade delay={0.08}>
            <h1 className="mt-6 font-display text-5xl font-medium leading-[1.05] tracking-tight text-ink md:text-7xl">
              Most ideas die in the notebook.
            </h1>
          </Fade>
          <Fade delay={0.16}>
            <p className="mt-8 max-w-xl text-lg leading-relaxed text-ink-soft">
              Writing a thought down takes ten seconds. Coming back to it, working it
              into something real, and deciding what it is worth takes everything else.
              idea is a small, quiet workspace for that second half.
            </p>
          </Fade>
          <Fade delay={0.24}>
            <div className="mt-10 flex flex-wrap items-center gap-4">
              <Link to="/workspace" className="btn-primary">
                Open your notebook
              </Link>
              <a href="#problem" className="btn-quiet">
                Read how it works
              </a>
            </div>
            <p className="mt-6 text-sm text-ink-faint">
              Runs in your browser. Nothing to install, nothing to sign up for.
            </p>
          </Fade>
        </div>
      </section>

      <section id="problem" className="border-t border-line">
        <div className="mx-auto max-w-6xl px-6 py-24">
          <div className="grid gap-16 lg:grid-cols-2">
            <Fade>
              <p className="kicker">The problem</p>
              <h2 className="mt-6 font-display text-4xl font-medium leading-tight md:text-5xl">
                The box problem
              </h2>
            </Fade>
            <Fade delay={0.1}>
              <div className="space-y-6 text-lg leading-relaxed text-ink-soft">
                <p>
                  Most idea apps are a box. A thought goes in and a list grows. The list
                  is easy to search and pleasant to look at, and almost nothing ever
                  comes out of it.
                </p>
                <p>
                  Capture is the easy ten percent. The other ninety is the path: shaping
                  a sentence into a proposal, and reaching a verdict you actually act on.
                  Tools that only collect ideas end up as graveyards with good search.
                </p>
              </div>
              <blockquote className="mt-10 border-l-2 border-rust pl-6 font-display text-2xl leading-snug text-ink">
                An idea you capture and never touch again has produced exactly nothing.
              </blockquote>
            </Fade>
          </div>
        </div>
      </section>

      <section id="path" className="border-t border-line bg-card">
        <div className="mx-auto max-w-6xl px-6 py-24">
          <Fade>
            <p className="kicker">The path</p>
            <h2 className="mt-6 font-display text-4xl font-medium leading-tight md:text-5xl">
              Capture. Shape. Decide.
            </h2>
            <p className="mt-4 max-w-xl text-lg text-ink-soft">
              Every idea gets a path, not a pile. Three steps and nothing else.
            </p>
          </Fade>
          <div className="mt-16 grid gap-px border border-line bg-line md:grid-cols-3">
            {steps.map((step, i) => (
              <Fade key={step.kicker} delay={i * 0.08} className="h-full bg-paper">
                <div className="flex h-full flex-col p-10">
                  <p className="kicker">{step.kicker}</p>
                  <h3 className="mt-4 font-display text-2xl">{step.title}</h3>
                  <p className="mt-3 leading-relaxed text-ink-soft">{step.body}</p>
                </div>
              </Fade>
            ))}
          </div>
        </div>
      </section>

      <section id="refuses" className="border-t border-line">
        <div className="mx-auto max-w-6xl px-6 py-24">
          <div className="grid gap-16 lg:grid-cols-2">
            <Fade>
              <p className="kicker">What it refuses to be</p>
              <h2 className="mt-6 font-display text-4xl font-medium leading-tight md:text-5xl">
                A quiet tool for loud thinking
              </h2>
            </Fade>
            <Fade delay={0.1}>
              <ul className="space-y-6">
                {refusals.map((item) => (
                  <li key={item.title} className="border-b border-line pb-6">
                    <h3 className="font-display text-xl">{item.title}</h3>
                    <p className="mt-2 leading-relaxed text-ink-soft">{item.body}</p>
                  </li>
                ))}
              </ul>
            </Fade>
          </div>
        </div>
      </section>

      <section id="privacy" className="border-t border-line bg-card">
        <div className="mx-auto max-w-6xl px-6 py-24">
          <div className="max-w-2xl">
            <Fade>
              <p className="kicker">Where your ideas live</p>
              <h2 className="mt-6 font-display text-4xl font-medium leading-tight">
                On this device.
              </h2>
              <p className="mt-6 text-lg leading-relaxed text-ink-soft">
                There is no account and no server, so there is nothing to leak and
                nothing to lose to a shutdown. Export is on the roadmap, and nothing will
                ever be uploaded without you choosing it.
              </p>
            </Fade>
          </div>
        </div>
      </section>

      <section className="border-t border-line">
        <div className="mx-auto max-w-6xl px-6 py-28 text-center">
          <Fade>
            <h2 className="mx-auto max-w-2xl font-display text-4xl font-medium leading-tight md:text-6xl">
              Start with one thought.
            </h2>
            <p className="mx-auto mt-6 max-w-md text-lg text-ink-soft">
              Write it down. Come back tomorrow. See what it becomes.
            </p>
            <div className="mt-10 flex justify-center">
              <Link to="/workspace" className="btn-primary">
                Open your notebook
              </Link>
            </div>
          </Fade>
        </div>
      </section>

      <footer className="border-t border-line">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-10 text-sm text-ink-faint md:flex-row md:items-center md:justify-between">
          <Wordmark />
          <p>A quiet place for thinking.</p>
          <a href="#problem" className="transition-colors hover:text-ink">
            How it works
          </a>
        </div>
      </footer>
    </div>
  );
}

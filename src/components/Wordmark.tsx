import { Link } from "react-router-dom";

export function Wordmark() {
  return (
    <Link to="/" className="font-display text-2xl tracking-tight text-ink" aria-label="idea home">
      idea<span className="text-rust">.</span>
    </Link>
  );
}

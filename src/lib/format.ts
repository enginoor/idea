const DAY = 86_400_000;

export function formatDay(ts: number): string {
  const today = new Date();
  const day = new Date(ts);
  const startOfToday = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate()
  ).getTime();
  const startOfDay = new Date(
    day.getFullYear(),
    day.getMonth(),
    day.getDate()
  ).getTime();
  const days = Math.round((startOfToday - startOfDay) / DAY);
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  return new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(
    day
  );
}

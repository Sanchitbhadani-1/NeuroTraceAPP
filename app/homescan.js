export const MAX_IDEAS = 6;
export const LIMITS = { title: 80, why: 200, where: 80, room: 40 };
export const PRIORITIES = ["high", "medium", "low"];

// ClaimsRules: an idea using any of these is dropped, not reworded
export const BANNED =
  /\b(ensur\w*|guarantee\w*|detect\w*|diagnos\w*|screening|treat(s|ed|ing|ment)?|cur(e|es|ed|ing)|prevent\w*|slows|improv\w*|prov(e|es|en|ing)|accurate\w*|effective\w*|safe|safer|safest|safely|fall-?proof|inspection|parkinson\w*)\b/i;

function parse(raw) {
  if (typeof raw !== "string") return raw;
  try {
    return JSON.parse(raw.replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, ""));
  } catch {
    return null;
  }
}

function clip(text, max) {
  const s = typeof text === "string" ? text.replace(/\s+/g, " ").trim() : "";
  if (s.length <= max) return s;
  const i = s.lastIndexOf(" ", max - 1);
  return (i > 0 ? s.slice(0, i) : s.slice(0, max - 1)) + "…";
}

export function cleanIdeas({ raw, max = MAX_IDEAS }) {
  const data = parse(raw);
  if (!data || typeof data !== "object") return { status: "unreadable", room: "", ideas: [], dropped: 0 };

  const room = clip(data.room, LIMITS.room);
  if (data.isRoom === false) return { status: "notRoom", room, ideas: [], dropped: 0 };

  const list = Array.isArray(data.ideas) ? data.ideas : [];
  const seen = new Set();
  const ideas = [];
  for (const item of list) {
    if (!item || typeof item.title !== "string") continue;
    const priority = String(item.priority).toLowerCase();
    const idea = {
      title: clip(item.title, LIMITS.title),
      why: clip(item.why, LIMITS.why),
      where: clip(item.where, LIMITS.where),
      priority: PRIORITIES.includes(priority) ? priority : "medium",
      done: false,
    };
    const key = idea.title.toLowerCase().replace(/[^a-z0-9]/g, "");
    if (!key || seen.has(key) || BANNED.test(`${idea.title} ${idea.why} ${idea.where}`)) continue;
    seen.add(key);
    ideas.push(idea);
  }

  const kept = ideas.slice(0, max);
  return { status: kept.length ? "ok" : "empty", room, ideas: kept, dropped: list.length - kept.length };
}

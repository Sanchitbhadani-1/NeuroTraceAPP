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

// On-device fallback: Apple's photo labels pick ideas from a fixed checklist. Tune the keywords on real photos
export const MIN_CONFIDENCE = 0.2;
export const DIM = 0.3; // average brightness 0..1 below which the photo counts as dim

const ROOMISH = /room|interior|indoor|furniture|floor|wall|house|home|kitchen|bath|bed|sofa|couch|chair|table|stair|hall|cabinet/;

const ROOMS = [
  [/bath|shower|toilet/, "Bathroom"],
  [/kitchen/, "Kitchen"],
  [/bedroom|\bbed\b/, "Bedroom"],
  [/stair/, "Stairs"],
  [/living|sofa|couch/, "Living room"],
];

// Highest priority first, since the cap keeps the first ones
const CHECKLIST = [
  [/rug|carpet/, "Tape down or remove loose rugs", "Rug edges and corners are easy to catch a foot on.", "high"],
  [/stair|step/, "Check for sturdy rails on both sides of the stairs", "A rail on each side gives something solid to hold going up and down.", "high"],
  [/bath|shower|toilet/, "Add grab bars and non-slip mats", "Wet floors and tubs are slippery, and a bar gives something solid to hold.", "high"],
  [/dim light/, "Add brighter lights or night lights", "This photo looks dim. More light makes edges and steps easier to see.", "medium"],
  [/cable|cord|wire/, "Move cords out of walkways", "Cords across the floor are easy to trip over.", "medium"],
  [/clutter|mess|box|bag|shoe|toy|laundry|clothing/, "Clear things off the floor in walkways", "A clear path is easier to walk through, especially at night.", "medium"],
  [/chair|sofa|couch|stool/, "Use chairs with arms and a seat that isn't too low", "Arms and a higher seat make standing up easier.", "low"],
  [/cabinet|cupboard|shelf|pantry|kitchen/, "Keep everyday things within easy reach", "Less reaching up high or bending down low.", "low"],
];

// labels: [{ identifier, confidence }] from VNClassifyImageRequest; brightness: 0..1 or null
export function ideasFromLabels({ labels = [], brightness = null, max = MAX_IDEAS }) {
  const seen = labels
    .filter((l) => l && l.confidence >= MIN_CONFIDENCE)
    .map((l) => String(l.identifier).toLowerCase().replace(/_/g, " "));
  if (brightness != null && brightness < DIM) seen.push("dim light");
  const text = seen.join(" | ");

  const ideas = CHECKLIST.filter(([re]) => re.test(text)).map(([, title, why, priority]) => ({ title, why, where: "", priority }));
  const room = ROOMS.find(([re]) => re.test(text))?.[1] ?? "Room";
  return cleanIdeas({ raw: { isRoom: ROOMISH.test(text), room, ideas }, max });
}

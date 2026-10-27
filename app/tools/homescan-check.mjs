// HOMESCAN.JS TURNS A PHOTO OF A ROOM INTO A LIST OF IDEAS FOR THE ROOM
// IT CLEANS UP IDEAS FROM GEMINI, AND PICKS IDEAS FROM APPLE'S PHOTO LABELS

// The most ideas a scan can give
export const MAX_IDEAS = 6;

// The longest each piece of text can be, in characters
export const LIMITS = {
  title: 80,
  why: 200,
  where: 80,
  room: 40,
};

// The priorities an idea can have, highest first
export const PRIORITIES = ["high", "medium", "low"];

// Words that get an idea dropped
export const BANNED =
  /\b(ensur\w*|guarantee\w*|detect\w*|diagnos\w*|screening|treat(s|ed|ing|ment)?|cur(e|es|ed|ing)|prevent\w*|slows|improv\w*|prov(e|es|en|ing)|accurate\w*|effective\w*|safe|safer|safest|safely|fall-?proof|inspection|parkinson\w*)\b/i;


// THE IDEAS GEMINI SENDS BACK

// Read Gemini's answer as an object
// Give back null if it can't be read
function parse(raw) {

  // Give back the answer as it is if it isn't text
  if (typeof raw !== "string") {
    return raw;
  }

  // Take off the code block marks and read the text as JSON
  try {
    return JSON.parse(raw.replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, ""));
  } catch {
    return null;
  }
}


// Shorten text to at most max characters
function clip(text, max) {

  // Turn runs of spaces and line breaks into one space, or use empty text if it isn't text
  let s = "";
  if (typeof text === "string") {
    s = text.replace(/\s+/g, " ").trim();
  }

  if (s.length <= max) {
    return s;
  }

  // Cut at the last space before max, or one character before max if there is no space, and add "…"
  const i = s.lastIndexOf(" ", max - 1);
  let cut = s.slice(0, max - 1);
  if (i > 0) {
    cut = s.slice(0, i);
  }
  return cut + "…";
}


// Clean up Gemini's answer into a room name and at most max ideas
// status is "unreadable", "notRoom", "empty" or "ok", and dropped is how many ideas were left out
export function cleanIdeas({ raw, max = MAX_IDEAS }) {

  // Give back unreadable if the answer can't be read
  const data = parse(raw);
  if (!data || typeof data !== "object") {
    return { status: "unreadable", room: "", ideas: [], dropped: 0 };
  }

  // Give back notRoom if isRoom is false
  const room = clip(data.room, LIMITS.room);
  if (data.isRoom === false) {
    return { status: "notRoom", room, ideas: [], dropped: 0 };
  }

  // Use an empty list if there are no ideas
  let list = [];
  if (Array.isArray(data.ideas)) {
    list = data.ideas;
  }

  const seen = new Set();
  const ideas = [];
  for (const item of list) {

    // Skip ideas with no title
    if (!item || typeof item.title !== "string") {
      continue;
    }

    // Use medium if the priority isn't high, medium or low
    let priority = String(item.priority).toLowerCase();
    if (!PRIORITIES.includes(priority)) {
      priority = "medium";
    }

    // Shorten each piece of text to its limit
    const idea = {
      title: clip(item.title, LIMITS.title),
      why: clip(item.why, LIMITS.why),
      where: clip(item.where, LIMITS.where),
      priority,
      done: false,
    };

    // Make a key from the title's lowercase letters and numbers
    const key = idea.title.toLowerCase().replace(/[^a-z0-9]/g, "");

    // Skip the idea if its key is empty or already seen, or it has a banned word
    if (!key || seen.has(key) || BANNED.test(`${idea.title} ${idea.why} ${idea.where}`)) {
      continue;
    }

    seen.add(key);
    ideas.push(idea);
  }

  // Keep the first max ideas and count the rest as dropped
  const kept = ideas.slice(0, max);
  let status = "empty";
  if (kept.length) {
    status = "ok";
  }

  return { status, room, ideas: kept, dropped: list.length - kept.length };
}


// IDEAS FROM APPLE'S PHOTO LABELS

// The lowest confidence a label needs to be used, from 0 to 1
export const MIN_CONFIDENCE = 0.2;

// The brightness below which a photo counts as dim, from 0 to 1
export const DIM = 0.3;

// Labels that mean the photo is of a room
const ROOMISH = /room|interior|indoor|furniture|floor|wall|house|home|kitchen|bath|bed|sofa|couch|chair|table|stair|hall|cabinet/;

// The room name for each kind of label, checked in order
const ROOMS = [
  [/bath|shower|toilet/, "Bathroom"],
  [/kitchen/, "Kitchen"],
  [/bedroom|\bbed\b/, "Bedroom"],
  [/stair/, "Stairs"],
  [/living|sofa|couch/, "Living room"],
];

// The checklist, each idea with its labels, title, reason and priority
// Listed from highest priority to lowest
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


// Pick ideas from Apple's photo labels
// labels is a list of { identifier, confidence }, and brightness is from 0 to 1 or null
export function ideasFromLabels({ labels = [], brightness = null, max = MAX_IDEAS }) {

  // Keep labels with enough confidence, in lowercase with underscores turned into spaces
  const seen = [];
  for (const l of labels) {
    if (l && l.confidence >= MIN_CONFIDENCE) {
      seen.push(String(l.identifier).toLowerCase().replace(/_/g, " "));
    }
  }

  // Add a dim light label if brightness is below DIM
  if (brightness != null && brightness < DIM) {
    seen.push("dim light");
  }

  // Join the labels into one string
  const text = seen.join(" | ");

  // Add each checklist idea whose labels match
  const ideas = [];
  for (const [re, title, why, priority] of CHECKLIST) {
    if (re.test(text)) {
      ideas.push({ title, why, where: "", priority });
    }
  }

  // Name the room after the first match in ROOMS, or Room if none match
  let room = "Room";
  for (const [re, name] of ROOMS) {
    if (re.test(text)) {
      room = name;
      break;
    }
  }

  // Run the ideas through cleanIdeas
  return cleanIdeas({ raw: { isRoom: ROOMISH.test(text), room, ideas }, max });
}
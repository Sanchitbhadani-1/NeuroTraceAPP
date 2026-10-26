// HOMESCAN.JS TURNS A PHOTO OF A ROOM INTO A SHORT LIST OF IDEAS FOR THE ROOM
// IT CLEANS UP GEMINI'S IDEAS, AND PICKS IDEAS FROM APPLE'S PHOTO LABELS WHEN WORKING ON THE DEVICE ONLY

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

// Words ClaimsRules doesn't allow, and an idea using any of them is dropped instead of reworded
export const BANNED =
  /\b(ensur\w*|guarantee\w*|detect\w*|diagnos\w*|screening|treat(s|ed|ing|ment)?|cur(e|es|ed|ing)|prevent\w*|slows|improv\w*|prov(e|es|en|ing)|accurate\w*|effective\w*|safe|safer|safest|safely|fall-?proof|inspection|parkinson\w*)\b/i;


// THE IDEAS GEMINI SENDS BACK

// Read Gemini's answer, which can be an object, JSON text, or JSON text inside a code block
// Give back null if the text can't be read
function parse(raw) {

  // An answer that isn't text is given back as it is
  if (typeof raw !== "string") {
    return raw;
  }

  // Take off the code block marks around the text, then read it
  try {
    return JSON.parse(raw.replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, ""));
  } catch {
    return null;
  }
}


// Shorten text to at most max characters, cutting at a space and ending with "…" when it is too long
function clip(text, max) {

  // Squash runs of spaces and line breaks into one space, and treat anything that isn't text as empty
  let s = "";
  if (typeof text === "string") {
    s = text.replace(/\s+/g, " ").trim();
  }

  if (s.length <= max) {
    return s;
  }

  // Cut at the last space that leaves room for the "…", or in the middle of a word if there is no space
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

  // Give up if the answer can't be read
  const data = parse(raw);
  if (!data || typeof data !== "object") {
    return { status: "unreadable", room: "", ideas: [], dropped: 0 };
  }

  // Give no ideas if the photo isn't of a room
  const room = clip(data.room, LIMITS.room);
  if (data.isRoom === false) {
    return { status: "notRoom", room, ideas: [], dropped: 0 };
  }

  // Treat a missing list of ideas as empty
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

    // Use medium for a priority that isn't high, medium or low
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

    // Compare titles by their letters and numbers only, so spacing, capitals and punctuation don't make a repeat look new
    const key = idea.title.toLowerCase().replace(/[^a-z0-9]/g, "");

    // Skip an idea with an empty title, a title already kept, or a banned word anywhere in it
    if (!key || seen.has(key) || BANNED.test(`${idea.title} ${idea.why} ${idea.where}`)) {
      continue;
    }

    seen.add(key);
    ideas.push(idea);
  }

  // Keep the first max ideas, and count every idea that was left out
  const kept = ideas.slice(0, max);
  let status = "empty";
  if (kept.length) {
    status = "ok";
  }

  return { status, room, ideas: kept, dropped: list.length - kept.length };
}


// THE ON DEVICE BACKUP, WHERE APPLE'S PHOTO LABELS PICK IDEAS FROM A FIXED CHECKLIST
// The keywords still need tuning on real photos

// How sure Apple has to be about a label for it to be used, from 0 to 1
export const MIN_CONFIDENCE = 0.2;

// The average brightness, from 0 to 1, below which the photo counts as dim
export const DIM = 0.3;

// Labels that mean the photo is of a room
const ROOMISH = /room|interior|indoor|furniture|floor|wall|house|home|kitchen|bath|bed|sofa|couch|chair|table|stair|hall|cabinet/;

// The room name to use for each kind of label, checked in this order
const ROOMS = [
  [/bath|shower|toilet/, "Bathroom"],
  [/kitchen/, "Kitchen"],
  [/bedroom|\bbed\b/, "Bedroom"],
  [/stair/, "Stairs"],
  [/living|sofa|couch/, "Living room"],
];

// The checklist, each idea with the labels that pick it, its title, why it helps and its priority
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


// Pick ideas from Apple's photo labels when working on the device only
// labels is a list of { identifier, confidence } from VNClassifyImageRequest, and brightness is from 0 to 1 or null
export function ideasFromLabels({ labels = [], brightness = null, max = MAX_IDEAS }) {

  // Keep the labels Apple is sure enough about, in lowercase with spaces instead of underscores
  const seen = [];
  for (const l of labels) {
    if (l && l.confidence >= MIN_CONFIDENCE) {
      seen.push(String(l.identifier).toLowerCase().replace(/_/g, " "));
    }
  }

  // Add a dim light label if the photo is dark
  if (brightness != null && brightness < DIM) {
    seen.push("dim light");
  }

  // Join the labels into one piece of text to search
  const text = seen.join(" | ");

  // Pick every checklist idea that has a matching label
  const ideas = [];
  for (const [re, title, why, priority] of CHECKLIST) {
    if (re.test(text)) {
      ideas.push({ title, why, where: "", priority });
    }
  }

  // Name the room after the first kind of room that matches, or just Room if none do
  let room = "Room";
  for (const [re, name] of ROOMS) {
    if (re.test(text)) {
      room = name;
      break;
    }
  }

  return cleanIdeas({ raw: { isRoom: ROOMISH.test(text), room, ideas }, max });
}
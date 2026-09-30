// Every user-facing string plus per-feature display metadata, in one file so
// it can be checked against Markdowns/NeuroTrace_ClaimsRules.md in one place
// (Global Constraint 10). Pure data + tiny string helpers - no DOM.

export const NOT_A_DIAGNOSIS =
  "These are measurements of how you moved during the tasks, compared with other people who " +
  "took the same tasks. They are not a diagnosis and cannot tell you whether you have a " +
  "neurological condition.";

const MANY_THINGS =
  "Many things move these numbers — caffeine, fatigue, sleep, anxiety, medication timing, cold " +
  "hands, familiarity with the task. One drawing is a single reading, not a pattern.";

// The consent card uses only the first sentence (Consent.dc.html).
export const MANY_THINGS_SHORT = MANY_THINGS.slice(0, MANY_THINGS.indexOf(".") + 1);

// Indexed by tier. label is verbatim (Global Constraint 3) - never reword.
export const TIERS = [
  {
    label: "Within typical range",
    meaning: [NOT_A_DIAGNOSIS],
    todo:
      "Draw the spiral again on another day if you want to see how much your own numbers move " +
      "between sittings. Your own baseline is the comparison that means the most over time.",
  },
  {
    label: "Some measures outside typical range",
    meaning: [NOT_A_DIAGNOSIS, MANY_THINGS],
    todo:
      "Draw the spiral again over the next few days. A measure that keeps landing outside the " +
      "typical range tells you more than one that did it once.",
  },
  {
    label: "Multiple measures outside typical range",
    meaning: [NOT_A_DIAGNOSIS, MANY_THINGS],
    todo:
      "If you have already noticed a change in how you move, these measurements are something " +
      "concrete to bring to a doctor. There is no disease-modifying therapy for Parkinson's today, " +
      "so this is not about urgency — earlier conversations mean earlier symptom management and " +
      "earlier access to clinical trials.",
  },
];

// Labels for the three-step result indicator on the results screen.
export const TIER_SHORT = ["Typical", "Some outside", "Multiple outside"];

// Keyed by SPIRAL_FEATURE_ORDER name; score-check.mjs asserts every key has
// an entry here with a group that exists in GROUPS.
export const MEASURES = {
  spiral_duration: { name: "Drawing time", group: "speed", hi: "Took longer than", lo: "Quicker than" },
  spiral_max_deviation: { name: "Largest wobble", group: "shape", hi: "Larger than", lo: "Smaller than" },
  spiral_mean_deviation: { name: "Average wobble", group: "shape", hi: "Larger than", lo: "Smaller than" },
  spiral_std_deviation: { name: "Wobble variation", group: "shape", hi: "More varied than", lo: "Steadier than" },
  spiral_major_reversals: { name: "Course corrections", group: "shape", hi: "More frequent than", lo: "Less frequent than" },
  spiral_mean_speed: { name: "Average speed", group: "speed", hi: "Faster than", lo: "Slower than" },
  spiral_std_speed: { name: "Speed variation", group: "speed", hi: "More varied than", lo: "Steadier than" },
  spiral_ldlj: { name: "Smoothness", group: "smoothness", hi: "Smoother than", lo: "Less smooth than" },
  spiral_sparc: { name: "Smoothness, second method", group: "smoothness", hi: "Smoother than", lo: "Less smooth than" },
  spiral_tremor_4_6: { name: "Tremor, 4–6 Hz", group: "tremor", hi: "Stronger than", lo: "Weaker than" },
  spiral_tremor_6_12: { name: "Tremor, 6–12 Hz", group: "tremor", hi: "Stronger than", lo: "Weaker than" },
  spiral_tremor_dominant_hz: { name: "Main wobble frequency", group: "tremor", hi: "Higher than", lo: "Lower than" },
};

export const GROUPS = [
  { id: "shape", title: "Shape", desc: "How closely your line followed a smooth spiral fitted to your own drawing." },
  { id: "speed", title: "Speed", desc: "How fast you drew, and how evenly." },
  { id: "smoothness", title: "Smoothness", desc: "How fluid the movement was, by two standard methods." },
  { id: "tremor", title: "Tremor", desc: "Small, fast, rhythmic wobble in the line." },
];

export function measureSentence(key, frac) {
  const { hi, lo } = MEASURES[key];
  const p = Math.round(frac * 100);
  return p >= 50 ? `${hi} ${p}% of the reference group` : `${lo} ${100 - p}% of the reference group`;
}

// The 50s bracket is everyone under 60 - training/neurotrace/collected.py: age_bracket.
const AGE_PHRASE = {
  all: "of all ages",
  "50s": "aged under 60",
  "60s": "aged 60 to 69",
  "70s": "aged 70 to 79",
  "80+": "aged 80 and over",
};

export function referenceSentence({ referenceN, bracketKey, deviceMatched }) {
  const base = `Compared with ${referenceN} healthy adults ${AGE_PHRASE[bracketKey]}.`;
  const device = deviceMatched
    ? " They drew on this kind of device."
    : " They drew on a different kind of device, so small differences may come from the device rather than from you.";
  return base + device;
}

export const AGE_CHOICES = [
  { label: "Under 60", bracket: "50s" },
  { label: "60–69", bracket: "60s" },
  { label: "70–79", bracket: "70s" },
  { label: "80 or over", bracket: "80+" },
  { label: "Prefer not to say", bracket: null },
];

// Verbatim safe sentences from ClaimsRules, used across the setup screens.
export const PITCH = "NeuroTrace turns an ordinary phone into a motor-function measurement tool.";
export const TRACKS = "It reports where each measure falls relative to a reference population and tracks how it changes over time.";
export const ON_DEVICE = "All analysis runs on the device. No motor data ever leaves the phone.";

// Screen sentences taken verbatim from the design mockups (*.dc.html), which
// were written against ClaimsRules. index.html pulls every sentence from this
// file through data-copy="KEY"; headings, legends and button/chip labels stay
// in the markup.
export const CONSENT_UNDERSTAND = "I understand this is a measurement tool, not a medical diagnosis.";
export const CONSENT_ADULT = "I am 18 years of age or older.";
export const CONSENT_HELP = "Tick both boxes to continue.";
export const ABOUT_WHY = "Used only to choose who you are compared with. Kept on this device.";
export const HAND_HELP = "The hand you will draw with. Use the same one each time so your check-ins compare fairly.";
export const CHECKIN_BLURB = "About two minutes. Draw a spiral with your finger or a stylus.";
export const HISTORY_EMPTY = "Your results will appear here after your first check-in. They stay on this device.";
export const DRAW_INSTRUCTION =
  "Start at the blue dot and follow the grey line outwards, at a comfortable pace. Lifting your " +
  "finger is fine — carry on from where you stopped.";
export const TOO_SHORT =
  "That spiral was too short to measure. Please draw the whole spiral, from the middle to the outside.";
export const COLLECT_INTRO =
  "Three spirals per participant, for the device-matched reference. No results are calculated or " +
  "shown in this mode.";
export const NEW_PARTICIPANT =
  "A random ID is made for them. Write it on their signed consent form — names are never stored.";
export const RETURNING_BLURB = "Pick up an ID already on this iPad.";
export const COLLECT_DRAW_INSTRUCTION =
  "Start at the dot in the middle and trace outwards at a comfortable pace. Lifting the pencil is " +
  "fine — carry on from where you stopped.";
export const SESSION_SAVED =
  "Three spirals are stored on this iPad. Thank the participant — no results are shown in collection mode.";

// Error screen (not in any mockup): its heading "We can't show results"
// (index.html) and this sentence are carried over from the previous app.js
// results-error copy. The old follow-on about going back to replay the
// drawing is dropped - there is no replay screen any more.
export const NOTHING_SCORED = "Nothing was scored.";

// Draw screen, when a resize wipes the trial (not in any mockup): worded in
// the task plan for the pad's resize guard. An instruction about the screen,
// nothing about the person, so no ClaimsRules sentence applies.
export const RESIZE_CLEARED = "The screen changed size, so this spiral was cleared. Please draw it again.";

// Results screen sentences - verbatim from Results.dc.html.
export const STOOD_OUT_CAPTION = "The measures that moved this result the most.";
export const EVERY_MEASURE_CAPTION =
  "Each dot shows where you sit among the reference group. The mark in the middle is the halfway point.";
export const RAW_LEGEND = "What the screen recorded.";
export const FILTERED_LEGEND =
  "The same line smoothed (100 Hz, 15 Hz low-pass) — the version every measure is taken from.";
export const SPEED_CAPTION = "From your first touch on the left to your last on the right.";
// Not in a mockup: store.js keeps raw drawings for the newest three check-ins only (handoff B6).
export const DRAWING_PRUNED = "The drawing itself is kept only for your three most recent check-ins.";

// Variant A (design canvas) - the plain line under the results verdict.
// Same claim as CONSENT_UNDERSTAND, ClaimsRules-safe.
export const RESULT_SUMMARY = "This is a measurement of how you drew today, not a diagnosis.";

// Settings and About tabs - new copy, written against ClaimsRules: it says
// what the software does and where the comparison comes from, nothing more.
export const SETTINGS_DETAILS_HELP = "Used to choose who you are compared with. Changes apply to your next check-in.";
export const APPEARANCE_HELP = "Automatic follows your device's setting.";
export const DELETE_HELP = "Removes every check-in saved on this device. This can't be undone.";
export const DELETE_CONFIRM = "Delete all check-ins? This can't be undone.";
export const DELETED = "All check-ins deleted.";
export const DELETE_FAILED = "Couldn't delete your check-ins. Try again.";
export const COLLECTION_HELP = "For the research team. Records spirals for the reference group and never shows results.";
export const HOW_STEPS = [
  "Trace a spiral on the screen with your finger or a stylus.",
  "NeuroTrace measures 12 things about the line: its shape, speed, smoothness and tremor.",
  "Each measure is placed among a reference group of healthy adults.",
];
export const CREDIT = "Made by Sanchit Bhadani and Aryan Modi for the 2026 Congressional App Challenge.";

// Motion, accent colours and the measuring overlay - new copy.
export const ACCENT_HELP = "Changes the colour of buttons, links and highlights.";
export const MOTION_HELP = "Reduced turns off moving effects. Automatic follows your device's setting.";
export const SAVED = "Saved";
export const SPIRAL_SAVED = (n) => `Spiral ${n} saved`;
export const MEASURING = "Measuring your spiral";
export const MEASURE_STEPS = [
  "Tidying up the line",
  "Smoothing out screen jitter",
  "Measuring 12 things about it",
  "Comparing with the reference group",
];
// Names match the swatch order in index.html.
export const ACCENTS = ["Blue", "Indigo", "Violet", "Teal", "Amber", "Rose", "Graphite"];

// Collection mode - new copy for the facilitator (docs/COLLECTED_FORMAT.md).
export const COLLECT_CONSENT = "Written consent for this participant is on file.";
export const DIAGNOSIS_NOTE =
  "Only participants with no diagnosis are added to the healthy reference. Everyone else is kept, labelled and left out of it.";
export const MED_HELP = "A rough answer is fine. Leave it empty if unsure.";
export const NO_PARTICIPANTS = "No participants on this iPad yet.";
export const UNEXPORTED_HELP = "They stay on this iPad until exported. Export before clearing Safari data.";
export const EXPORTED = "Exported";
export const LEAVE_SESSION = "Leave this session? The spirals drawn so far will be discarded.";
export const DIAGNOSES = { none: "None", parkinsons: "Parkinson\u2019s", essential_tremor: "Essential tremor", other: "Other" };
export const bracketNote = (age) =>
  age < 60 ? "Counts toward the under-60 reference group." :
  age >= 80 ? "Counts toward the 80+ reference group." :
  `Counts toward the ${Math.floor(age / 10) * 10}s reference group.`;

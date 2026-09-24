// Every user-facing string plus per-feature display metadata, in one file so
// it can be checked against Markdowns/NeuroTrace_ClaimsRules.md in one place
// (Global Constraint 10). Pure data + tiny string helpers - no DOM.

const NOT_A_DIAGNOSIS =
  "These are measurements of how you moved during the tasks, compared with other people who " +
  "took the same tasks. They are not a diagnosis and cannot tell you whether you have a " +
  "neurological condition.";

const MANY_THINGS =
  "Many things move these numbers — caffeine, fatigue, sleep, anxiety, medication timing, cold " +
  "hands, familiarity with the task. One drawing is a single reading, not a pattern.";

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

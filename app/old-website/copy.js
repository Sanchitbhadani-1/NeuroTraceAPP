// COPY.JS HOLDS THE WORDS THE APP SHOWS ON SCREEN
// IT HAS THE RESULT LEVELS, THE MEASURE NAMES, THE INSTRUCTIONS AND THE SENTENCES BUILT FROM A RESULT'S NUMBERS
// THE OTHER APP FILES IMPORT THEIR TEXT FROM HERE


// THE RESULT LEVELS AND THE NOTE THAT THIS IS NOT A DIAGNOSIS

// Shown with every result
export const NOT_A_DIAGNOSIS =
  "These are measurements of how you moved during the tasks, compared with other people who " +
  "took the same tasks. They are not a diagnosis and cannot tell you whether you have a " +
  "neurological condition.";

// Shown with results where a measure landed outside the typical range
const MANY_THINGS =
  "Many things move these numbers — caffeine, fatigue, sleep, anxiety, medication timing, cold " +
  "hands, familiarity with the task. One drawing is a single reading, not a pattern.";

// Just the first sentence of MANY_THINGS
export const MANY_THINGS_SHORT = MANY_THINGS.slice(0, MANY_THINGS.indexOf(".") + 1);

// The three result levels, each with its name, what it means and what to do next
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

// Short names for the three result levels
export const TIER_SHORT = ["Typical", "Some outside", "Multiple outside"];


// THE 12 SPIRAL MEASURES AND THEIR GROUPS

// Each measure's name, its group, and the words for landing higher or lower than the reference group
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

// The four groups the measures are shown in, with a title and a short description
export const GROUPS = [
  { id: "shape", title: "Shape", desc: "How closely your line followed a smooth spiral fitted to your own drawing." },
  { id: "speed", title: "Speed", desc: "How fast you drew, and how evenly." },
  { id: "smoothness", title: "Smoothness", desc: "How fluid the movement was, by two standard methods." },
  { id: "tremor", title: "Tremor", desc: "Small, fast, rhythmic wobble in the line." },
];


// Make the sentence for one measure from where it fell in the reference group, from 0 to 1
export function measureSentence(key, frac) {

  // Find the words for higher and lower, and turn the share into a percent
  const { hi, lo } = MEASURES[key];
  const p = Math.round(frac * 100);

  // At 50% or more use the higher words, and under 50% use the lower words with the rest of the group
  if (p >= 50) {
    return `${hi} ${p}% of the reference group`;
  }
  return `${lo} ${100 - p}% of the reference group`;
}


// WHO YOU ARE COMPARED WITH

// How each age group is said in a sentence
const AGE_PHRASE = {
  all: "of all ages",
  "50s": "aged under 60",
  "60s": "aged 60 to 69",
  "70s": "aged 70 to 79",
  "80+": "aged 80 and over",
};


// Make the sentence that says who you were compared with and whether they used the same kind of device
export function referenceSentence({ referenceN, bracketKey, deviceMatched }) {
  const base = `Compared with ${referenceN} healthy adults ${AGE_PHRASE[bracketKey]}.`;

  // Say whether the reference group drew on the same kind of device
  let device = " They drew on a different kind of device, so small differences may come from the device rather than from you.";
  if (deviceMatched) {
    device = " They drew on this kind of device.";
  }

  return base + device;
}


// The age choices, each with the age group it uses
export const AGE_CHOICES = [
  { label: "Under 60", bracket: "50s" },
  { label: "60–69", bracket: "60s" },
  { label: "70–79", bracket: "70s" },
  { label: "80 or over", bracket: "80+" },
  { label: "Prefer not to say", bracket: null },
];


// THE START, CONSENT AND CHECK-IN SCREENS

// What the app does
export const PITCH = "NeuroTrace turns an ordinary phone into a motor-function measurement tool.";
export const TRACKS = "It reports where each measure falls relative to a reference population and tracks how it changes over time.";
export const ON_DEVICE = "All analysis runs on the device. No motor data ever leaves the phone.";

// The consent boxes
export const CONSENT_UNDERSTAND = "I understand this is a measurement tool, not a medical diagnosis.";
export const CONSENT_ADULT = "I am 18 years of age or older.";
export const CONSENT_HELP = "Check both boxes to continue.";

// The age and hand choices, the check-in, and the empty history
export const ABOUT_WHY = "Used only to choose who you are compared with. Kept on this device.";
export const HAND_HELP = "The hand you will draw with. Use the same one each time so your check-ins compare fairly.";
export const CHECKIN_BLURB = "About two minutes. Draw a spiral with your finger or a stylus.";
export const HISTORY_EMPTY = "Your results will appear here after your first check-in. They stay on this device.";
export const DRAW_INSTRUCTION =
  "Start at the blue dot and follow the gray line outward, at a comfortable pace. Lifting your " +
  "finger is fine — keep going from where you stopped.";
export const TOO_SHORT =
  "That spiral was too short to measure. Please draw the whole spiral, from the middle to the outside.";

// Collection mode, where the research team records spirals for the reference group
export const COLLECT_INTRO =
  "Three spirals per participant, for the device-matched reference. No results are calculated or " +
  "shown in this mode.";
export const NEW_PARTICIPANT =
  "A random ID is made for them. Write it on their signed consent form — names are never stored.";
export const RETURNING_BLURB = "Pick up an ID already on this iPad.";
export const COLLECT_DRAW_INSTRUCTION =
  "Start at the dot in the middle and trace outward at a comfortable pace. Lifting the pencil is " +
  "fine — keep going from where you stopped.";
export const SESSION_SAVED =
  "Three spirals are stored on this iPad. Thank the participant — no results are shown in collection mode.";


// THE RESULT SCREEN

export const NOTHING_SCORED = "Nothing was scored.";
export const RESIZE_CLEARED = "The screen changed size, so this spiral was cleared. Please draw it again.";

// The captions under each part of the result
export const STOOD_OUT_CAPTION = "The measures that moved this result the most.";
export const EVERY_MEASURE_CAPTION =
  "Each dot shows where you sit among the reference group. The mark in the middle is the halfway point.";
export const RAW_LEGEND = "What the screen recorded.";
export const FILTERED_LEGEND =
  "The same line smoothed (100 Hz, 15 Hz low-pass) — the version every measure is taken from.";
export const SPEED_CAPTION = "From your first touch on the left to your last on the right.";
export const DRAWING_PRUNED = "The drawing itself is kept only for your three most recent check-ins.";
export const RESULT_SUMMARY = "This is a measurement of how you drew today, not a diagnosis.";


// SETTINGS AND THE HOW IT WORKS STEPS

export const SETTINGS_DETAILS_HELP = "Used to choose who you are compared with. Changes apply to your next check-in.";
export const APPEARANCE_HELP = "Automatic follows your device's setting.";

// Deleting every check-in
export const DELETE_HELP = "Removes every check-in saved on this device. This can't be undone.";
export const DELETE_CONFIRM = "Delete all check-ins? This can't be undone.";
export const DELETED = "All check-ins deleted.";
export const DELETE_FAILED = "Couldn't delete your check-ins. Try again.";

export const COLLECTION_HELP = "For the research team. Records spirals for the reference group and never shows results.";

// The three steps of how a check-in works
export const HOW_STEPS = [
  "Trace a spiral on the screen with your finger or a stylus.",
  "NeuroTrace measures 12 things about the line: its shape, speed, smoothness and tremor.",
  "Each measure is placed among a reference group of healthy adults.",
];

export const CREDIT = "Made by Sanchit Bhadani, Aryan Modi, and Mihir Malladi for the 2026 Congressional App Challenge.";


// LOGGING IN AND THE HOME PAGE SECTIONS

export const LOGIN_NOTE = "Accounts aren't set up yet. For now, logging in opens the app on this device.";
export const LOGOUT_HELP = "Accounts aren't set up yet. Logging out takes you back to the home page. Your check-ins stay on this device.";
export const TESTING_BLURB =
  "Short drawing tests that measure how you move. Use the same hand on the same device each time, so your results compare fairly.";
export const MED_BLURB = "The medicines you take, with the dose and when you take them.";
export const MED_NOT_SAVED = "Not saved yet. This part of the app is still being built.";


// TRAINING

export const TRAINING_BLURB = "Short practice exercises. Each one gets a little harder once you've mastered its current level.";
export const TRAINING_WHY = "Why this one: wobble was your most unusual measure in your Sep 30 check-in.";

// Labels for the parts of the training screen that show sample data for now
export const FOCUS_SAMPLE = "Sample. Picking today's exercise from your check-ins isn't built yet.";
export const WEEK_SAMPLE = "Sample. Practice days aren't counted yet.";

// The name of each exercise
export const EXERCISE_NAMES = {
  "big-writing": "Big writing",
  rhythm: "Rhythm",
  "steady-tracing": "Steady tracing",
  "hand-skills": "Hand skills",
};

// What to do in each exercise
export const INSTRUCTIONS = {
  "big-writing": "Write a row of tall loops, like a cursive l, from left to right. Make each loop touch the dashed line.",
  "steady-tracing":
    "Watch the dot trace the spiral, picture yourself drawing it, then trace it yourself from the middle out. " +
    "At higher levels the guide gets fainter.",
  rhythm: "Turn your sound on. After three clicks, a dot moves along the wave, one stroke per click. Keep your pen with the dot.",
  "hand-skills": "Circles appear one at a time and shrink away. Tap each one before it disappears.",
};

// What a screen reader says for each drawing area
export const PAD_LABELS = {
  "big-writing": "Writing area with a baseline and a dashed target line",
  "steady-tracing": "Tracing area with a spiral guide",
  rhythm: "Tracing area with a wave and a dot to follow",
};


// THE STEPS OF STEADY TRACING, RHYTHM AND HAND SKILLS

export const WATCH = "Watch the dot trace the spiral.";
export const LOOK = "Look at the spiral, from the middle out.";


// Ask the user to picture drawing the spiral, with the seconds left as n
export function imagine(n) {
  return `Now picture yourself drawing it. ${n}`;
}


export const TRACE_NOW = "Your turn. Trace it from the middle out.";
export const RHYTHM_READY = "Tap Start, then put your pen on the dot before it moves.";


// Count down before the rhythm dot starts moving, with the clicks left as n
export function getReady(n) {
  return `Get ready. ${n}`;
}


export const FOLLOW = "Follow the dot.";
export const RHYTHM_END = "That's the end of the wave. Tap Done.";
export const TARGETS_READY = "Tap Start when you're ready.";


// Say which circle this is out of how many
export function circleOf(n, of) {
  return `Circle ${n} of ${of}`;
}


// Shown when a try was too short to count
export const TRACE_TOO_SHORT = "Too little of the spiral to count. Trace it from the middle all the way out.";
export const RHYTHM_TOO_SHORT = "Too little of the wave to count. Follow the dot all the way to the end.";

export const COMING_SOON = "Coming soon";
export const NOT_STARTED = "Not started";


// LEVELS AND THE RESULT OF A TRY

// Whether the level went up or down after the last try
export const LAST_CHANGE = { up: "Went up last time", down: "Went down last time" };


// Make the short level label
export function levelShort(n) {
  return `Level ${n}`;
}


// Make the level label with the number of levels
export function levelOf(n, of) {
  return `Level ${n} of ${of}`;
}


// Say how many hits there are so far out of how many are needed to move up
export function hitsSoFar(hits, need) {
  return `Hits at this level: ${hits} of ${need}`;
}


// Say how many misses in a row there are out of how many move the level down
export function missesInARow(misses, limit) {
  return `Misses in a row: ${misses} of ${limit}`;
}


export const TOP_LEVEL = "Top level. Keep practicing to hold it.";
export const TARGET_LABEL = "Reach this line";
export const TOO_FEW_LOOPS = "Too few loops to count. Write at least 4 tall loops across the row.";

// The verdict at the top of a try
export const VERDICT_HIT = "Hit";
export const VERDICT_MISS = "Not yet";

// The verdict when the target was reached but the try still didn't count as a hit
export const VERDICT_NOT_COUNTED = {
  "big-writing": "Reached the line, but not counted",
  "steady-tracing": "Accurate, but not counted",
  rhythm: "On the beat, but not counted",
};

// Shown when the pace dropped compared with recent tries
export const SLOWER_NOTES = {
  "big-writing": "Your pace dropped compared with your recent tries. Keep your usual rhythm as you write bigger.",
  "steady-tracing": "Your pace dropped compared with your recent tries. Keep your usual pace as the guide fades.",
};

// Shown when the line was less smooth than in recent tries
export const SHAKIER_NOTES = {
  "big-writing": "Your writing was less smooth than in your recent tries. Keep the loops smooth as you write bigger.",
  "steady-tracing": "Your line was less smooth than in your recent tries. Keep it smooth as the guide fades.",
  rhythm: "Your line was less smooth than in your recent tries. Keep it smooth as you follow the dot.",
};

// The name of each measure shown under a try
export const MEASURE_NAMES = {
  size: "Size",
  accuracy: "Accuracy",
  pace: "Pace",
  smoothness: "Smoothness",
  coverage: "How much you traced",
  timing: "Keeping up",
  caught: "Caught",
  reaction: "Speed",
  extra: "Extra taps",
};


// THE SENTENCES UNDER EACH MEASURE OF A TRY

// Turn a share like 0.25 or -0.25 into a whole percent without the sign, like 25
function pct(x) {
  return Math.round(Math.abs(x) * 100);
}


// Say "it doesn't" for one and "they don't" for more than one
function dontCount(n) {
  if (n === 1) {
    return "it doesn't";
  }
  return "they don't";
}


// Make the sentence that says how many loops reached the target line
// open is how many were spikes or bumps, and below is how many dipped well below the baseline
export function reachedLine(reached, loops, open = 0, below = 0) {

  // Call them letters if any of them weren't real loops
  let kind = "loops";
  if (open || below) {
    kind = "letters";
  }
  let message = `${reached} of ${loops} ${kind} reached the line.`;

  // Say how many were spikes or bumps
  if (open) {
    let shape = "were spikes or bumps";
    let loop = "loops";
    if (open === 1) {
      shape = "was a spike or bump";
      loop = "a loop";
    }
    message += ` ${open} ${shape}, not ${loop}, so ${dontCount(open)} count.`;
  }

  // Say how many dipped well below the baseline
  if (below) {
    message += ` ${below} started or ended well below the baseline, so ${dontCount(below)} count.`;
  }

  return message + " Filled dots on your writing mark the ones that reached it.";
}


export const PRACTICE_EXPORT_HELP = "Saves every practice try on this device as one file, to help tune the exercises.";
export const NO_PRACTICE = "No practice tries on this device yet";


// Make the sentence about the loops' size, and how much they shrank or grew along the row
export function sizeSentence(size, shrink) {
  let sentence = `Your loops averaged ${pct(size)}% of the target height.`;

  // Only mention a change of 5% or more
  if (Number.isFinite(shrink) && Math.abs(shrink) >= 0.05) {
    let change = "bigger";
    if (shrink < 0) {
      change = "smaller";
    }
    sentence += ` The last loops in the row were ${pct(shrink)}% ${change} than the first.`;
  }

  return sentence;
}


// Say "faster" when the change is above 0 and "slower" when it isn't
function fasterOrSlower(vs) {
  if (vs > 0) {
    return "faster";
  }
  return "slower";
}


// Make the sentence about the pace, compared with recent tries
export function paceSentence(pace, vs) {
  const start = `${pace.toFixed(1)} loops a second`;

  // With no recent tries there is nothing to compare with
  if (vs == null) {
    return start + ". Nothing to compare with yet.";
  }

  // Under 5% either way counts as the same
  if (Math.abs(vs) < 0.05) {
    return start + ", about the same as your recent tries.";
  }

  return start + `, ${pct(vs)}% ${fasterOrSlower(vs)} than your recent tries.`;
}


// Make the sentence about smoothness, compared with recent tries
export function smoothSentence(vs) {
  if (vs == null) {
    return "Nothing to compare with yet.";
  }

  // Under 5% either way counts as the same
  if (Math.abs(vs) < 0.05) {
    return "About as smooth as your recent tries.";
  }

  if (vs > 0) {
    return "Smoother than your recent tries.";
  }
  return "Less smooth than your recent tries.";
}


// Make the sentence about pace for exercises without a loops a second number
export function paceVs(vs) {
  if (vs == null) {
    return "Nothing to compare with yet.";
  }

  // Under 5% either way counts as the same
  if (Math.abs(vs) < 0.05) {
    return "About the same pace as your recent tries.";
  }

  return `${pct(vs)}% ${fasterOrSlower(vs)} than your recent tries.`;
}


// Turn a share into a percent, saying "less than 1" for anything under half a percent
function share(x) {
  if (x < 0.005) {
    return "less than 1";
  }
  return String(pct(x));
}


// Make the sentence about how far the line was from the spiral guide
export function tracingAccuracy(acc, limit) {
  return `On average your line was ${share(acc)}% of the spiral's size away from the guide. A hit needs ${pct(limit)}% or less.`;
}


// Make the sentence about how much of the spiral or wave was traced
export function tracedShare(cover, what) {
  return `You traced ${pct(cover)}% of the ${what}.`;
}


// Make the sentence about keeping up with the rhythm dot
// lag is how many beats away from the dot the pen was, and lead is below 0 when the pen was behind it
export function keptUp(lag, lead, limit) {
  if (lag < 0.15) {
    return "You kept up with the dot.";
  }

  let side = "ahead of";
  if (lead < 0) {
    side = "behind";
  }

  return `On average you were ${lag.toFixed(1)} beats from the dot, mostly ${side} it. ` +
    `A hit needs ${limit} or less.`;
}


// Make the sentence about how far the line was from the wave
export function waveNear(near, limit) {
  return `On average your line was ${share(near)}% of the wave's height away from it. A hit needs ${pct(limit)}% or less.`;
}


// Make the sentence about how many circles were caught
export function caughtSentence(caught, of, need) {
  return `You caught ${caught} of ${of} circles. A hit needs ${need}.`;
}


// Make the sentence about how fast the circles were tapped, from the time in milliseconds
export function reactionSentence(ms) {
  if (!Number.isFinite(ms)) {
    return "No circles caught yet.";
  }
  return `You typically tapped a circle ${(ms / 1000).toFixed(2)} seconds after it appeared.`;
}


// Make the sentence about taps that missed every circle, and how many a hit allows
export function extraTapsSentence(n, allowed) {
  let sentence = "Every tap landed on a circle.";
  if (n !== 0) {
    let plural = "s";
    if (n === 1) {
      plural = "";
    }
    sentence = `${n} tap${plural} missed every circle.`;
  }

  if (allowed > 0) {
    sentence += ` A hit allows ${allowed} or fewer.`;
  } else {
    sentence += " A hit allows none.";
  }

  return sentence;
}


// LEVEL CHANGES

// What changes at the next level of each exercise
export const LEVEL_UP = {
  "big-writing": (n) => `Level up. Level ${n} has a taller target line.`,
  "steady-tracing": (n) => `Level up. Level ${n}'s guide is fainter.`,
  rhythm: (n) => `Level up. Level ${n} has a faster beat.`,
  "hand-skills": (n) => `Level up. Level ${n}'s circles start smaller.`,
};


// Start the sentence for moving down a level
function downTo(n) {
  return `Three misses in a row, so you're back to Level ${n}.`;
}


// What changes after moving down a level in each exercise
export const LEVEL_DOWN = {
  "big-writing": (n) => `${downTo(n)} The target line is a little lower.`,
  "steady-tracing": (n) => `${downTo(n)} The guide is a little clearer.`,
  rhythm: (n) => `${downTo(n)} The beat is a little slower.`,
  "hand-skills": (n) => `${downTo(n)} The circles start a little bigger.`,
};


// Shown after picking too hard today
export function tooHardToast(n) {
  return `Level ${n} for today`;
}


export const NOT_BUILT = "Not built yet";


// THE PROGRESS SCREEN

export const PROGRESS_BLURB = "Your first check-in next to your latest, measure by measure.";
export const PROGRESS_EMPTY = "Do two check-ins with the same hand and the same pen or finger to compare them here.";
export const PROGRESS_CAPTION =
  "Both check-ins are placed against the same reference group, so the comparison is fair. Single check-ins vary " +
  "from day to day, so a change between two of them is one reading, not a trend.";

// How each kind of input is said in a sentence
const INPUT_PHRASE = { pencil: "an Apple Pencil", touch: "a finger", mouse: "a mouse" };


// Say how long a spiral took to draw
export function drawnIn(seconds) {
  return `Drawn in ${seconds.toFixed(1)} seconds`;
}


export const REPLAY_MISSING = "No drawing was kept for this check-in.";


// Say which hand and input the compared check-ins used
export function progressSetup(hand, inputType) {
  return `Comparing check-ins drawn with your ${hand} hand, using ${INPUT_PHRASE[inputType] ?? "the same input"}.`;
}


// APPEARANCE AND THE MEASURING SCREEN

export const ACCENT_HELP = "Changes the color of buttons, links and highlights.";
export const MOTION_HELP = "Reduced turns off moving effects. Automatic follows your device's setting.";
export const SAVED = "Saved";


// Say which spiral was just saved
export function SPIRAL_SAVED(n) {
  return `Spiral ${n} saved`;
}


export const MEASURING = "Measuring your spiral";

// The steps shown while a spiral is measured
export const MEASURE_STEPS = [
  "Cleaning up the line",
  "Smoothing out screen jitter",
  "Measuring 12 things about it",
  "Comparing with the reference group",
];

// The accent colors to pick from
export const ACCENTS = ["Blue", "Indigo", "Violet", "Teal", "Amber", "Rose", "Graphite"];


// THE COLLECTION MODE SCREENS

export const COLLECT_CONSENT = "Written consent for this participant is on file.";
export const DIAGNOSIS_NOTE =
  "Only participants with no diagnosis are added to the healthy reference. Everyone else is kept, labeled and left out of it.";
export const MED_HELP = "A rough answer is fine. Leave it empty if unsure.";
export const NO_PARTICIPANTS = "No participants on this iPad yet.";
export const UNEXPORTED_HELP = "They stay on this iPad until exported. Export before clearing Safari data.";
export const EXPORTED = "Exported";
export const LEAVE_SESSION = "Leave this session? The spirals drawn so far will be discarded.";

// The diagnosis choices for a participant
export const DIAGNOSES = {
  none: "None",
  parkinsons: "Parkinson\u2019s",
  essential_tremor: "Essential tremor",
  other: "Other",
};


// Say which age group a participant's age counts toward
export function bracketNote(age) {
  if (age < 60) {
    return "Counts toward the under-60 reference group.";
  }
  if (age >= 80) {
    return "Counts toward the 80+ reference group.";
  }
  return `Counts toward the ${Math.floor(age / 10) * 10}s reference group.`;
}
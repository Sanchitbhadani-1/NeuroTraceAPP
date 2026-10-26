// SCORE.JS TURNS A CHECK-IN'S MEASUREMENTS INTO A RESULT
// IT CHECKS THE SCORING FILES, PICKS THE AGE GROUP TO COMPARE WITH, AVERAGES THE SPIRALS AND SCORES THEM
// EACH MEASURE IS ALSO PLACED AMONG THE REFERENCE GROUP, AND THE THREE THAT MOVED THE RESULT THE MOST ARE PICKED OUT

// Where the result levels change, so a score under 75% of the group is level 0, under 95% is level 1, and the rest is level 2
export const TIER_CUTS = [0.75, 0.95];


// Check that model.json and reference.json match this version of the app, and throw a clear error if they don't
// featureOrder is the list of measures the app makes, in order
export function checkScoringFiles(model, reference, featureOrder) {
  const order = featureOrder.join(",");
  const reExport = "Re-export with training/scripts/export_model.py.";

  // The model has to be version 2
  if (model.version !== 2) {
    throw new Error(`model.json version is ${model.version}, expected 2. ${reExport}`);
  }

  // The model has to use the same measures in the same order
  if (!model.featureOrder || model.featureOrder.join(",") !== order) {
    throw new Error(
      `model.json featureOrder [${(model.featureOrder || []).join(", ")}] does not match ` +
      `the app's feature order [${featureOrder.join(", ")}]. ${reExport}`
    );
  }

  // The model needs one weight for each measure, and a bias
  if (model.weights.length !== featureOrder.length) {
    throw new Error(
      `model.json weights has ${model.weights.length} entries, expected ${featureOrder.length}. ${reExport}`
    );
  }
  if (typeof model.bias !== "number") {
    throw new Error(`model.json bias is ${typeof model.bias}, expected a number. ${reExport}`);
  }

  // The reference has to be version 2, with the same measures in the same order
  if (reference.version !== 2) {
    throw new Error(`reference.json version is ${reference.version}, expected 2. ${reExport}`);
  }
  if (!reference.featureOrder || reference.featureOrder.join(",") !== order) {
    throw new Error(
      `reference.json featureOrder [${(reference.featureOrder || []).join(", ")}] does not match ` +
      `the app's feature order [${featureOrder.join(", ")}]. ${reExport}`
    );
  }

  // The reference needs a group for all ages
  if (!reference.brackets || !reference.brackets.all) {
    throw new Error(`reference.json is missing brackets.all. ${reExport}`);
  }

  // Every age group needs an average and a spread for each measure, every measure's values, and the scores
  for (const [key, block] of Object.entries(reference.brackets)) {
    if (block.mean.length !== featureOrder.length || block.sd.length !== featureOrder.length) {
      throw new Error(`reference.json brackets.${key} has a mean/sd of the wrong length. ${reExport}`);
    }
    for (const k of featureOrder) {
      if (!Array.isArray(block.features?.[k])) {
        throw new Error(`reference.json brackets.${key}.features is missing "${k}". ${reExport}`);
      }
    }
    if (!Array.isArray(block.score)) {
      throw new Error(`reference.json brackets.${key} is missing its score array. ${reExport}`);
    }
  }
}


// Pick the age group to compare with
// All ages are used when no group is given, or when the group has fewer people than minBracketN
export function bracketFor(reference, bracketKey) {
  let key = "all";
  if (bracketKey !== undefined && bracketKey !== null) {
    key = bracketKey;
  }

  const block = reference.brackets[key];
  if (block && block.n >= reference.minBracketN) {
    return { key, block };
  }
  return { key: "all", block: reference.brackets.all };
}


// Average each measure over a check-in's spirals, skipping spirals where it couldn't be measured
// A measure with no number on any spiral comes back as NaN
export function averageFeatures(perTrial, featureOrder) {
  const out = {};
  for (const k of featureOrder) {
    let sum = 0;
    let n = 0;
    for (const trial of perTrial) {
      const v = trial[k];
      if (Number.isFinite(v)) {
        sum += v;
        n++;
      }
    }

    if (n > 0) {
      out[k] = sum / n;
    } else {
      out[k] = NaN;
    }
  }
  return out;
}


// Find the share of values that are below v
export function fractionBelow(v, values) {
  let count = 0;
  for (const x of values) {
    if (x < v) {
      count++;
    }
  }
  return count / values.length;
}


// Score a check-in from its spirals' measures, the model and the reference group
export function scoreSession(perTrial, model, reference, bracketKey) {

  // Average the spirals and pick the age group to compare with
  const features = averageFeatures(perTrial, model.featureOrder);
  const { key, block } = bracketFor(reference, bracketKey);

  // Turn each measure into how many spreads it is from the group's average, then multiply it by its weight
  // A measure that is missing, or whose group has no usable spread, counts as exactly average
  const weighted = [];
  for (let i = 0; i < model.featureOrder.length; i++) {
    const f = features[model.featureOrder[i]];
    const sd = block.sd[i];
    let z = 0;
    if (Number.isFinite(f) && sd > 0 && Number.isFinite(sd)) {
      z = (f - block.mean[i]) / sd;
    }
    weighted.push(model.weights[i] * z);
  }

  // Add up the weighted measures and the bias, and squash the total into a score from 0 to 1
  let total = 0;
  for (const w of weighted) {
    total += w;
  }
  const zsum = model.bias + total;
  const score = 1 / (1 + Math.exp(-zsum));

  // Place the score among the reference group's scores, and pick the result level from that
  const scorePct = fractionBelow(score, block.score);
  let tier = 2;
  if (scorePct < TIER_CUTS[0]) {
    tier = 0;
  } else if (scorePct < TIER_CUTS[1]) {
    tier = 1;
  }

  // Place each measure that has a number among the reference group's values for it
  const measurePct = {};
  for (const k of model.featureOrder) {
    if (Number.isFinite(features[k])) {
      measurePct[k] = fractionBelow(features[k], block.features[k]);
    }
  }

  // Find the measures with a number, sorted by how much they moved the score up
  const signals = [];
  for (let i = 0; i < model.featureOrder.length; i++) {
    const k = model.featureOrder[i];
    if (Number.isFinite(features[k])) {
      signals.push({ k, signal: weighted[i] });
    }
  }
  signals.sort((a, b) => b.signal - a.signal);

  // Keep the top three
  const topSignals = [];
  for (const s of signals.slice(0, 3)) {
    topSignals.push(s.k);
  }

  return {
    features,
    bracketKey: key,
    referenceN: block.n,
    deviceMatched: reference.deviceMatched === true,
    trialsPerSession: reference.trialsPerSession,
    tier,
    measurePct,
    topSignals,
    score,
    scorePct,
  };
}
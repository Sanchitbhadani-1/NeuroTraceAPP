export const TIER_CUTS = [0.75, 0.95];

export function checkScoringFiles(model, reference, featureOrder) {
  const order = featureOrder.join(",");
  const reExport = "Re-export with training/scripts/export_model.py.";

  if (model.version !== 2) {
    throw new Error(`model.json version is ${model.version}, expected 2. ${reExport}`);
  }
  if (!model.featureOrder || model.featureOrder.join(",") !== order) {
    throw new Error(
      `model.json featureOrder [${(model.featureOrder || []).join(", ")}] does not match ` +
      `the app's feature order [${featureOrder.join(", ")}]. ${reExport}`
    );
  }
  if (model.weights.length !== featureOrder.length) {
    throw new Error(
      `model.json weights has ${model.weights.length} entries, expected ${featureOrder.length}. ${reExport}`
    );
  }
  if (typeof model.bias !== "number") {
    throw new Error(`model.json bias is ${typeof model.bias}, expected a number. ${reExport}`);
  }

  if (reference.version !== 2) {
    throw new Error(`reference.json version is ${reference.version}, expected 2. ${reExport}`);
  }
  if (!reference.featureOrder || reference.featureOrder.join(",") !== order) {
    throw new Error(
      `reference.json featureOrder [${(reference.featureOrder || []).join(", ")}] does not match ` +
      `the app's feature order [${featureOrder.join(", ")}]. ${reExport}`
    );
  }
  if (!reference.brackets || !reference.brackets.all) {
    throw new Error(`reference.json is missing brackets.all. ${reExport}`);
  }
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

export function bracketFor(reference, bracketKey) {
  const key = bracketKey ?? "all";
  const block = reference.brackets[key];
  if (block && block.n >= reference.minBracketN) return { key, block };
  return { key: "all", block: reference.brackets.all };
}

export function averageFeatures(perTrial, featureOrder) {
  const out = {};
  for (const k of featureOrder) {
    let sum = 0, n = 0;
    for (const trial of perTrial) {
      const v = trial[k];
      if (Number.isFinite(v)) { sum += v; n++; }
    }
    out[k] = n > 0 ? sum / n : NaN;
  }
  return out;
}

export function fractionBelow(v, values) {
  let count = 0;
  for (const x of values) if (x < v) count++;
  return count / values.length;
}

export function scoreSession(perTrial, model, reference, bracketKey) {
  const features = averageFeatures(perTrial, model.featureOrder);
  const { key, block } = bracketFor(reference, bracketKey);

  const weighted = model.featureOrder.map((k, i) => {
    const f = features[k];
    const sd = block.sd[i];
    const z = Number.isFinite(f) && sd > 0 && Number.isFinite(sd) ? (f - block.mean[i]) / sd : 0;
    return model.weights[i] * z;
  });
  const zsum = model.bias + weighted.reduce((a, b) => a + b, 0);
  const score = 1 / (1 + Math.exp(-zsum));

  const scorePct = fractionBelow(score, block.score);
  const tier = scorePct < TIER_CUTS[0] ? 0 : scorePct < TIER_CUTS[1] ? 1 : 2;

  const measurePct = {};
  model.featureOrder.forEach((k) => {
    if (Number.isFinite(features[k])) measurePct[k] = fractionBelow(features[k], block.features[k]);
  });

  const topSignals = model.featureOrder
    .map((k, i) => ({ k, signal: weighted[i] }))
    .filter((s) => Number.isFinite(features[s.k]))
    .sort((a, b) => b.signal - a.signal)
    .slice(0, 3)
    .map((s) => s.k);

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

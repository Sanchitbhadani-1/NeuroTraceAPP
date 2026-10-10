// storage: IndexedDB history (assessments, collected sessions) + localStorage
// prefs. pure functions where possible, and every DB function opens, does its
// work, then closes in `finally` (same shape as app.js's old history section).

const DB_NAME = "neurotrace";
const DB_VERSION = 3;
const STORE_ASSESSMENTS = "assessments"; // v1 store - keyPath "id", autoIncrement
const STORE_COLLECTED = "collected";
const STORE_TRAINING = "training"; // v3 - one record per counted training try

// features + score are a few hundred bytes so they're kept for good - they're
// the whole point of measuring over time. raw samples are ~100 KB each, so
// only the newest RAW_KEEP assessments hold on to theirs (handoff B6). each
// trial's `path`, a 60 Hz copy of the drawing for replay (a few KB), is kept
// for good like the features.
const RAW_KEEP = 3;

const request = (req) => new Promise((resolve, reject) => {
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});

const txDone = (tx) => new Promise((resolve, reject) => {
  tx.oncomplete = () => resolve();
  tx.onerror = tx.onabort = () => reject(tx.error);
});

function openDb() {
  const req = indexedDB.open(DB_NAME, DB_VERSION);
  req.onupgradeneeded = () => {
    const db = req.result;
    // upgrading from v1 already leaves "assessments" in place - never touch it.
    if (!db.objectStoreNames.contains(STORE_ASSESSMENTS)) {
      db.createObjectStore(STORE_ASSESSMENTS, { keyPath: "id", autoIncrement: true });
    }
    if (!db.objectStoreNames.contains(STORE_COLLECTED)) {
      db.createObjectStore(STORE_COLLECTED, { keyPath: "id", autoIncrement: true });
    }
    if (!db.objectStoreNames.contains(STORE_TRAINING)) {
      db.createObjectStore(STORE_TRAINING, { keyPath: "id", autoIncrement: true });
    }
  };
  return request(req);
}

// ---------- assessments (personal-mode history) ----------

export async function saveAssessment(record) {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_ASSESSMENTS, "readwrite");
    const store = tx.objectStore(STORE_ASSESSMENTS);
    const addReq = store.add(record);
    // same transaction, so the cursor below already sees the record we just added.
    // strip raw traces from everything past the newest RAW_KEEP. older v1
    // records with no `trials` field get left alone.
    let seen = 0;
    store.openCursor(null, "prev").onsuccess = (ev) => {
      const cur = ev.target.result;
      if (!cur) return;
      if (++seen > RAW_KEEP && cur.value.trials) {
        const trials = cur.value.trials.map(({ samples, strokeStarts, ...rest }) => rest);
        cur.update({ ...cur.value, trials });
      }
      cur.continue();
    };
    await txDone(tx);
    return addReq.result;
  } finally {
    db.close();
  }
}

export async function listAssessments() {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_ASSESSMENTS, "readonly");
    const all = await request(tx.objectStore(STORE_ASSESSMENTS).getAll());
    await txDone(tx);
    // pre-v2 dev records have no `result` - nothing v2 can show for them.
    return all.filter((r) => r.result).reverse();
  } finally {
    db.close();
  }
}

export async function getAssessment(id) {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_ASSESSMENTS, "readonly");
    const rec = await request(tx.objectStore(STORE_ASSESSMENTS).get(id));
    await txDone(tx);
    return rec;
  } finally {
    db.close();
  }
}

// Settings > Delete all check-ins. collected research sessions are a separate
// store so they stay untouched.
export async function clearAssessments() {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_ASSESSMENTS, "readwrite");
    tx.objectStore(STORE_ASSESSMENTS).clear();
    await txDone(tx);
  } finally {
    db.close();
  }
}

// ---------- collected (research-mode sessions) ----------

export async function saveCollected(session) {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_COLLECTED, "readwrite");
    const id = await request(tx.objectStore(STORE_COLLECTED).add(session));
    await txDone(tx);
    return id;
  } finally {
    db.close();
  }
}

export async function listCollected() {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_COLLECTED, "readonly");
    const all = await request(tx.objectStore(STORE_COLLECTED).getAll());
    await txDone(tx);
    return all.reverse();
  } finally {
    db.close();
  }
}

export async function markExported(ids) {
  const db = await openDb();
  try {
    const idSet = new Set(ids);
    const tx = db.transaction(STORE_COLLECTED, "readwrite");
    tx.objectStore(STORE_COLLECTED).openCursor().onsuccess = (ev) => {
      const cur = ev.target.result;
      if (!cur) return;
      if (idSet.has(cur.value.id)) cur.update({ ...cur.value, exported: true });
      cur.continue();
    };
    await txDone(tx);
  } finally {
    db.close();
  }
}

export async function subjects() {
  const sessions = await listCollected(); // newest first already
  const bySubject = new Map();
  for (const s of sessions) {
    const entry = bySubject.get(s.subjectId);
    if (entry) entry.sessions++;
    // the first time we see a subject is its most recent session, since
    // `sessions` is already newest-first - so insertion order into this Map
    // is newest-lastAt-first too.
    else bySubject.set(s.subjectId, { subjectId: s.subjectId, sessions: 1, lastAt: s.collectedAt });
  }
  return [...bySubject.values()];
}

// 6 lowercase hex chars, never a name and never derived from one (privacy
// contract). `existing` is a Set of ids already assigned on this device.
export function newSubjectId(existing) {
  let id;
  do {
    const bytes = crypto.getRandomValues(new Uint8Array(3));
    id = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  } while (existing.has(id));
  return id;
}

// ---------- training ----------
// every counted try is kept (measures plus a small replay path, a few KB),
// in its own store so "Delete all check-ins" leaves practice alone.

export async function saveTrainingTry(record) {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_TRAINING, "readwrite");
    const id = await request(tx.objectStore(STORE_TRAINING).add(record));
    await txDone(tx);
    return id;
  } finally {
    db.close();
  }
}

// one exercise's tries, or every exercise's when none is named, newest first.
export async function listTrainingTries(exercise) {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_TRAINING, "readonly");
    const all = await request(tx.objectStore(STORE_TRAINING).getAll());
    await txDone(tx);
    return (exercise ? all.filter((r) => r.exercise === exercise) : all).reverse();
  } finally {
    db.close();
  }
}

// each exercise's level state (train.js newLevelState) in localStorage, read
// on every visit. null for an exercise not started yet.
const TRAINING_KEY = "neurotrace:training";

function trainingStates() {
  try {
    return JSON.parse(localStorage.getItem(TRAINING_KEY) || "{}");
  } catch {
    return {};
  }
}

export const getTrainingState = (exercise) => trainingStates()[exercise] ?? null;

export function setTrainingState(exercise, state) {
  try {
    localStorage.setItem(TRAINING_KEY, JSON.stringify({ ...trainingStates(), [exercise]: state }));
  } catch {
    // private mode or blocked storage: the level just doesn't persist
  }
}

// ---------- prefs (localStorage) ----------

const PREFS_KEY = "neurotrace:prefs";
// signedIn is a placeholder until accounts exist: it only decides whether the
// signed-out home or the tabs are shown.
const PREFS_DEFAULTS = { onboarded: false, consented: false, signedIn: false, ageChoice: null, hand: "right", theme: "auto", accent: "blue", motion: "auto" };

// private mode / blocked storage throws on read or write - never let that
// take down the app, js fall back to defaults.
export function getPrefs() {
  try {
    const raw = localStorage.getItem(PREFS_KEY);
    return raw ? { ...PREFS_DEFAULTS, ...JSON.parse(raw) } : { ...PREFS_DEFAULTS };
  } catch {
    return { ...PREFS_DEFAULTS };
  }
}

export function setPrefs(patch) {
  try {
    localStorage.setItem(PREFS_KEY, JSON.stringify({ ...getPrefs(), ...patch }));
  } catch {
    // ignoring it - next read js falls back to defaults
  }
}

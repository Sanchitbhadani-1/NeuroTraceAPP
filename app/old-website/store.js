// STORE.JS SAVES EVERYTHING ON THE DEVICE
// CHECK-INS, COLLECTION SESSIONS AND PRACTICE TRIES GO IN THE BROWSER'S DATABASE, AND SETTINGS GO IN LOCAL STORAGE

// The database's name and version, and its three stores
const DB_NAME = "neurotrace";
const DB_VERSION = 3;
const STORE_ASSESSMENTS = "assessments";
const STORE_COLLECTED = "collected";
const STORE_TRAINING = "training";

// How many of the latest check-ins keep their drawing points
const RAW_KEEP = 3;


// Wait for a database request to finish and give back its result
function request(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}


// Wait for a transaction to finish, and fail if it errors or is stopped
function txDone(tx) {
  return new Promise((resolve, reject) => {
    const fail = () => reject(tx.error);
    tx.oncomplete = () => resolve();
    tx.onerror = fail;
    tx.onabort = fail;
  });
}


// Open the database, and make any store that doesn't exist yet
function openDb() {
  const req = indexedDB.open(DB_NAME, DB_VERSION);

  // This runs the first time the database opens, and whenever DB_VERSION goes up
  req.onupgradeneeded = () => {
    const db = req.result;
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


// CHECK-INS

// Save a check-in and give back its id
// Check-ins older than the latest RAW_KEEP lose their drawing points, but keep everything else
export async function saveAssessment(record) {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_ASSESSMENTS, "readwrite");
    const store = tx.objectStore(STORE_ASSESSMENTS);
    const addReq = store.add(record);

    // Go through the check-ins from newest to oldest
    let seen = 0;
    store.openCursor(null, "prev").onsuccess = (ev) => {
      const cur = ev.target.result;
      if (!cur) {
        return;
      }

      // Past the latest RAW_KEEP, take the points and stroke starts out of each spiral
      seen++;
      if (seen > RAW_KEEP && cur.value.trials) {
        const trials = [];
        for (const { samples, strokeStarts, ...rest } of cur.value.trials) {
          trials.push(rest);
        }
        cur.update({ ...cur.value, trials });
      }
      cur.continue();
    };

    // Give back the new check-in's id once everything is saved
    await txDone(tx);
    return addReq.result;
  } finally {
    db.close();
  }
}


// Give back every check-in that has a result, newest first
export async function listAssessments() {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_ASSESSMENTS, "readonly");
    const all = await request(tx.objectStore(STORE_ASSESSMENTS).getAll());
    await txDone(tx);

    // Skip check-ins that were never scored
    const scored = [];
    for (const r of all) {
      if (r.result) {
        scored.push(r);
      }
    }
    return scored.reverse();
  } finally {
    db.close();
  }
}


// Give back one check-in by its id
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


// Delete every check-in
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


// COLLECTION MODE SESSIONS

// Save a collection session and give back its id
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


// Give back every collection session, newest first
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


// Mark the collection sessions with these ids as exported
export async function markExported(ids) {
  const db = await openDb();
  try {
    const idSet = new Set(ids);
    const tx = db.transaction(STORE_COLLECTED, "readwrite");
    tx.objectStore(STORE_COLLECTED).openCursor().onsuccess = (ev) => {
      const cur = ev.target.result;
      if (!cur) {
        return;
      }
      if (idSet.has(cur.value.id)) {
        cur.update({ ...cur.value, exported: true });
      }
      cur.continue();
    };
    await txDone(tx);
  } finally {
    db.close();
  }
}


// List each participant once, with how many sessions they have and when their newest one was collected
export async function subjects() {
  const sessions = await listCollected();
  const bySubject = new Map();
  for (const s of sessions) {
    const entry = bySubject.get(s.subjectId);

    // Count another session for a participant already listed, or add them with this session
    if (entry) {
      entry.sessions++;
    } else {
      bySubject.set(s.subjectId, { subjectId: s.subjectId, sessions: 1, lastAt: s.collectedAt });
    }
  }
  return [...bySubject.values()];
}


// Make a random 6 character participant ID that isn't in existing yet
export function newSubjectId(existing) {
  let id;
  do {

    // Turn 3 random bytes into 6 hex characters
    const bytes = crypto.getRandomValues(new Uint8Array(3));
    id = "";
    for (const b of bytes) {
      id += b.toString(16).padStart(2, "0");
    }
  } while (existing.has(id));
  return id;
}


// PRACTICE TRIES AND LEVELS

// Save a practice try and give back its id
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


// Give back the practice tries, newest first, for one exercise when it is given or for all of them
export async function listTrainingTries(exercise) {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE_TRAINING, "readonly");
    const all = await request(tx.objectStore(STORE_TRAINING).getAll());
    await txDone(tx);

    // Keep only this exercise's tries when one is given
    let tries = all;
    if (exercise) {
      tries = [];
      for (const r of all) {
        if (r.exercise === exercise) {
          tries.push(r);
        }
      }
    }
    return tries.reverse();
  } finally {
    db.close();
  }
}


// Where each exercise's level is kept in local storage
const TRAINING_KEY = "neurotrace:training";


// Read every exercise's saved level, or nothing if it can't be read
function trainingStates() {
  try {
    return JSON.parse(localStorage.getItem(TRAINING_KEY) || "{}");
  } catch {
    return {};
  }
}


// Give back one exercise's saved level, or null if there isn't one
export function getTrainingState(exercise) {
  const state = trainingStates()[exercise];
  if (state === undefined || state === null) {
    return null;
  }
  return state;
}


// Save one exercise's level, keeping the others
export function setTrainingState(exercise, state) {
  try {
    localStorage.setItem(TRAINING_KEY, JSON.stringify({ ...trainingStates(), [exercise]: state }));
  } catch {

    // If storage is full or blocked, the level just isn't saved
  }
}


// SETTINGS

// Where the settings are kept in local storage
const PREFS_KEY = "neurotrace:prefs";

// The settings before anything is saved
const PREFS_DEFAULTS = {
  onboarded: false,
  consented: false,
  signedIn: false,
  ageChoice: null,
  hand: "right",
  theme: "auto",
  accent: "blue",
  motion: "auto",
};


// Read the saved settings, with a default for anything not saved yet
export function getPrefs() {
  try {
    const raw = localStorage.getItem(PREFS_KEY);
    if (raw) {
      return { ...PREFS_DEFAULTS, ...JSON.parse(raw) };
    }
    return { ...PREFS_DEFAULTS };
  } catch {

    // If the settings can't be read, use the defaults
    return { ...PREFS_DEFAULTS };
  }
}


// Save some settings, keeping the rest as they are
export function setPrefs(patch) {
  try {
    localStorage.setItem(PREFS_KEY, JSON.stringify({ ...getPrefs(), ...patch }));
  } catch {

    // If storage is full or blocked, the settings just aren't saved
  }
}
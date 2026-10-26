// HOMESCAN-CHECK.MJS TESTS HOMESCAN.JS ON MADE UP HOME SCANS
// IT CHECKS HOW GEMINI'S IDEAS ARE CLEANED UP, AND HOW THE IDEAS FROM ON DEVICE LABELS ARE PICKED
// RUN IT FROM THE REPO FOLDER WITH node app/tools/homescan-check.mjs

import assert from "node:assert/strict";
import { cleanIdeas, ideasFromLabels } from "../homescan.js";


// Make a made up idea with a title, with any other fields changed by extra
function idea(title, extra = {}) {
  return { title, why: "Edges catch a foot.", where: "front left", priority: "high", ...extra };
}


// Make a made up scan of a living room with a list of ideas, with any other fields changed by extra
function scan(ideas, extra = {}) {
  return { isRoom: true, room: "living room", ideas, ...extra };
}


// Get the titles from a list of ideas, in order
function titlesOf(ideas) {
  const titles = [];
  for (const i of ideas) {
    titles.push(i.title);
  }
  return titles;
}


// A clean scan works as an object, as text, and as text inside a json code block
{
  const raw = scan([idea("Move the rug out of the walkway")]);
  const inputs = [raw, JSON.stringify(raw), "```json\n" + JSON.stringify(raw) + "\n```"];

  for (const input of inputs) {
    const r = cleanIdeas({ raw: input });
    assert.equal(r.status, "ok");
    assert.equal(r.room, "living room");
    assert.deepEqual(r.ideas, [
      { title: "Move the rug out of the walkway", why: "Edges catch a foot.", where: "front left", priority: "high", done: false },
    ]);
  }
}

// Text that isn't a scan can't be read
assert.deepEqual(cleanIdeas({ raw: "Sorry, I can't help with that." }), { status: "unreadable", room: "", ideas: [], dropped: 0 });
assert.equal(cleanIdeas({ raw: null }).status, "unreadable");

// A photo that isn't a room gives no ideas
assert.equal(cleanIdeas({ raw: scan([idea("Move the rug")], { isRoom: false }) }).status, "notRoom");
assert.equal(cleanIdeas({ raw: scan([idea("Move the rug")], { isRoom: false }) }).ideas.length, 0);

// A scan with no list of ideas, or an empty list, is empty
assert.equal(cleanIdeas({ raw: scan("rug") }).status, "empty");
assert.equal(cleanIdeas({ raw: scan([]) }).status, "empty");

// Broken ideas are dropped, and missing fields are filled in
{
  const r = cleanIdeas({ raw: scan([null, "rug", {}, { title: "  " }, { title: 7 }, { title: "Add a night light" }]) });
  assert.deepEqual(titlesOf(r.ideas), ["Add a night light"]);
  assert.equal(r.ideas[0].why, "");
  assert.equal(r.ideas[0].where, "");
  assert.equal(r.ideas[0].priority, "medium");
  assert.equal(r.dropped, 5);
}

// Extra spaces are removed, and a priority that isn't high, medium or low becomes medium
{
  const r = cleanIdeas({ raw: scan([idea("  Tape   down\nthe cord ", { priority: "HIGH" }), idea("Add a lamp", { priority: "urgent" })]) });
  assert.equal(r.ideas[0].title, "Tape down the cord");
  assert.equal(r.ideas[0].priority, "high");
  assert.equal(r.ideas[1].priority, "medium");
}

// Long text is cut at the end of a word and ends with an ellipsis
{
  const long = "Move the heavy wooden coffee table closer to the wall so there is a wide clear path from the door to the sofa";
  const r = cleanIdeas({ raw: scan([idea(long, { why: long.repeat(4) })]) });
  const { title, why } = r.ideas[0];

  // Titles are cut to 80 characters
  assert.ok(title.length <= 80 && title.endsWith("…"), title);
  assert.ok(long.startsWith(title.slice(0, -1)) && long[title.length - 1] === " ", `cut mid-word: ${title}`);

  // Reasons are cut to 200 characters
  assert.ok(why.length <= 200 && why.endsWith("…"));

  // Room names are cut to 40 characters
  assert.ok(cleanIdeas({ raw: scan([idea("x", { room: "a".repeat(100) })], { room: "b".repeat(100) }) }).room.length <= 40);
}

// Ideas that only differ in capitals, spaces or punctuation are kept once
{
  const r = cleanIdeas({ raw: scan([idea("Move the rug"), idea("move the rug."), idea("Move the  rug!")]) });
  assert.equal(r.ideas.length, 1);
  assert.equal(r.dropped, 2);
}

// Only 6 ideas are kept, or the number set by max
{
  const nine = [];
  for (let i = 0; i < 9; i++) {
    nine.push(idea(`Idea ${i}`));
  }

  assert.equal(cleanIdeas({ raw: scan(nine) }).ideas.length, 6);
  assert.equal(cleanIdeas({ raw: scan(nine), max: 3 }).ideas.length, 3);
  assert.equal(cleanIdeas({ raw: scan(nine) }).dropped, 3);
}

// Ideas that promise safety or talk about Parkinson's are dropped
{
  const banned = [
    idea("This prevents falls"),
    idea("Makes your home safe"),
    idea("Improve the lighting"),
    idea("Add rails", { why: "Guarantees you won't trip." }),
    idea("Add rails", { where: "Ensures a steady grip" }),
    idea("Clear the floor", { why: "Common for people with Parkinson's." }),
    idea("A quick safety inspection"),
    idea("Proven to reduce trips"),
    idea("Effective for balance"),
  ];

  // Ideas with words that look close to the banned ones but are fine
  const kept = [
    idea("Secure the loose cord"),
    idea("Provide a lamp by the bed"),
    idea("Stand up slowly from the low chair"),
    idea("Move the cord behind the TV screen"),
    idea("Add a grab bar by the safety rail"),
  ];

  const r = cleanIdeas({ raw: scan([...banned, ...kept]), max: 20 });
  assert.deepEqual(titlesOf(r.ideas), titlesOf(kept));
  assert.equal(r.dropped, banned.length);

  // Dropped ideas don't count toward the 6 idea limit
  assert.equal(cleanIdeas({ raw: scan([...banned, ...kept]), max: 2 }).ideas[0].title, "Secure the loose cord");
}

// Ideas made from the labels the iPad finds in the photo
{

  // Make a made up label with how sure the iPad is about it
  function label(identifier, confidence = 0.8) {
    return { identifier, confidence };
  }

  // A living room with a rug and a sofa gives the rug idea and the chair idea
  const living = ideasFromLabels({ labels: [label("living_room"), label("rug"), label("sofa")], brightness: 0.7 });
  assert.equal(living.status, "ok");
  assert.equal(living.room, "Living room");
  assert.deepEqual(titlesOf(living.ideas), ["Tape down or remove loose rugs", "Use chairs with arms and a seat that isn't too low"]);

  // Ideas from labels have no place in the room and aren't done yet
  for (const i of living.ideas) {
    assert.ok(i.where === "" && i.done === false);
  }

  // A label the iPad isn't sure about gives no idea
  const unsure = ideasFromLabels({ labels: [label("rug", 0.1), label("sofa")] });
  for (const t of titlesOf(unsure.ideas)) {
    assert.ok(!t.includes("rug"));
  }

  // A dark room gets the lighting idea, and a bright room doesn't
  const dark = ideasFromLabels({ labels: [label("kitchen")], brightness: 0.1 });
  assert.equal(dark.room, "Kitchen");
  assert.ok(titlesOf(dark.ideas).includes("Add brighter lights or night lights"));
  assert.ok(!titlesOf(ideasFromLabels({ labels: [label("kitchen")], brightness: 0.8 }).ideas).includes("Add brighter lights or night lights"));

  // A photo outside isn't a room, a bright room with nothing to change is empty, and no labels isn't a room
  assert.equal(ideasFromLabels({ labels: [label("dog"), label("grass")] }).status, "notRoom");
  assert.equal(ideasFromLabels({ labels: [label("interior_room"), label("table")], brightness: 0.9 }).status, "empty");
  assert.equal(ideasFromLabels({}).status, "notRoom");

  // A dark room with lots of things keeps 6 ideas, with the most important one first
  const labels = [];
  for (const id of ["staircase", "bathtub", "rug", "power_cable", "clutter", "armchair", "cabinet"]) {
    labels.push(label(id));
  }
  const all = ideasFromLabels({ labels, brightness: 0.1 });
  assert.equal(all.ideas.length, 6);
  assert.equal(all.dropped, 2);
  assert.equal(all.ideas[0].priority, "high");
}

console.log("HOMESCAN OK");
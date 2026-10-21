import assert from "node:assert/strict";
import { cleanIdeas } from "../homescan.js";

const idea = (title, extra = {}) => ({ title, why: "Edges catch a foot.", where: "front left", priority: "high", ...extra });
const scan = (ideas, extra = {}) => ({ isRoom: true, room: "living room", ideas, ...extra });

// Clean input, as an object or as the model's text
{
  const raw = scan([idea("Move the rug out of the walkway")]);
  for (const input of [raw, JSON.stringify(raw), "```json\n" + JSON.stringify(raw) + "\n```"]) {
    const r = cleanIdeas({ raw: input });
    assert.equal(r.status, "ok");
    assert.equal(r.room, "living room");
    assert.deepEqual(r.ideas, [
      { title: "Move the rug out of the walkway", why: "Edges catch a foot.", where: "front left", priority: "high", done: false },
    ]);
  }
}

// Unreadable, not a room, nothing usable
assert.deepEqual(cleanIdeas({ raw: "Sorry, I can't help with that." }), { status: "unreadable", room: "", ideas: [], dropped: 0 });
assert.equal(cleanIdeas({ raw: null }).status, "unreadable");
assert.equal(cleanIdeas({ raw: scan([idea("Move the rug")], { isRoom: false }) }).status, "notRoom");
assert.equal(cleanIdeas({ raw: scan([idea("Move the rug")], { isRoom: false }) }).ideas.length, 0);
assert.equal(cleanIdeas({ raw: scan("rug") }).status, "empty");
assert.equal(cleanIdeas({ raw: scan([]) }).status, "empty");

// Malformed items
{
  const r = cleanIdeas({ raw: scan([null, "rug", {}, { title: "  " }, { title: 7 }, { title: "Add a night light" }]) });
  assert.deepEqual(r.ideas.map((i) => i.title), ["Add a night light"]);
  assert.equal(r.ideas[0].why, "");
  assert.equal(r.ideas[0].where, "");
  assert.equal(r.ideas[0].priority, "medium");
  assert.equal(r.dropped, 5);
}

// Whitespace and priority
{
  const r = cleanIdeas({ raw: scan([idea("  Tape   down\nthe cord ", { priority: "HIGH" }), idea("Add a lamp", { priority: "urgent" })]) });
  assert.equal(r.ideas[0].title, "Tape down the cord");
  assert.equal(r.ideas[0].priority, "high");
  assert.equal(r.ideas[1].priority, "medium");
}

// Long text is cut at a word
{
  const long = "Move the heavy wooden coffee table closer to the wall so there is a wide clear path from the door to the sofa";
  const r = cleanIdeas({ raw: scan([idea(long, { why: long.repeat(4) })]) });
  const { title, why } = r.ideas[0];
  assert.ok(title.length <= 80 && title.endsWith("…"), title);
  assert.ok(long.startsWith(title.slice(0, -1)) && long[title.length - 1] === " ", `cut mid-word: ${title}`);
  assert.ok(why.length <= 200 && why.endsWith("…"));
  assert.ok(cleanIdeas({ raw: scan([idea("x", { room: "a".repeat(100) })], { room: "b".repeat(100) }) }).room.length <= 40);
}

// Duplicates
{
  const r = cleanIdeas({ raw: scan([idea("Move the rug"), idea("move the rug."), idea("Move the  rug!")]) });
  assert.equal(r.ideas.length, 1);
  assert.equal(r.dropped, 2);
}

// Cap
{
  const nine = Array.from({ length: 9 }, (_, i) => idea(`Idea ${i}`));
  assert.equal(cleanIdeas({ raw: scan(nine) }).ideas.length, 6);
  assert.equal(cleanIdeas({ raw: scan(nine), max: 3 }).ideas.length, 3);
  assert.equal(cleanIdeas({ raw: scan(nine) }).dropped, 3);
}

// Wording rules
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
  const kept = [
    idea("Secure the loose cord"),
    idea("Provide a lamp by the bed"),
    idea("Stand up slowly from the low chair"),
    idea("Move the cord behind the TV screen"),
    idea("Add a grab bar by the safety rail"),
  ];
  const r = cleanIdeas({ raw: scan([...banned, ...kept]), max: 20 });
  assert.deepEqual(r.ideas.map((i) => i.title), kept.map((i) => i.title));
  assert.equal(r.dropped, banned.length);

  // Banned ideas don't use up the cap
  assert.equal(cleanIdeas({ raw: scan([...banned, ...kept]), max: 2 }).ideas[0].title, "Secure the loose cord");
}

console.log("HOMESCAN OK");

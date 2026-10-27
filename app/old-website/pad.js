// PAD.JS IS THE DRAWING AREA FOR THE SPIRAL AND THE TRAINING EXERCISES
// IT DRAWS THE GUIDE AND THE INK, AND RECORDS EVERY POINT OF THE PEN OR FINGER WITH ITS TIME, PRESSURE AND TILT
// ONCE AN APPLE PENCIL TOUCHES THE SCREEN, FINGERS ARE IGNORED

// How many times the spiral guide turns
const TURNS = 4;


// Make the points of a spiral around 0, 0 that grows from radius r0 to r1 over the given turns
export function spiralPoints(r0, r1, turns, steps) {
  const pts = [];
  for (let i = 0; i <= steps; i++) {

    // How far along the spiral this point is from 0 to 1, and its angle and radius there
    const p = i / steps;
    const theta = p * turns * 2 * Math.PI;
    const r = r0 + p * (r1 - r0);
    pts.push([r * Math.cos(theta), r * Math.sin(theta)]);
  }
  return pts;
}


// Read a value from the styles, like the --accent color
export function cssVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}


// Call a pen an Apple Pencil, and keep touch and mouse as they are
function mapInputType(pointerType) {
  if (pointerType === "pen") {
    return "pencil";
  }
  return pointerType;
}


// Name the kind of device the drawing was made on
function deviceLabel() {

  // iPads say they are a Mac, but a Mac doesn't have a touch screen
  if (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) {
    return "iPad";
  }

  // Look for iPhone or iPad in the browser's description, and fall back on the platform
  const match = navigator.userAgent.match(/iPhone|iPad/);
  if (match) {
    return match[0];
  }
  return navigator.platform || "unknown";
}


// Draw the spiral guide from the middle out, leaving 20 px at the edges
function spiralGuide(ctx, w, h) {
  ctx.strokeStyle = cssVar("--guide");
  ctx.lineWidth = Math.max(2, w / 180);
  ctx.beginPath();
  const maxR = Math.min(w, h) / 2 - 20;
  for (const [x, y] of spiralPoints(0, maxR, TURNS, 1000)) {
    ctx.lineTo(w / 2 + x, h / 2 + y);
  }
  ctx.stroke();
}


// Turn a canvas into a drawing area
// onInk is called when a stroke starts or a resize clears the drawing, guide draws what to trace, and overlay draws on top
export function createPad(canvas, { onInk, guide = spiralGuide, overlay = null }) {
  const ctx = canvas.getContext("2d");

  // The highlight around the start dot, hidden until the dot shows
  const halo = document.createElement("span");
  halo.className = "pad-start";
  halo.hidden = true;
  canvas.before(halo);

  // The size of the drawing area, the recorded points, where each stroke starts in them, and the time of the first point
  let w = 0;
  let h = 0;
  let samples = [];
  let starts = [];
  let t0 = 0;

  // The input used, whether a pen has touched the screen, which pointer is drawing, and whether the start dot shows
  let inputType = null;
  let penSeen = false;
  let active = null;
  let dot = false;


  // Draw everything again from the start
  function draw() {
    if (!w) {
      return;
    }
    ctx.clearRect(0, 0, w, h);
    guide(ctx, w, h);

    // Draw the start dot in the middle
    if (dot) {
      ctx.fillStyle = cssVar("--accent");
      ctx.beginPath();
      ctx.arc(w / 2, h / 2, 7.5, 0, 2 * Math.PI);
      ctx.fill();
    }

    // Draw each stroke, which runs up to where the next one starts
    for (let i = 0; i < starts.length; i++) {
      let to = samples.length;
      if (i + 1 < starts.length) {
        to = starts[i + 1];
      }
      ink(starts[i], to);
    }
    overlay?.(ctx, w, h);
  }


  // Draw the ink for the points from up to to
  // A new stroke starts at its own first point, and more ink joins on from the point before
  function ink(from, to) {
    let first = from - 1;
    if (starts.includes(from)) {
      first = from;
    }

    ctx.strokeStyle = cssVar("--accent");
    ctx.lineWidth = Math.max(3, w / 110);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(samples[first].x, samples[first].y);
    for (let i = first; i < to; i++) {
      ctx.lineTo(samples[i].x, samples[i].y);
    }
    ctx.stroke();
  }


  // Whenever the canvas changes size, match its pixels to the screen and draw again
  new ResizeObserver(([entry]) => {
    const { width, height } = entry.contentRect;
    if (!width || !height) {
      return;
    }

    // A new size clears the drawing, since its points no longer line up with the guide
    const cleared = (width !== w || height !== h) && samples.length > 0;
    if (cleared) {
      reset();
    }
    w = width;
    h = height;

    // Give the canvas one pixel per screen pixel so the lines stay sharp
    const dpr = devicePixelRatio || 1;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();

    // Tell the screen the drawing was cleared
    if (cleared) {
      onInk({ cleared: "resize" });
    }
  }).observe(canvas);

  // Draw again when the device switches between light and dark, so the colors update
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", draw);


  // Record pointer events as points, with the time in seconds since the first point, then draw the new ink
  function addSamples(events) {
    const rect = canvas.getBoundingClientRect();
    const from = samples.length;
    for (const ev of events) {

      // The first point of the drawing sets the start time
      if (!samples.length) {
        t0 = ev.timeStamp;
      }

      // Keep the position inside the canvas, with pressure and tilt as 0 when the input doesn't have them
      samples.push({
        t: (ev.timeStamp - t0) / 1000,
        x: ev.clientX - rect.left,
        y: ev.clientY - rect.top,
        pressure: ev.pressure || 0,
        tiltX: ev.tiltX || 0,
        tiltY: ev.tiltY || 0,
      });
    }
    ink(from, samples.length);
  }


  // Start a stroke when a pen, finger or mouse goes down
  canvas.addEventListener("pointerdown", (ev) => {

    // The first time a pen touches, clear anything a finger drew before it
    if (ev.pointerType === "pen") {
      if (!penSeen && inputType === "touch") {
        reset();
      }
      penSeen = true;
    }

    // Only start with the main pointer and button, and only when nothing else is drawing
    if (!ev.isPrimary || ev.button !== 0 || active !== null) {
      return;
    }

    // Ignore fingers once a pen has been used
    if (ev.pointerType === "touch" && penSeen) {
      return;
    }

    active = ev.pointerId;

    // Hide the start dot once drawing starts
    if (dot) {
      showStartDot(false);
    }

    // The first stroke decides the input type
    if (!samples.length) {
      inputType = mapInputType(ev.pointerType);
    }

    // Start a new stroke at this point
    starts.push(samples.length);
    addSamples([ev]);
    onInk({});

    // Keep getting this pointer's moves even if it leaves the canvas
    // This throws on made up events, so it has to stay last
    canvas.setPointerCapture(ev.pointerId);
  });


  // Add points as the drawing pointer moves, using every point the browser grouped into this event
  canvas.addEventListener("pointermove", (ev) => {
    if (ev.pointerId !== active) {
      return;
    }

    let batch = [];
    if (ev.getCoalescedEvents) {
      batch = ev.getCoalescedEvents();
    }

    if (batch.length) {
      addSamples(batch);
    } else {
      addSamples([ev]);
    }
  });


  // End the stroke when the drawing pointer lifts or is cancelled
  function end(ev) {
    if (ev.pointerId === active) {
      active = null;
    }
  }

  canvas.addEventListener("pointerup", end);
  canvas.addEventListener("pointercancel", end);


  // Clear the drawing and forget the input, so the next stroke starts fresh
  function reset() {
    samples = [];
    starts = [];
    inputType = null;
    penSeen = false;
    active = null;
    draw();
  }


  // Show or hide the start dot and its highlight
  function showStartDot(on) {
    dot = on;
    halo.hidden = !on;
    draw();
  }


  // Give back what the screens use from the pad
  return {
    reset,
    showStartDot,
    redraw: draw,

    // The time of the first point, or null with nothing drawn
    startedAt() {
      if (samples.length) {
        return t0;
      }
      return null;
    },

    // Whether anything has been drawn
    hasInk() {
      return samples.length > 0;
    },

    // A copy of where each stroke starts in the points
    strokeStarts() {
      return starts.slice();
    },

    // The full recording of the drawing, with the hand it was drawn with
    trace(hand) {
      return {
        task: "spiral",
        hand,
        inputType,
        deviceLabel: deviceLabel(),
        samples: samples.slice(),
      };
    },
  };
}
const TURNS = 4;

export function spiralPoints(r0, r1, turns, steps) {
  const pts = [];
  for (let i = 0; i <= steps; i++) {
    const p = i / steps;
    const theta = p * turns * 2 * Math.PI;
    const r = r0 + p * (r1 - r0);
    pts.push([r * Math.cos(theta), r * Math.sin(theta)]);
  }
  return pts;
}

export const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

const mapInputType = (pointerType) => (pointerType === "pen" ? "pencil" : pointerType);

function deviceLabel() {
  if (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) return "iPad";
  return navigator.userAgent.match(/iPhone|iPad/)?.[0] ?? (navigator.platform || "unknown");
}

function spiralGuide(ctx, w, h) {
  ctx.strokeStyle = cssVar("--guide");
  ctx.lineWidth = Math.max(2, w / 180);
  ctx.beginPath();
  const maxR = Math.min(w, h) / 2 - 20;
  for (const [x, y] of spiralPoints(0, maxR, TURNS, 1000)) ctx.lineTo(w / 2 + x, h / 2 + y);
  ctx.stroke();
}

export function createPad(canvas, { onInk, guide = spiralGuide, overlay = null }) {
  const ctx = canvas.getContext("2d");
  const halo = document.createElement("span");
  halo.className = "pad-start";
  halo.hidden = true;
  canvas.before(halo);

  let w = 0, h = 0;
  let samples = [];
  let starts = [];
  let t0 = 0;
  let inputType = null;
  let penSeen = false;
  let active = null;
  let dot = false;

  function draw() {
    if (!w) return;
    ctx.clearRect(0, 0, w, h);
    guide(ctx, w, h);

    if (dot) {
      ctx.fillStyle = cssVar("--accent");
      ctx.beginPath();
      ctx.arc(w / 2, h / 2, 7.5, 0, 2 * Math.PI);
      ctx.fill();
    }

    starts.forEach((start, i) => ink(start, starts[i + 1] ?? samples.length));
    overlay?.(ctx, w, h);
  }

  function ink(from, to) {
    const first = starts.includes(from) ? from : from - 1;
    ctx.strokeStyle = cssVar("--accent");
    ctx.lineWidth = Math.max(3, w / 110);
    ctx.lineCap = ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(samples[first].x, samples[first].y);
    for (let i = first; i < to; i++) ctx.lineTo(samples[i].x, samples[i].y);
    ctx.stroke();
  }

  new ResizeObserver(([entry]) => {
    const { width, height } = entry.contentRect;
    if (!width || !height) return;
    const cleared = (width !== w || height !== h) && samples.length > 0;
    if (cleared) reset();
    w = width;
    h = height;
    const dpr = devicePixelRatio || 1;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();
    if (cleared) onInk({ cleared: "resize" });
  }).observe(canvas);

  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", draw);

  function addSamples(events) {
    const rect = canvas.getBoundingClientRect();
    const from = samples.length;
    for (const ev of events) {
      if (!samples.length) t0 = ev.timeStamp;
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

  canvas.addEventListener("pointerdown", (ev) => {
    if (ev.pointerType === "pen") {
      if (!penSeen && inputType === "touch") reset();
      penSeen = true;
    }
    if (!ev.isPrimary || ev.button !== 0 || active !== null) return;
    if (ev.pointerType === "touch" && penSeen) return;
    active = ev.pointerId;
    if (dot) showStartDot(false);
    if (!samples.length) inputType = mapInputType(ev.pointerType);
    starts.push(samples.length);
    addSamples([ev]);
    onInk({});
    canvas.setPointerCapture(ev.pointerId); // throws on fake events, keep last
  });

  canvas.addEventListener("pointermove", (ev) => {
    if (ev.pointerId !== active) return;
    const batch = ev.getCoalescedEvents ? ev.getCoalescedEvents() : [];
    addSamples(batch.length ? batch : [ev]);
  });

  const end = (ev) => { if (ev.pointerId === active) active = null; };
  canvas.addEventListener("pointerup", end);
  canvas.addEventListener("pointercancel", end);

  function reset() {
    samples = [];
    starts = [];
    inputType = null;
    penSeen = false;
    active = null;
    draw();
  }

  function showStartDot(on) {
    dot = on;
    halo.hidden = !on;
    draw();
  }

  return {
    reset,
    showStartDot,
    redraw: draw,
    startedAt: () => (samples.length ? t0 : null),
    hasInk: () => samples.length > 0,
    strokeStarts: () => starts.slice(),
    trace: (hand) => ({ task: "spiral", hand, inputType, deviceLabel: deviceLabel(), samples: samples.slice() }),
  };
}

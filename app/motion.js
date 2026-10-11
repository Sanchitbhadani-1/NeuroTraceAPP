const root = document.documentElement;
const motionQuery = matchMedia("(prefers-reduced-motion: reduce)");

export const reduced = () => root.dataset.motion === "reduce";

export function applyMotion(pref) {
  root.dataset.motion = pref === "reduce" || (pref !== "full" && motionQuery.matches) ? "reduce" : "full";
}

export function swap(update, { kind = "fade", x, y } = {}) {
  if (reduced() || !document.startViewTransition || document.visibilityState !== "visible") return update();
  root.dataset.vt = kind;
  if (x != null) {
    root.style.setProperty("--vt-x", `${x}px`);
    root.style.setProperty("--vt-y", `${y}px`);
  }
  const t = document.startViewTransition(update);
  t.ready.catch(() => {});
  t.finished.finally(() => delete root.dataset.vt);
}
if (document.startViewTransition) root.classList.add("vt-ok");

export function moveLens(nav) {
  const lens = nav.querySelector(".tab-lens");
  const tab = nav.querySelector('[aria-current="page"]');
  if (!lens || !tab || nav.hidden) return;
  lens.classList.toggle("placed", lens.dataset.x != null);
  const x = tab.offsetLeft + (tab.offsetWidth - lens.offsetWidth) / 2;
  lens.style.transform = `translateX(${x}px)`;
  lens.dataset.x = x;
}

let revealObserver;
export function reveal(nodes, onIn) {
  revealObserver ??= new IntersectionObserver((entries) => {
    for (const { isIntersecting, target } of entries) {
      if (!isIntersecting) continue;
      target.classList.add("in");
      revealObserver.unobserve(target);
      target._onIn?.(target);
    }
  }, { rootMargin: "0px 0px -6% 0px" });
  [...nodes].forEach((node, i) => {
    node.classList.add("reveal");
    node.style.setProperty("--i", i % 6);
    node._onIn = onIn;
    if (reduced()) {
      node.classList.add("in");
      onIn?.(node);
    } else revealObserver.observe(node);
  });
}

export function countUp(el, to, from = 50, ms = 620) {
  if (reduced()) return (el.textContent = to);
  const start = performance.now();
  const tick = (now) => {
    const t = Math.min(1, (now - start) / ms);
    el.textContent = Math.round(from + (to - from) * (1 - (1 - t) ** 3));
    if (t < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

let titleObserver;
export function watchTitle(h1) {
  const bar = document.getElementById("compact-bar");
  titleObserver?.disconnect();
  bar.classList.remove("show");
  if (!h1) return;
  bar.querySelector("span").textContent = h1.textContent;
  titleObserver = new IntersectionObserver(([entry]) => {
    bar.classList.toggle("show", !entry.isIntersecting && entry.boundingClientRect.top < 0);
  }, { rootMargin: "-44px 0px 0px 0px" });
  titleObserver.observe(h1);
}

let toastTimer;
export function toast(text) {
  const t = document.getElementById("toast");
  t.querySelector("span").textContent = text;
  t.classList.remove("show");
  void t.offsetWidth;
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), 1800);
}

const SHELL = Array.from({ length: 161 }, (_, i) => {
  const p = i / 160, th = p * 1.6 * 2 * Math.PI, r = 62 + 88 * p;
  return `${i ? "L" : "M"}${(170 + r * Math.cos(th)).toFixed(1)} ${(170 + r * Math.sin(th)).toFixed(1)}`;
}).join("");

export function mascot(mood = "idle") {
  return `<svg class="mascot ${mood}" viewBox="0 0 340 340" aria-hidden="true" focusable="false">` +
    `<g class="m-body"><path class="m-shell" pathLength="1" d="${SHELL}"/>` +
    '<circle class="m-face" cx="170" cy="170" r="54"/>' +
    '<g class="m-look"><g class="m-eyes"><ellipse cx="150" cy="166" rx="9.5" ry="14"/><ellipse cx="190" cy="166" rx="9.5" ry="14"/></g></g>' +
    "</g></svg>";
}

export function mountMascots(scope = document) {
  for (const slot of scope.querySelectorAll("[data-mascot]")) {
    if (slot.firstElementChild) continue;
    slot.innerHTML = mascot(slot.dataset.mascot);
    slot.firstElementChild.addEventListener("animationend", (e) => {
      if (e.animationName === "m-spin") e.currentTarget.classList.remove("spin");
    });
    slot.addEventListener("click", () => {
      if (reduced()) return;
      const svg = slot.firstElementChild;
      svg.classList.remove("spin");
      void svg.offsetWidth;
      svg.classList.add("spin");
    });
  }
}

export function measuring(min = 2000) {
  const box = document.getElementById("measuring");
  if (reduced()) return async () => {};
  const steps = [...box.querySelectorAll("li")];
  steps.forEach((li) => li.classList.remove("on"));
  box.hidden = false;
  requestAnimationFrame(() => box.classList.add("show"));
  const timers = steps.map((li, i) => setTimeout(() => li.classList.add("on"), 250 + i * ((min - 500) / steps.length)));
  const shown = performance.now();
  return async () => {
    await new Promise((r) => setTimeout(r, Math.max(0, min - (performance.now() - shown))));
    timers.forEach(clearTimeout);
    steps.forEach((li) => li.classList.add("on"));
    return () => {
      box.classList.remove("show");
      setTimeout(() => (box.hidden = true), 320);
    };
  };
}

// MOTION.JS HOLDS THE APP'S ANIMATIONS
// IT HANDLES REDUCED MOTION, SCREEN CHANGES, THE TAB BAR, THE TOAST, THE MASCOT AND THE MEASURING SCREEN
// EVERY ANIMATION IS SKIPPED WHEN MOTION IS SET TO REDUCED

// The page's root element, where the motion setting is kept
const root = document.documentElement;

// Whether the device asks for less motion
const motionQuery = matchMedia("(prefers-reduced-motion: reduce)");


// Check whether motion is set to reduced
export function reduced() {
  return root.dataset.motion === "reduce";
}


// Set motion to reduced or full from the saved setting, which is "reduce", "full" or automatic
// The same rule runs in index.html before the first paint
export function applyMotion(pref) {

  // Reduce motion if it was set to reduced, or if it isn't set to full and the device asks for less motion
  let motion = "full";
  if (pref === "reduce" || (pref !== "full" && motionQuery.matches)) {
    motion = "reduce";
  }
  root.dataset.motion = motion;
}


// Change the screen with a view transition, where kind picks the animation and x and y are where it starts
// With reduced motion, no view transitions, or the page in the background, the change happens straight away
export function swap(update, { kind = "fade", x, y } = {}) {
  if (reduced() || !document.startViewTransition || document.visibilityState !== "visible") {
    return update();
  }

  // Tell the styles which animation to play, and where it starts if a spot was given
  root.dataset.vt = kind;
  if (x != null) {
    root.style.setProperty("--vt-x", `${x}px`);
    root.style.setProperty("--vt-y", `${y}px`);
  }

  // Run the change inside the transition, ignore a transition that gets skipped, and clear the animation once it ends
  const t = document.startViewTransition(update);
  t.ready.catch(() => {});
  t.finished.finally(() => {
    delete root.dataset.vt;
  });
}


// Mark the page when the browser can do view transitions, so the styles can use them
if (document.startViewTransition) {
  root.classList.add("vt-ok");
}


// Move the tab bar's lens under the current tab
export function moveLens(nav) {
  const lens = nav.querySelector(".tab-lens");
  const tab = nav.querySelector('[aria-current="page"]');
  if (!lens || !tab || nav.hidden) {
    return;
  }

  // Only slide once the lens has been placed before, so the first time it jumps straight there
  lens.classList.toggle("placed", lens.dataset.x != null);

  // Center the lens under the tab and remember where it went
  const x = tab.offsetLeft + (tab.offsetWidth - lens.offsetWidth) / 2;
  lens.style.transform = `translateX(${x}px)`;
  lens.dataset.x = x;
}


// The watcher that notices items scrolling into view, made the first time reveal runs
let revealObserver;


// Fade items in as they scroll into view, and call onIn for each one when it shows
export function reveal(nodes, onIn) {

  // Make the watcher once, where an item counts as in view once it is 6% above the bottom of the screen
  if (!revealObserver) {
    revealObserver = new IntersectionObserver((entries) => {
      for (const { isIntersecting, target } of entries) {
        if (!isIntersecting) {
          continue;
        }

        // Show the item, stop watching it and call its onIn
        target.classList.add("in");
        revealObserver.unobserve(target);
        target._onIn?.(target);
      }
    }, { rootMargin: "0px 0px -6% 0px" });
  }

  // Get each item ready to fade in, with a number from 0 to 5 so neighbors fade in one after another
  const list = [...nodes];
  for (let i = 0; i < list.length; i++) {
    const node = list[i];
    node.classList.add("reveal");
    node.style.setProperty("--i", i % 6);
    node._onIn = onIn;

    // With reduced motion, show it straight away instead of waiting for it to scroll into view
    if (reduced()) {
      node.classList.add("in");
      onIn?.(node);
    } else {
      revealObserver.observe(node);
    }
  }
}


// Count el's number from the start value to the end value over ms milliseconds, slowing down near the end
export function countUp(el, to, from = 50, ms = 620) {

  // With reduced motion, show the end value straight away
  if (reduced()) {
    el.textContent = to;
    return to;
  }

  const start = performance.now();

  // Each frame, find how far through the count it is and ease it so it slows near the end
  function tick(now) {
    const t = Math.min(1, (now - start) / ms);
    el.textContent = Math.round(from + (to - from) * (1 - (1 - t) ** 3));

    // Keep going until the count is done
    if (t < 1) {
      requestAnimationFrame(tick);
    }
  }

  requestAnimationFrame(tick);
}


// The watcher for the current screen's large title
let titleObserver;


// Show the compact title bar once the screen's h1 scrolls up out of view
export function watchTitle(h1) {

  // Stop watching the last screen's title and hide the bar
  const bar = document.getElementById("compact-bar");
  titleObserver?.disconnect();
  bar.classList.remove("show");
  if (!h1) {
    return;
  }

  // Put the title's text in the bar
  bar.querySelector("span").textContent = h1.textContent;

  // Show the bar while the title is above the top of the screen, leaving out the top 44 px
  titleObserver = new IntersectionObserver(([entry]) => {
    bar.classList.toggle("show", !entry.isIntersecting && entry.boundingClientRect.top < 0);
  }, { rootMargin: "-44px 0px 0px 0px" });
  titleObserver.observe(h1);
}


// The timer that hides the toast
let toastTimer;


// Show a short message for 1.8 seconds
export function toast(text) {
  const t = document.getElementById("toast");
  t.querySelector("span").textContent = text;

  // Take the show class off and read the width, so the animation restarts if a toast is already showing
  t.classList.remove("show");
  void t.offsetWidth;
  t.classList.add("show");

  // Hide it 1.8 seconds after the latest message
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    t.classList.remove("show");
  }, 1800);
}


// Make the path of the mascot's shell, a spiral of 161 points that turns 1.6 times from radius 62 to 150
function shellPath() {
  let d = "";
  for (let i = 0; i <= 160; i++) {
    const p = i / 160;
    const th = p * 1.6 * 2 * Math.PI;
    const r = 62 + 88 * p;

    // Move to the first point, then draw a line to each next one
    let command = "L";
    if (i === 0) {
      command = "M";
    }
    d += `${command}${(170 + r * Math.cos(th)).toFixed(1)} ${(170 + r * Math.sin(th)).toFixed(1)}`;
  }
  return d;
}

const SHELL = shellPath();


// Make the mascot's svg in a mood like idle or thinking
// The body holds the shell and the face, and the eyes sit inside a group that can look around
export function mascot(mood = "idle") {
  return (
    `<svg class="mascot ${mood}" viewBox="0 0 340 340" aria-hidden="true" focusable="false">` +
    '<g class="m-body">' +
    `<path class="m-shell" pathLength="1" d="${SHELL}"/>` +
    '<circle class="m-face" cx="170" cy="170" r="54"/>' +
    '<g class="m-look">' +
    '<g class="m-eyes">' +
    '<ellipse cx="150" cy="166" rx="9.5" ry="14"/>' +
    '<ellipse cx="190" cy="166" rx="9.5" ry="14"/>' +
    "</g>" +
    "</g>" +
    "</g>" +
    "</svg>"
  );
}


// Put a mascot in every empty data-mascot slot, and make it spin when tapped
export function mountMascots(scope = document) {
  for (const slot of scope.querySelectorAll("[data-mascot]")) {

    // Skip slots that already have a mascot
    if (slot.firstElementChild) {
      continue;
    }
    slot.innerHTML = mascot(slot.dataset.mascot);

    // Take the spin class off once the spin finishes, so it can spin again
    slot.firstElementChild.addEventListener("animationend", (e) => {
      if (e.animationName === "m-spin") {
        e.currentTarget.classList.remove("spin");
      }
    });

    // Spin when tapped, unless motion is reduced
    slot.addEventListener("click", () => {
      if (reduced()) {
        return;
      }

      // Take the spin class off and read the width, so the spin restarts even in the middle of one
      const svg = slot.firstElementChild;
      svg.classList.remove("spin");
      void svg.offsetWidth;
      svg.classList.add("spin");
    });
  }
}


// Show the measuring screen for at least min milliseconds, lighting up its steps one at a time
// It gives back a function to await once the work is done, which gives back a function that hides the screen
export function measuring(min = 2000) {
  const box = document.getElementById("measuring");

  // With reduced motion, skip the screen
  if (reduced()) {
    return async () => {};
  }

  // Turn every step off and show the screen, fading it in on the next frame
  const steps = [...box.querySelectorAll("li")];
  for (const li of steps) {
    li.classList.remove("on");
  }
  box.hidden = false;
  requestAnimationFrame(() => {
    box.classList.add("show");
  });

  // Light up each step in turn, spread over the time the screen shows
  const timers = [];
  for (let i = 0; i < steps.length; i++) {
    const delay = 250 + i * ((min - 500) / steps.length);
    timers.push(setTimeout(() => {
      steps[i].classList.add("on");
    }, delay));
  }
  const shown = performance.now();

  return async () => {

    // Wait out the rest of the minimum time
    const left = Math.max(0, min - (performance.now() - shown));
    await new Promise((r) => setTimeout(r, left));

    // Stop the timers and light up every step
    for (const timer of timers) {
      clearTimeout(timer);
    }
    for (const li of steps) {
      li.classList.add("on");
    }

    // Give back a function that fades the screen out, then hides it once the fade is done
    return () => {
      box.classList.remove("show");
      setTimeout(() => {
        box.hidden = true;
      }, 320);
    };
  };
}
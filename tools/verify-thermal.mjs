#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · what the instrument costs to hold

  Reported as a phone getting hot. That is not a bug you can read out of
  the source, because nothing in it is wrong — the loop is correct, the
  quality ladder is correct, and together they ask a device for everything
  it has for as long as the page is open.

  Two facts made it:

    · The loop never stopped. After ninety-six still frames the
      accumulator blends each new one at a ninety-seventh, so the picture
      is finished — and it kept computing a whole one, sixty times a
      second, to add almost nothing to it.

    · The ladder climbs while the frame rate holds. A capable phone holds
      sixty frames at the top tier, so the ladder settles at a hundred and
      ninety raymarch steps per pixel at full resolution and stays there.
      Sustaining sixty frames and being pleasant to hold are different
      goals and it only knew the first.

  Neither is visible in a screenshot and neither is measurable by reading.
  So this counts the thing that actually costs: draw calls that reach the
  GPU. `drawArrays` is hooked before the document loads, the loop is left
  alone to run at its own rate, and the rate is measured — idle, and
  while the solid is being turned.

    node tools/verify-thermal.mjs
───────────────────────────────────────────────────────────────────────────*/
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { chromium } from "playwright";

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  c ? pass++ : fail++;
  console.log(`  ${c ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${n}`);
  if (!c && d !== undefined) console.log(`      ${d}`);
};
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);

/*  Overridable, so the same measurement can be pointed at the document a
    chain is actually serving rather than at the one just built. A local
    build passing tells you the file is right, not that the deployment
    has it.                                                            */
const DOC = process.env.DOC || "dist/ipseity.min.html";
if (!existsSync(DOC)) { console.error("run tools/build-engine.mjs first"); process.exit(1); }
const engine = readFileSync(DOC, "utf8");
const STATE = `<script>window.IPSE={id:7,collection:"0x${"11".repeat(20)}",chainId:84532,` +
  `owner:"0x${"22".repeat(20)}",seed:"0x${"33".repeat(32)}",hue:34,form:0,` +
  `rot:[0,0,0,0,0,0],w:32768,ops:3,xfers:1,strata:2,open:0}</script>`;

const srv = createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html" });
  const path = req.url.split("?")[0];
  if (path === "/") return res.end(engine.replace("</head>", STATE + "</head>"));
  /*  A stub that animates, because the thing under test is whether a pane
      nobody is looking at keeps thinking. A static stub would pass by
      having nothing to stop.                                          */
  res.end(`<h1 id=who>${path}</h1><input id=f><script>
    window.__ticks = 0;
    (function loop(){ window.__ticks++; requestAnimationFrame(loop); })();
  </script>`);
});
await new Promise((r) => srv.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${srv.address().port}`;

const EXE = ["/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
             "/opt/pw-browsers/chromium/chrome-linux/chrome"].find((p) => existsSync(p));
/*  Tiny on purpose, and this is the whole reason the measurement is
    possible at all. This machine has no GPU: a 4-D distance field at any
    real size through a software rasteriser pins the main thread so hard
    that `evaluate` never returns, which is why the deck's harness throttles
    the loop to three frames and measures nothing about pacing.

    Here the loop must be left alone — its pacing IS the thing under test —
    so the field is made small enough that a rasteriser can keep up. What
    is measured is the RATIO between idle and in-use, and a ratio does not
    care how big the picture was.                                       */
const browser = await chromium.launch({
  executablePath: EXE,
  args: ["--use-gl=swiftshader", "--no-sandbox", "--disable-dev-shm-usage"]
});
const page = await browser.newPage({ viewport: { width: 200, height: 160 } });

/*  Count what costs, before the document that will do it exists. Every
    pass of the field, the accumulator, the bloom pyramid and the
    composite ends in a drawArrays; counting them counts GPU work in the
    only unit this file has.

    rAF is deliberately NOT throttled here, unlike the deck's harness —
    the loop's own pacing is the thing under test, and a harness that
    paced it would be measuring itself.                                */
await page.addInitScript(() => {
  window.__draws = 0;
  const patch = (proto) => {
    if(!proto) return;
    const d = proto.drawArrays;
    proto.drawArrays = function(...a){ window.__draws++; return d.apply(this, a); };
  };
  patch(window.WebGL2RenderingContext && WebGL2RenderingContext.prototype);
  patch(window.WebGLRenderingContext && WebGLRenderingContext.prototype);
});

await page.goto(base + "/", { waitUntil: "domcontentloaded" });

/*  Long enough for the accumulator to converge (ninety-six frames) and
    for the ladder to have made at least one decision.                 */
await page.waitForTimeout(9000);

const rate = async (ms) => {
  const a = await page.evaluate(() => window.__draws);
  await page.waitForTimeout(ms);
  const b = await page.evaluate(() => window.__draws);
  return (b - a) / (ms / 1000);
};

head("the field draws when there is something to draw");
{
  const idle = await rate(2500);
  console.log(`      idle: ${idle.toFixed(1)} draw calls/sec`);

  /*  Counted in draw calls, not frames: one frame is the field, the
      accumulator, both halves of the bloom pyramid and the composite —
      about thirteen. So the number to read is the RATIO, which is what a
      battery feels, and an absolute threshold here would be a threshold
      on how many passes the renderer happens to have.               */
  ok("but it is not frozen either, because the shader moves on time",
     idle > 0, "nothing drew at all");

  /*  And it must wake instantly. A throttle that had to be waited out
      would read as lag on the first touch, which is worse than heat. */
  const box = await page.evaluate(() => {
    const c = document.querySelector("canvas");
    const r = c.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  });
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  const before = await page.evaluate(() => window.__draws);
  for (let i = 0; i < 24; i++) {
    await page.mouse.move(box.x + i * 6, box.y + i * 3);
    await page.waitForTimeout(40);
  }
  const after = await page.evaluate(() => window.__draws);
  await page.mouse.up();
  const moving = (after - before) / (24 * 0.04);
  console.log(`      turning the solid: ${moving.toFixed(1)} draw calls/sec`);

  const ratio = moving / Math.max(idle, 0.01);
  ok("a converged, untouched field costs a fraction of one being turned",
     ratio > 4, `only ${ratio.toFixed(1)}x — the throttle is not biting`);
  ok("and turning it brings the field straight back, with no wake-up lag",
     moving > idle * 1.8,
     `idle ${idle.toFixed(1)}/sec vs turning ${moving.toFixed(1)}/sec — no wake`);
  console.log(`      ${ratio.toFixed(1)}x the work only while it is being used`);
}

head("the ladder has a ceiling it may not climb past");
{
  /*  Read from the source rather than from the page. The engine's
      top-level bindings are not reachable from an injected evaluate, and
      exporting them onto window purely to be testable would put a byte in
      the shipped instrument that exists for this file's benefit — which
      the deck's harness already refuses to do, for the same reason.   */
  const src = readFileSync("engine/ipseity.html", "utf8");
  ok("the ladder's climb is bounded by a tier ceiling",
     /tier\s*<\s*TIER_CEIL/.test(src),
     "the ladder still climbs to TIERS.length - 1 regardless of device");
  ok("and by a scale ceiling",
     /Math\.min\(SCALE_CEIL/.test(src), "scale still climbs to 1 regardless of device");
  ok("the ceiling is lower on something held in a hand",
     /HANDHELD\s*\?\s*2/.test(src) && /pointer:coarse/.test(src), "no handheld ceiling");
  ok("lower again when the reader asked for less motion",
     /prefers-reduced-motion/.test(src) && /CALM\s*\?/.test(src), "reduced motion is ignored");
  /*  The bug this one is for: the ladder starts at tier 2, which is ABOVE
      the reduced-motion ceiling, and would only ever have come down by
      failing to keep up — the ceiling would have been silently useless
      for the readers who most needed it.                             */
  ok("and the tier it starts at is clamped to its own ceiling",
     /let tier = Math\.min\(2, TIER_CEIL\)/.test(src),
     "tier starts at a fixed 2 and can begin above the ceiling");
}

head("a page nobody is looking at stops");
{
  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { get: () => true, configurable: true });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  const hidden = await rate(1500);
  console.log(`      hidden: ${hidden.toFixed(1)} draw calls/sec`);
  ok("hiding the document stops the field entirely", hidden === 0,
     `${hidden.toFixed(1)}/sec while hidden`);

  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { get: () => false, configurable: true });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await page.waitForTimeout(400);
  const back = await rate(1200);
  ok("and coming back starts it again", back > 0, "it never woke up");
}

head("a pane nobody is looking at stops too");
{
  /*  visibility:hidden stops a document painting and not thinking. Four
      panes were four loops running at once, on top of the field — which
      is the half of the heat the loop's own throttle could never reach. */
  /*  The field is stopped first, and this is the only way the measurement
      is possible on a machine with no GPU: a 4-D distance field at a size
      big enough to hold a palette pins the main thread so hard that
      nothing responds — which is why the deck's harness throttles the loop
      to three frames and why an earlier version of this block timed out
      waiting for an input that was there all along.

      Hiding the document is not a trick borrowed for the test; it is the
      pause this session added, used for what it is for. And it stops the
      ENGINE's loop only: the browser's own background throttling keys off
      real tab visibility, not off a property we defined, so the panes go
      on running exactly as they would on a phone.                     */
  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { get: () => true, configurable: true });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await page.setViewportSize({ width: 900, height: 700 });
  await page.waitForTimeout(500);
  for (const route of ["swap", "gallery"]) {
    await page.evaluate(() => window.__palette());
    await page.fill("#palq", "open " + route);
    await page.waitForTimeout(200);
    await page.evaluate(() => {
      const r = document.querySelector("#pallist .pi");
      if (r) r.click();
    });
    await page.waitForTimeout(700);
  }

  const n = await page.evaluate(() => document.querySelectorAll("#dkwrap iframe").length);
  ok("two panes are open", n === 2, "got " + n);

  if (n === 2) {
    const ticks = async () => page.evaluate(() =>
      Array.from(document.querySelectorAll("#dkwrap iframe"))
        .map((f) => { try { return f.contentWindow.__ticks | 0; } catch(e){ return -1; } }));
    const a = await ticks();
    await page.waitForTimeout(1200);
    const b = await ticks();
    const moved = a.map((v, i) => b[i] - v);
    console.log(`      frames advanced while one pane was focused: ${JSON.stringify(moved)}`);

    const focused = await page.evaluate(() =>
      Array.from(document.querySelectorAll("#dkwrap iframe")).findIndex((f) => f.classList.contains("on")));
    ok("the focused pane keeps animating", moved[focused] > 0,
       "the pane being looked at was parked");
    const others = moved.filter((_, i) => i !== focused);
    ok("and every pane behind it is parked", others.every((m) => m <= 1),
       "unfocused panes advanced " + JSON.stringify(others) + " frames");

    /*  Parked, not killed. A stub whose loop was stubbed to a no-op would
        look identical until you came back to a frozen page.           */
    /*  Clicked on the rail, not called: dkFocus is not on window either,
        and a test that calls a function it cannot reach silently does
        nothing and then reports the code broken.                      */
    const k = await page.evaluate(() =>
      Array.from(document.querySelectorAll("#dkwrap iframe")).findIndex((f) => !f.classList.contains("on")));
    await page.click(`#dkrail .dm[data-k="${k}"]`);
    await page.waitForTimeout(1200);
    const c = await ticks();
    const woke = c.map((v, i) => v - b[i]);
    console.log(`      after switching focus: ${JSON.stringify(woke)}`);
    ok("and starts again from where it stopped when you come back",
       woke[k] > 0, "the pane brought back forward never resumed: " + JSON.stringify(woke));
    /*  Not zero, and pretending otherwise would be a test tuned to pass.
        Parking happens on the click, so the frame already in flight and
        the one queued behind it still run — a handful out of the seventy
        a second the pane was managing. What must be true is that it
        STOPS, and a tenth is stopped.                                 */
    ok("while the one you left parks in its turn",
       woke[focused] < woke[k] / 5,
       `left-behind pane ran ${woke[focused]} frames against ${woke[k]} — not parked`);
    console.log(`      the pane you left ran ${woke[focused]} more frames, then stopped`);
  }
}

await browser.close();
srv.close();
console.log(`\n  ${fail ? "\x1b[31m" : "\x1b[32m"}${pass} passed, ${fail} failed\x1b[0m\n`);
process.exit(fail ? 1 : 0);
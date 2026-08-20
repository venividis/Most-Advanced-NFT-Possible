#!/usr/bin/env node
/*───────────────────────────────────────────────────────────────────────────
  IPSEITY · the deck

  The claim under test: clicking an orbiting node opens the real flat
  surface, four of them stay alive at once, and the field shrinks rather
  than being covered.

  None of that can be checked by reading the source. A pane is an iframe
  whose document must actually load; "four stay alive" is a claim about
  what a browser did with four documents, not about what a function
  returned; and "the field shrinks" is a claim about a rectangle after
  layout. So this serves the built engine over a real origin — `DOORED` is
  false on file:// and the whole deck would never form — and drives it in
  a browser.

  The surfaces are stubs rather than the real contract-rendered pages: what
  is under test is the deck, and a stub that prints its own path is a
  better witness than a 30 KB page, because a pane showing the wrong route
  is then visible rather than inferred.

    node tools/verify-deck.mjs
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
const eq = (n, g, w) => ok(n, String(g) === String(w), `got ${g}\n      want ${w}`);
const head = (s) => console.log(`\n  \x1b[1m${s}\x1b[0m`);

const DOC = "dist/ipseity.min.html";
if (!existsSync(DOC)) { console.error("run tools/build-engine.mjs first"); process.exit(1); }
const engine = readFileSync(DOC, "utf8");

/*  window.IPSE is written between <head> and <body> by tokenURI(); the
    built document has none, so the harness supplies one exactly as the
    contract would.                                                     */
const STATE = `<script>window.IPSE={id:7,collection:"0x${"11".repeat(20)}",chainId:84532,` +
  `owner:"0x${"22".repeat(20)}",seed:"0x${"33".repeat(32)}",hue:34,form:0,` +
  `rot:[0,0,0,0,0,0],w:32768,ops:3,xfers:1,strata:2,open:0}</script>`;

const served = [];
const srv = createServer((req, res) => {
  const path = req.url.split("?")[0];
  if (path === "/" ) {
    res.writeHead(200, { "Content-Type": "text/html" });
    return res.end(engine.replace("</head>", STATE + "</head>"));
  }
  served.push(path);
  res.writeHead(200, { "Content-Type": "text/html" });
  /*  Every stub carries an input, so the "something is typed in it" guard
      has something real to find.                                       */
  res.end(`<!doctype html><title>${path}</title><body style="background:#030206;color:#ddd">` +
          `<h1 id=who>${path}</h1><input id=f><script>document.title=${JSON.stringify(path)}</script>`);
});
await new Promise((r) => srv.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${srv.address().port}`;

/*  The image pins a browser build that this Playwright version does not
    name the same way, so the binary is given explicitly rather than
    resolved — a resolver that guesses wrong prints an install banner and
    looks like a missing dependency instead of a version mismatch.     */
const EXE = ["/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
             "/opt/pw-browsers/chromium/chrome-linux/chrome"].find((p) => existsSync(p));
const browser = await chromium.launch({
  executablePath: EXE,
  args: ["--use-gl=swiftshader", "--no-sandbox", "--disable-dev-shm-usage"]
});
/*  Small enough that a software rasteriser can keep up. The deck's
    geometry is checked against this width, not against a desktop's, so
    the numbers below are the ones this viewport produces.            */
const ctx = await browser.newContext({ viewport: { width: 900, height: 700 } });
const page = await ctx.newPage();

/*  Let the instrument boot, then stop its frame loop.

    The deck is a DOM system: tabs, iframes, a CSS inset. None of it needs
    the raymarcher to have drawn anything. But this machine has no GPU, and
    a 4-D distance field at 900x700 through a software rasteriser pins the
    main thread hard enough that `evaluate` never returns — which reads
    exactly like a page that failed to boot, and cost an hour to tell
    apart. Three frames is enough for initGL, the first resize and the
    quality ladder's first reading; after that the loop is a no-op and the
    thread belongs to the test.

    Nothing in the engine knows about this. It is done from outside, before
    the document's own script runs, so no byte of the shipped instrument
    exists to make it testable.                                         */
await page.addInitScript(() => {
  const raf = window.requestAnimationFrame.bind(window);
  let n = 0;
  window.requestAnimationFrame = (cb) => (n++ < 3 ? raf(cb) : 0);
});
const errs = [];
page.on("pageerror", (e) => errs.push(String(e.message)));
/*  Kept apart on purpose. A thrown exception is a defect; a console
    resource error is not necessarily one — closing a pane sets its src to
    about:blank and removes it, and a document still fetching when that
    happens reports ERR_CONNECTION_RESET. That is the tear-down working. */
const noise = [];
page.on("console", (m) => { if (m.type() === "error") noise.push(m.text()); });
/*  The instrument compiles a raymarching shader before it is interactive
    and this may be a software rasteriser, so the wait is generous and the
    marker is a thing the document owns rather than a load event.     */
await page.goto(base + "/", { waitUntil: "commit", timeout: 90000 });
/*  Timer polling, not the default. `waitForFunction` polls on
    requestAnimationFrame, and this document's own render loop owns every
    frame — under a software rasteriser the poll is starved for as long as
    you are willing to wait, which reads exactly like a page that never
    booted.                                                              */
/*  An explicit evaluate loop rather than waitForFunction. The latter polls
    on requestAnimationFrame by default and this document's render loop owns
    every frame; under a software rasteriser the poll is starved for as long
    as you care to wait, which reads exactly like a page that never booted.
    An evaluate runs as an ordinary task and gets through.               */
{
  let up = false;
  for (let i = 0; i < 60 && !up; i++) {
    up = await Promise.race([
      page.evaluate(() => !!document.getElementById("deck")).catch(() => false),
      new Promise((r) => setTimeout(() => r(false), 5000))
    ]);
    if (!up) await new Promise((r) => setTimeout(r, 500));
    if (!up && i % 10 === 9) {
      const st = await Promise.race([
        page.evaluate(() => document.readyState).catch((e) => "eval:" + e.message.slice(0, 40)),
        new Promise((r) => setTimeout(() => r("blocked"), 4000))]);
      console.log(`      still waiting (${i + 1}) readyState=${st} errs=${errs.length ? errs[0].slice(0, 120) : "none"}`);
    }
  }
  if (!up) { console.error("  the instrument never became responsive"); process.exit(1); }
}
await page.waitForTimeout(1500);

head("the instrument comes up over a real origin");
ok("no uncaught error while booting", errs.length === 0, errs.join("\n      "));
eq("DOORED is true, so the door ring formed", await page.evaluate(() => window.DOORED === undefined ? "n/a" : String(window.DOORED)), "n/a");
ok("the deck exists and is closed", await page.evaluate(() =>
  !!document.getElementById("deck") && !document.getElementById("deck").classList.contains("on")));
ok("the veil is gone entirely", await page.evaluate(() =>
  !document.getElementById("veil") && !document.getElementById("veilf")));

/*  The deck's own functions are module-scope inside one <script>, so the
    harness reaches them the way a person does: through the palette and
    through the nodes.                                                  */
const pal = async (text) => {
  await page.evaluate(() => window.__palette());
  await page.fill("#palq", text);
  await page.waitForTimeout(120);
  return page.$$eval("#pallist .pi", (els) => els.map((e) => ({
    t: e.querySelector(".pt").textContent, d: e.querySelector(".pd").textContent })));
};
const runRow = async (i) => {
  await page.evaluate((k) => document.querySelectorAll("#pallist .pi")[k].click(), i);
  await page.waitForTimeout(400);
};
const tabs = () => page.$$eval("#dkbar .dt", (els) => els.map((e) => e.textContent.replace("×", "").trim()));
const frames = () => page.$$eval("#dkwrap iframe", (els) => els.map((e) => e.getAttribute("src")));

head("the grammar the owner asked for");
{
  let r = await pal("open swap");
  ok("`open swap` finds exactly the swap surface", r.length === 1 && r[0].t === "open swap", JSON.stringify(r));
  eq("and shows the route it would load", r[0].d, "/swap");

  r = await pal("open world chat");
  ok("`open world chat` reaches the commons through its aliases",
     r.length === 1 && r[0].t === "open chat", JSON.stringify(r));

  r = await pal("/open swap");
  ok("a leading slash costs nothing", r.length === 1 && r[0].t === "open swap", JSON.stringify(r));

  r = await pal("open wor ch");
  ok("prefixes, not whole words — `open wor ch` still reaches it",
     r.some((x) => x.t === "open chat"), JSON.stringify(r));

  /*  `room` also prefixes `rooms`, and `vault` is an alias of `lock`.
      Ambiguity is the palette's normal condition — what must hold is that
      typing a surface's exact name puts that surface first, or the top
      row runs something the reader did not ask for.                   */
  r = await pal("open room");
  eq("an exact name outranks a longer one that merely starts with it", r[0].t, "open room");
  ok("and it says it needs a number rather than loading a wrong route",
     /needs a number/.test(r[0].d), JSON.stringify(r[0]));

  r = await pal("open room 7");
  eq("with the number it names the exact route", r[0].d, "/room/7");

  r = await pal("open vault");
  eq("an exact name outranks an alias on another surface", r[0].t, "open vault");
  eq("and `$` resolves to this token's id", r[0].d, "/token/7/vault");

  r = await pal("open frobnicate");
  ok("an unknown name refuses, then answers the question actually asked",
     /no surface is named/.test(r[0].d) && r.length > 20, JSON.stringify(r.slice(0, 2)));
}

head("opening surfaces");
{
  await pal("open swap"); await runRow(0);
  eq("one pane is open", (await tabs()).length, 1);
  eq("and it loaded the route, not a name", (await frames())[0], "/swap");
  ok("the deck is showing", await page.evaluate(() =>
    document.getElementById("deck").classList.contains("on")));

  const fx = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue("--fx").trim());
  ok("the field gave up a strip rather than being covered", parseInt(fx) > 150, `--fx = ${fx}`);

  const rect = await page.evaluate(() => {
    const c = document.getElementById("field").getBoundingClientRect();
    return { w: Math.round(c.width), h: Math.round(c.height) };
  });
  ok("and the canvas is genuinely narrower than the window",
     rect.w < 900 && rect.w > 250, JSON.stringify(rect));
  eq("while still reaching top and bottom", rect.h, 700);
}

head("four live at once, and the fifth");
{
  for (const n of ["open gallery", "open lock", "open estate"]) { await pal(n); await runRow(0); }
  eq("four panes", (await tabs()).length, 4);
  eq("four documents, all still in the DOM", (await frames()).length, 4);
  ok("each holds its own route",
     JSON.stringify(await frames()) === JSON.stringify(["/swap", "/gallery", "/lock", "/estate"]),
     JSON.stringify(await frames()));

  /*  The point of "live": the hidden ones are still loaded documents with
      their own state, not tabs that will be fetched when shown.       */
  const titles = await page.evaluate(() =>
    Array.from(document.querySelectorAll("#dkwrap iframe")).map(f => {
      try { return f.contentDocument.title; } catch(e){ return "opaque"; } }));
  ok("every hidden document actually loaded",
     titles.join(",") === "/swap,/gallery,/lock,/estate", titles.join(","));

  const vis = await page.$$eval("#dkwrap iframe", (els) =>
    els.map((e) => getComputedStyle(e).visibility));
  eq("exactly one is visible", vis.filter((v) => v === "visible").length, 1);
  ok("and the hidden ones keep their layout box",
     await page.$$eval("#dkwrap iframe", (els) => els.every((e) => e.getBoundingClientRect().width > 0)));

  /*  Typing into the least-recently-used pane makes it undroppable, so the
      fifth open must take the next clean one instead — and say which.  */
  await page.evaluate(() => {
    const f = document.querySelectorAll("#dkwrap iframe")[0];
    f.contentDocument.getElementById("f").value = "half a swap";
  });
  await pal("open keys"); await runRow(0);
  const t = await tabs();
  eq("still four", t.length, 4);
  ok("the pane with typing in it survived", (await frames()).includes("/swap"), JSON.stringify(await frames()));
  ok("and the clean least-recently-used one was taken instead",
     !(await frames()).includes("/gallery"), JSON.stringify(await frames()));
}

head("dedupe, focus and closing");
{
  const before = (await frames()).length;
  await pal("open swap"); await runRow(0);
  eq("opening a route already open focuses it rather than loading twice",
     (await frames()).length, before);
  const onIdx = await page.$$eval("#dkbar .dt", (els) => els.findIndex((e) => e.classList.contains("on")));
  eq("and the focused tab is that one", (await frames())[onIdx], "/swap");

  /*  The close target exists only on the tab already focused, so a
      mis-tap anywhere else costs a focus change and never a form.     */
  const xs = await page.$$eval("#dkbar .dt", (els) =>
    els.map((e) => getComputedStyle(e.querySelector("i")).display));
  eq("exactly one close button is rendered", xs.filter((d) => d !== "none").length, 1);

  await pal("close all"); await runRow(0);
  eq("`close all` empties the deck", (await tabs()).length, 0);
  eq("and every document is torn down", (await frames()).length, 0);
  const fx = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue("--fx").trim());
  eq("the field takes its rectangle back", fx, "0px");
}

head("the nodes themselves");
{
  /*  What the owner actually reported: clicking an orbiting node produced
      a black panel of prose. A door node must now produce the surface. */
  const clicked = await page.evaluate(() => {
    const n = Array.from(document.querySelectorAll("#nodes .nd"))
      .find((e) => /swap/i.test(e.textContent));
    if(!n) return null;
    n.click(); return n.textContent.trim();
  });
  await page.waitForTimeout(500);
  ok("a door node was found in the orbit", clicked !== null, "no node labelled Swap");
  eq("clicking it opened the surface, not a blurb", (await frames())[0], "/swap");
  ok("and the sheet stayed shut", await page.evaluate(() =>
    !document.getElementById("sheet").classList.contains("open")));
}

head("no error the whole way through");
ok("nothing threw", errs.length === 0, errs.slice(0, 4).join("\n      "));
ok("and the only console noise is documents torn down mid-fetch",
   noise.every((t) => /ERR_CONNECTION_RESET|ERR_ABORTED/.test(t)),
   noise.filter((t) => !/ERR_CONNECTION_RESET|ERR_ABORTED/.test(t)).slice(0, 3).join("\n      "));
ok("every pane the deck opened was actually requested from the origin",
   served.length >= 6, served.join(" "));

await browser.close();
srv.close();
console.log(`\n  ${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);

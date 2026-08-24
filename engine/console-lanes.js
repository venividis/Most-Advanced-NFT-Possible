/*═══════════════════════════════════════════════════════════════════════════
  IPSEITY · the lanes

  The contract renders each lane's STATE — what is true about this token
  right now, read on chain in the same call that produced the document.
  This file does not repaint that. It adds the half a contract cannot have:
  the controls that send a transaction.

  So the layering is deliberate and it is the whole degradation story:

      no script at all → the crest, the still, the identity, seven rows
                          with their clocks, and each lane's state. A
                          correct page about the right token.
      script, no wallet → the same, plus the walk and the command line.
      script and wallet → the above, plus the controls.

  Nothing is ever a spinner over a number nobody read.

  ── selectors ──

  Every four-byte selector arrives in `CON.sel`, derived by the contract,
  because Solidity has keccak and a browser does not. Shipping two
  kilobytes of keccak so the client can recompute what the contract already
  knows is a client that can be wrong about something it never had to
  decide. The ABI encoding of the ARGUMENTS is done here, by hand, in the
  four shapes this file needs — which is a small thing to own and a large
  thing to depend on somebody else for.

  ── the slab ──

  There is no path from a text field to a broadcast transaction. Every
  send raises a slab that names, in words, what is about to happen and to
  what, and the transaction is built only after a person presses the
  button on it. The console types; the human presses.
═══════════════════════════════════════════════════════════════════════════*/
(function () {
  "use strict";
  var C = window.CON;
  if (!C) return;
  var $ = function (s) { return document.querySelector(s); };
  var say = C.say || function () {};

  /*───────────────────────── the smallest ABI coder ─────────────────────*/

  var pad = function (h) { return h.replace(/^0x/, "").padStart(64, "0"); };
  var enc = {
    addr: function (a) { return pad(String(a).toLowerCase()); },
    uint: function (n) { return pad(BigInt(n).toString(16)); }
  };
  var wei = function (s) {
    /*  Decimal ether to wei without a float anywhere near it. A balance
        that went through a double is a balance that is wrong in the last
        places, and those are somebody's.                               */
    var m = /^(\d*)(?:\.(\d*))?$/.exec(String(s).trim());
    if (!m) return null;
    var whole = m[1] || "0", frac = (m[2] || "").slice(0, 18).padEnd(18, "0");
    return BigInt(whole) * 10n ** 18n + BigInt(frac || "0");
  };
  var eth = function (v) {
    v = BigInt(v);
    var w = v / 10n ** 18n, f = (v % 10n ** 18n).toString().padStart(18, "0").slice(0, 5);
    f = f.replace(/0+$/, "");
    /*  Dust is still custody. A balance that rounds to zero and prints as
        zero is a lie a holder cannot argue with.                       */
    if (v > 0n && w === 0n && f === "") return "<0.00001";
    return w.toString() + (f ? "." + f : "");
  };

  /*  The same two moves for a token that is not ether. `dec` comes from the
      coin's own `decimals()` — and when that read does not answer, these
      are never called: an amount scaled by a guessed exponent is wrong by
      factors of ten, which is the one mistake no slab can catch.        */
  var units = function (s, dec) {
    var m = /^(\d*)(?:\.(\d*))?$/.exec(String(s).trim());
    if (!m || (!m[1] && !m[2])) return null;
    var frac = (m[2] || "").slice(0, dec).padEnd(dec, "0");
    return BigInt(m[1] || "0") * 10n ** BigInt(dec) + BigInt(frac || "0");
  };
  var amt = function (v, dec) {
    v = BigInt(v);
    var b = 10n ** BigInt(dec);
    var w = v / b;
    var f = dec > 0 ? (v % b).toString().padStart(dec, "0").slice(0, 6).replace(/0+$/, "") : "";
    if (v > 0n && w === 0n && f === "") return "<0.000001";
    return w.toString() + (f ? "." + f : "");
  };

  /*  Text to calldata bytes and back, without TextEncoder — the console is
      deliberately old-fashioned, and the escape/encodeURIComponent pair is
      the UTF-8 codec every browser has carried since before it had one. */
  var utf8hex = function (s) {
    var raw = unescape(encodeURIComponent(s)), out = "";
    for (var i = 0; i < raw.length; i++) out += ("0" + raw.charCodeAt(i).toString(16)).slice(-2);
    return out;
  };
  var deHex = function (hex) {
    if (!hex || hex.length % 2) return null;
    try {
      return decodeURIComponent(hex.replace(/../g, function (b) { return "%" + b; }));
    } catch (e) {
      /*  Not UTF-8. That is a fact about the bytes, not an error to hide. */
      return null;
    }
  };

  function provider() { return window.ethereum || null; }

  function call(to, data) {
    var p = provider();
    if (!p) return Promise.reject(new Error("no wallet"));
    return p.request({ method: "eth_call", params: [{ to: to, data: data }, "latest"] });
  }

  /*───────────────────────── the confirm slab ─────────────────────────*/

  /*  §E.9, finally shipped. The slab always states where the transaction
      goes, what it carries, and which function it calls — a person should
      never have to trust the lane's title over the bytes. And after the
      press, the sentence keeps moving: sent, then mined or reverted, read
      back off the wallet's own node one hash at a time. "Sent · 0x…" used
      to be the entire post-signature experience of this console, which
      left a holder refreshing a block explorer to learn whether their own
      turn had landed.                                                    */

  function watch(h) {
    var p = provider();
    if (!p) return;
    var tries = 0;
    var poll = function () {
      tries += 1;
      p.request({ method: "eth_getTransactionReceipt", params: [h] })
        .then(function (r) {
          if (r && r.blockNumber) {
            var n = parseInt(r.blockNumber, 16);
            if (r.status === "0x0") {
              say("It reverted in block " + n + ". Nothing changed.", "err");
            } else {
              say("Mined in block " + n + ". What this page shows may lag it by one.", "ok");
            }
            return;
          }
          if (tries === 22) say("Still not mined. The chain is slow or the fee was low.");
          if (tries < 45) setTimeout(poll, 4000);
          else say("Not mined after three minutes. The wallet may still land it — check there.");
        })
        /*  A wallet that cannot answer for receipts is not a failure of
            the transaction — stop asking rather than guessing.          */
        .catch(function () {});
    };
    setTimeout(poll, 4000);
  }

  function propose(title, lines, tx, fn) {
    var box = $("#cbox"), slab = $("#cslab");
    if (!box || !slab) return;

    /*  The wrong chain refuses HERE, before a slab exists — §E.5. The
        crest already offers the move; a slab built for the wrong chain is
        a trap with a countdown. Unknown is not wrong: a provider that
        cannot say its chain leaves the wallet's own guard in charge.    */
    if (C.chainOk === false) {
      return say("Your wallet is on another chain. This token lives on chain " +
                 C.chain + " — the crest offers the move.", "err");
    }

    slab.innerHTML =
      '<div class="k" style="margin-bottom:10px"></div>' +
      '<div class="body"></div>' +
      '<button class="b" type="button" data-go>1</button>' +
      '<button class="b g" type="button" data-no>Not now</button>';
    slab.querySelector(".k").textContent = title;
    var body = slab.querySelector(".body");
    var put = function (k, v) {
      var d = document.createElement("div");
      d.className = "kv";
      var a = document.createElement("span"); a.className = "k"; a.textContent = k;
      var b = document.createElement("span"); b.className = "v"; b.textContent = v;
      d.appendChild(a); d.appendChild(b); body.appendChild(d);
    };
    lines.forEach(function (l) { put(l[0], l[1]); });
    put("To", short(tx.to));
    if (tx.value) put("Value", eth(BigInt(tx.value)) + " ETH");
    if (tx.data && tx.data.length >= 10) put("Function", (fn ? fn + " · " : "") + tx.data.slice(0, 10));
    slab.querySelector("[data-go]").textContent = "Sign it";
    box.classList.add("on");

    var shut = function () { box.classList.remove("on"); };
    slab.querySelector("[data-no]").onclick = shut;
    slab.querySelector("[data-go]").onclick = function () {
      shut();
      var p = provider();
      if (!p || !C.account) return say("Connect a wallet first.", "err");
      say("Waiting for the wallet…");
      p.request({ method: "eth_sendTransaction", params: [Object.assign({ from: C.account }, tx)] })
        .then(function (h) {
          say("Sent · " + h.slice(0, 10) + "… — watching for the block.", "ok");
          watch(h);
        })
        .catch(function (e) { say(e && e.message ? e.message : "The wallet refused.", "err"); });
    };
  }
  C.propose = propose;

  /*───────────────────────── lane furniture ─────────────────────────*/

  var el = function (tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  function kv(parent, k, v) {
    var d = el("div", "kv");
    d.appendChild(el("span", "k", k));
    d.appendChild(el("span", "v", v));
    parent.appendChild(d);
    return d;
  }
  function button(parent, label, grey, fn) {
    var b = el("button", "b" + (grey ? " g" : ""), label);
    b.type = "button";
    b.addEventListener("click", fn);
    parent.appendChild(b);
    return b;
  }
  function field(parent, label, placeholder) {
    parent.appendChild(el("div", "k", label));
    var i = el("input");
    i.type = "text";
    i.placeholder = placeholder || "";
    i.autocomplete = "off";
    parent.appendChild(i);
    return i;
  }
  /*  Always with the spaces around the ellipsis, and always used: a full
      address in a 300px column runs off the edge, and an address that runs
      off the edge is one a holder cannot check.                        */
  var short = function (a) {
    return !a || /^0x0{40}$/i.test(a) ? "nobody" : a.slice(0, 6) + " \u2026 " + a.slice(-4);
  };

  function note(parent, text, cls) {
    var p = el("p", "blurb" + (cls ? " " + cls : ""), text);
    parent.appendChild(p);
    return p;
  }

  /*  A lane says what it cannot do, in the place a holder would look for
      it. A surface that is silent about its own edges teaches somebody
      that the thing they want is impossible, when it is only unbuilt.  */
  function unbuilt(parent, what) {
    var p = el("p", "s", what);
    p.style.color = "var(--warn)";
    p.style.marginTop = "16px";
    parent.appendChild(p);
  }

  var mine = function () {
    return !!(C.account && C.owner && C.account.toLowerCase() === C.owner.toLowerCase());
  };
  function onlyHolder(parent) {
    if (mine()) return true;
    note(parent, C.account
      ? "You are reading somebody else's token. Nothing here will sign."
      : "Connect a wallet to act on this token.");
    return false;
  }

  /*───────────────────────── the seven ─────────────────────────*/

  var LANE = {};

  /* 1 · TURN IT — the word is one uint256, and committing it is one call */
  LANE[1] = function (h) {
    var word = BigInt(C.word);
    var planes = ["XY", "XZ", "YZ", "XW", "YW", "ZW"];
    var vals = planes.map(function (_, i) { return Number((word >> BigInt(i * 16)) & 0xffffn); });
    var wCut = Number((word >> 96n) & 0xffffn);
    var form = Number((word >> 112n) & 0xffn);
    var hue = Number((word >> 120n) & 0xffn);

    h.appendChild(el("div", "k", "THE WORD"));
    note(h, "Six planes and a cut. The three that contain w are the ones a " +
            "three-dimensional eye has no name for, and they are the ones worth turning.");

    var inputs = [];
    planes.forEach(function (nm, i) {
      var row = el("div", "kv");
      row.appendChild(el("span", "k", nm));
      var r = el("input");
      r.type = "range"; r.min = 0; r.max = 65535; r.value = vals[i];
      r.style.flex = "1";
      /*  The three containing w are drawn dashed, the way the instrument
          marks them. A plane you cannot picture should not look like one
          you can.                                                     */
      if (i >= 3) r.style.borderBottom = "1px dashed var(--a-dim)";
      row.appendChild(r);
      h.appendChild(row);
      inputs.push(r);
    });

    var cutRow = el("div", "kv");
    cutRow.appendChild(el("span", "k", "CUT"));
    var cut = el("input");
    cut.type = "range"; cut.min = 0; cut.max = 65535; cut.value = wCut; cut.style.flex = "1";
    cutRow.appendChild(cut); h.appendChild(cutRow);

    var hueRow = el("div", "kv");
    hueRow.appendChild(el("span", "k", "HUE"));
    var hu = el("input");
    hu.type = "range"; hu.min = 0; hu.max = 255; hu.value = hue; hu.style.flex = "1";
    hueRow.appendChild(hu); h.appendChild(hueRow);
    /*  The console re-tints live, the way the instrument does, because a
        colour you cannot see before you pay for it is a colour you are
        guessing at.                                                    */
    hu.addEventListener("input", function () {
      document.documentElement.style.setProperty("--h",
        String(Math.floor(Number(hu.value) * 360 / 256)));
    });

    if (!onlyHolder(h)) return;
    button(h, "Review the turn", false, function () {
      var next = 0n;
      inputs.forEach(function (r, i) { next |= BigInt(r.value) << BigInt(i * 16); });
      next |= BigInt(cut.value) << 96n;
      next |= BigInt(form) << 112n;
      next |= BigInt(hu.value) << 120n;
      if (next === word) return say("Nothing has moved.", "err");

      /*  The slab used to print the word before and after as two raw
          decimal uint256s, which no person can audit. It says what moved
          now, plane by plane, in degrees — the word itself rides in the
          calldata the slab already names.                               */
      var deg = function (v) { return String(Math.round(v * 360 / 65536)) + "°"; };
      var linesOut = [["Token", "#" + C.id]];
      planes.forEach(function (nm, i) {
        var now = vals[i], then = Number(inputs[i].value);
        if (now !== then) linesOut.push([nm, deg(now) + " → " + deg(then)]);
      });
      if (Number(cut.value) !== wCut)
        linesOut.push(["Cut", deg(wCut) + " → " + deg(Number(cut.value))]);
      if (Number(hu.value) !== hue)
        linesOut.push(["Hue", String(Math.floor(Number(hu.value) * 360 / 256)) + "°"]);
      propose("TURN IT", linesOut,
        { to: C.hub, data: C.sel.commit + enc.uint(C.id) + enc.uint(next) },
        "commit(uint256,uint256)");
    });
  };

  /* 2 · PUT SOMETHING IN IT — the two hands */
  LANE[2] = function (h) {
    /*  The contract already printed both addresses and the permanence
        sentence. Printing them again is not belt and braces, it is two
        answers to one question with no way to tell which is current. What
        is added here is what a contract could not know or could not do:
        the balances, and the acts.                                     */
    var p = provider();
    var rows = {};
    ["reach", "grip"].forEach(function (k) {
      rows[k] = kv(h, k === "reach" ? "In the Reach" : "In the Grip", "reading\u2026");
    });
    if (!p) {
      ["reach", "grip"].forEach(function (k) {
        rows[k].lastChild.textContent = "not reported";
      });
    } else {
      [["reach", C.reach], ["grip", C.grip]].forEach(function (pair) {
        p.request({ method: "eth_getBalance", params: [pair[1], "latest"] })
          .then(function (b) { rows[pair[0]].lastChild.textContent = eth(BigInt(b)) + " ETH"; })
          /*  Not zero. Nobody answered, and those are different facts. */
          .catch(function () { rows[pair[0]].lastChild.textContent = "not reported"; });
      });
    }

    if (!onlyHolder(h)) return;
    h.appendChild(el("hr"));
    h.appendChild(el("div", "k", "BRING THEM INTO BEING"));
    note(h, "Both addresses exist as arithmetic before anything is deployed to them. " +
            "A hand that has not been embodied can still receive; it cannot yet act.");
    button(h, "Embody the Reach", true, function () {
      propose("EMBODY THE REACH", [["Token", "#" + C.id], ["Deploys", short(C.reach)]],
        { to: C.hub, data: C.sel.embody + enc.uint(C.id) });
    });
    button(h, "Embody the Grip", true, function () {
      propose("EMBODY THE GRIP", [["Token", "#" + C.id], ["Deploys", short(C.grip)]],
        { to: C.hub, data: C.sel.embodyGrip + enc.uint(C.id) });
    });

    h.appendChild(el("hr"));
    h.appendChild(el("div", "k", "PAY INTO THE GRIP"));
    var amt = field(h, "AMOUNT IN ETH", "0.0");
    button(h, "Review the payment", false, function () {
      var v = wei(amt.value);
      if (v == null || v === 0n) return say("An amount, in ether.", "err");
      propose("PAY INTO THE GRIP", [
        ["Token", "#" + C.id],
        ["To", short(C.grip)],
        ["Amount", eth(v) + " ETH"],
        ["Reversible", "no \u2014 nothing can leave the Grip"]
      ], { to: C.grip, value: "0x" + v.toString(16) });
    });
  };

  /* 3 · TRADE THROUGH IT */
  LANE[3] = function (h) {
    /*  The contract already rendered the market's state above; what is
        added is the acts. Bit 1 is the pool, and a clear bit means the
        pool did not answer rather than that there is no market.        */
    if (!(C.reported & 2) || !C.pool || !C.mkt) {
      note(h, "No market contract answered on this chain. That is not the same as this " +
              "token having no market, and the console will not print one as the other.");
      return;
    }
    var m = C.mkt;

    /*── the two coins, resolved once each ──*/
    /*  `dec: null` means the coin's own decimals() did not answer, and it
        stays null: every amount for that coin then refuses rather than
        guesses, because an amount scaled by an assumed exponent is wrong
        by factors of ten. The symbol is cosmetic and may fall back to the
        short address; the exponent is custody and may not.             */
    var COINS = {};
    function coinOf(a) {
      if (COINS[a]) return COINS[a];
      var c = { addr: a, sym: short(a), dec: null };
      COINS[a] = c;
      call(a, C.sel.symbol).then(function (r) {
        var s = decodeSym(r);
        if (s) c.sym = s;
      }).catch(function () {});
      call(a, C.sel.decimals).then(function (r) {
        if (r && r !== "0x") c.dec = Number(BigInt(r));
      }).catch(function () {});
      return c;
    }
    function decodeSym(r) {
      if (!r || r === "0x") return null;
      var d = r.slice(2), hx;
      if (d.length === 64) {
        hx = d.replace(/(00)+$/, "");           // bytes32, the old dialect
      } else if (d.length >= 192) {
        var len = parseInt(d.substr(64, 64), 16);
        if (!len || len > 32) return null;
        hx = d.substr(128, len * 2);
      } else return null;
      var s = deHex(hx);
      /*  Printable ASCII, twelve characters, or the address stands in. A
          chain string reaches this DOM through textContent only, and a
          symbol longer than a word is somebody being clever.           */
      return s && /^[\x20-\x7e]{1,12}$/.test(s) ? s : null;
    }
    function parseAmt(c, v, label) {
      if (!String(v).trim()) return 0n;
      if (c.dec == null) {
        say("The decimals of " + c.sym + " did not answer, and the console will not " +
            "guess where the point goes.", "err");
        return null;
      }
      var a = units(v, c.dec);
      if (a == null) { say(label + " is not a number.", "err"); return null; }
      return a;
    }

    /*  §D.3 #24: the approval is the button's CURRENT STEP, never a
        separate control — press once, sign the approval; press the same
        button again, sign the act. And always the exact amount, never
        unlimited: an allowance that outlives its swap is a standing order
        nobody remembers signing.                                       */
    function stepThenPropose(steps, fin) {
      var i = 0;
      var next = function () {
        while (i < steps.length && steps[i].need === 0n) i++;
        if (i >= steps.length) return fin();
        var s = steps[i];
        call(s.coin.addr, C.sel.allowance + enc.addr(C.account) + enc.addr(C.pool))
          .then(function (r) {
            var have = r && r !== "0x" ? BigInt(r) : 0n;
            if (have >= s.need) { i++; return next(); }
            propose("APPROVE — THE CURRENT STEP", [
              ["Lets", "the market pull exactly " + amt(s.need, s.coin.dec) + " " + s.coin.sym],
              ["Never", "unlimited"],
              ["Then", "press the same button again"]
            ], { to: s.coin.addr, data: C.sel.approve + enc.addr(C.pool) + enc.uint(s.need) },
              "approve(address,uint256)");
          })
          .catch(function () { say("The allowance did not answer.", "err"); });
      };
      next();
    }

    /*── closed: the exchange does not exist yet ──*/
    if (!m.open) {
      h.appendChild(el("div", "k", "ITS OWN EXCHANGE"));
      note(h, "This token has no market open. Its holder can open one: the pool prices " +
              "it from the artwork's own orientation, and the fee is paid to whoever " +
              "holds the token.");
      if (!onlyHolder(h)) return;
      var oB = field(h, "BASE COIN", "0x…");
      var oQ = field(h, "QUOTE COIN", "0x…");
      var oF = field(h, "FEE, IN BPS", "30");
      button(h, "Review the opening", false, function () {
        var b = String(oB.value).trim(), q = String(oQ.value).trim();
        if (!/^0x[0-9a-fA-F]{40}$/.test(b) || !/^0x[0-9a-fA-F]{40}$/.test(q))
          return say("Two coin addresses.", "err");
        if (b.toLowerCase() === q.toLowerCase()) return say("Two DIFFERENT coins.", "err");
        var f = Number(oF.value);
        if (!(f >= 0) || f !== Math.floor(f)) return say("The fee, in whole bps.", "err");
        propose("OPEN ITS MARKET", [
          ["Token", "#" + C.id],
          ["Base", short(b)],
          ["Quote", short(q)],
          ["Fee", f + " bps, paid to whoever holds the token"],
          ["Priced by", "the artwork's own orientation"]
        ], { to: C.pool, data: C.sel.open + enc.uint(C.id) + enc.addr(b) + enc.addr(q) + enc.uint(f) },
          "openMarket(uint256,address,address,uint16)");
      });
      note(h, "Where the collection keeps a blessed pair list, the chain refuses a pair " +
              "off it — the control is shown and the chain decides, which is this " +
              "console's rule for every control.");
      return;
    }

    /*── open: the swap, for anyone with a wallet ──*/
    var B = coinOf(m.base), Q = coinOf(m.quote);
    h.appendChild(el("div", "k", "ITS OWN EXCHANGE"));
    note(h, "Swapping needs no permission from the holder — the fee above is what " +
            "they earn from you. The price is quoted first and the swap refuses to " +
            "settle below what the slab states.");
    if (!C.account) {
      note(h, "Connect a wallet to trade.");
    } else {
      var baseIn = false;
      var dirRow = el("div", "kv");
      dirRow.appendChild(el("span", "k", "DIRECTION"));
      var buyB = el("button", "chip", "buy"), sellB = el("button", "chip", "sell");
      buyB.type = sellB.type = "button";
      var paintDir = function () {
        buyB.style.opacity = baseIn ? ".5" : "1";
        sellB.style.opacity = baseIn ? "1" : ".5";
        buyB.textContent = "buy " + B.sym;
        sellB.textContent = "sell " + B.sym;
      };
      buyB.addEventListener("click", function () { baseIn = false; paintDir(); });
      sellB.addEventListener("click", function () { baseIn = true; paintDir(); });
      dirRow.appendChild(buyB); dirRow.appendChild(sellB);
      h.appendChild(dirRow);
      setTimeout(paintDir, 800);   // after the symbols have had a chance to answer
      paintDir();

      var sAmt = field(h, "AMOUNT IN", "0.0");
      button(h, "Review the swap", false, function () {
        var IN = baseIn ? B : Q, OUT = baseIn ? Q : B;
        var a = parseAmt(IN, sAmt.value, "The amount");
        if (a == null) return;
        if (a === 0n) return say("An amount of " + IN.sym + ".", "err");
        stepThenPropose([{ coin: IN, need: a }], function () {
          /*  Quoted at review time, every time — a price read when the lane
              opened is a price from another block.                       */
          call(C.pool, C.sel.quote + enc.uint(C.id) + enc.uint(baseIn ? 1 : 0) + enc.uint(a))
            .then(function (r) {
              if (!r || r === "0x") return say("The market would not price it.", "err");
              var out = BigInt(r);
              if (out === 0n) return say("That amount prices at zero — nothing to swap.", "err");
              /*  Half a percent below the quote, stated in the slab, and the
                  contract refuses beneath it. Fifteen minutes and the intent
                  dies: both are front-running defenses, not conveniences. */
              var minOut = out - out * 50n / 10000n;
              var dl = BigInt(Math.floor(Date.now() / 1000) + 900);
              var outWords = OUT.dec == null ? out.toString() + " units" : amt(out, OUT.dec) + " " + OUT.sym;
              var minWords = OUT.dec == null ? minOut.toString() + " units" : amt(minOut, OUT.dec) + " " + OUT.sym;
              propose("SWAP THROUGH ITS MARKET", [
                ["Token", "#" + C.id],
                ["In", amt(a, IN.dec) + " " + IN.sym],
                ["Out", "about " + outWords],
                ["No less than", minWords + " — or nothing moves"],
                ["Dies", "in fifteen minutes"]
              ], { to: C.pool, data: C.sel.swap + enc.uint(C.id) + enc.uint(baseIn ? 1 : 0) +
                   enc.uint(a) + enc.uint(minOut) + enc.addr(C.account) + enc.uint(dl) },
                "swap(uint256,bool,uint256,uint256,address,uint256)");
            })
            .catch(function () { say("The market would not price it.", "err"); });
        });
      });
    }

    /*── the holder's half ──*/
    if (mine()) {
      h.appendChild(el("hr"));
      h.appendChild(el("div", "k", "INVENTORY"));
      note(h, "You are the only maker this market will ever have. What you deposit is " +
              "what it trades; what you withdraw is yours again — unless the bond " +
              "below says otherwise.");
      var dB = field(h, "DEPOSIT " + (B.sym || "BASE"), "0.0");
      var dQ = field(h, "AND " + (Q.sym || "QUOTE"), "0.0");
      button(h, "Review the deposit", false, function () {
        var ab = parseAmt(B, dB.value, "The base amount");
        if (ab == null) return;
        var aq = parseAmt(Q, dQ.value, "The quote amount");
        if (aq == null) return;
        if (ab === 0n && aq === 0n) return say("An amount of either coin.", "err");
        stepThenPropose([{ coin: B, need: ab }, { coin: Q, need: aq }], function () {
          propose("DEPOSIT INVENTORY", [
            ["Token", "#" + C.id],
            [B.sym, amt(ab, B.dec == null ? 0 : B.dec)],
            [Q.sym, amt(aq, Q.dec == null ? 0 : Q.dec)],
            ["Counted as", "what actually arrives, not what was sent"]
          ], { to: C.pool, data: C.sel.deposit + enc.uint(C.id) + enc.uint(ab) + enc.uint(aq) },
            "deposit(uint256,uint256,uint256)");
        });
      });

      var wB = field(h, "WITHDRAW " + (B.sym || "BASE"), "0.0");
      var wQ = field(h, "AND " + (Q.sym || "QUOTE"), "0.0");
      button(h, "Review the withdrawal", true, function () {
        var ab = parseAmt(B, wB.value, "The base amount");
        if (ab == null) return;
        var aq = parseAmt(Q, wQ.value, "The quote amount");
        if (aq == null) return;
        if (ab === 0n && aq === 0n) return say("An amount of either coin.", "err");
        propose("WITHDRAW INVENTORY", [
          ["Token", "#" + C.id],
          [B.sym, amt(ab, B.dec == null ? 0 : B.dec)],
          [Q.sym, amt(aq, Q.dec == null ? 0 : Q.dec)],
          ["To", short(C.account)],
          ["Refused while", "the bond below stands"]
        ], { to: C.pool, data: C.sel.withdraw + enc.uint(C.id) + enc.uint(ab) + enc.uint(aq) +
             enc.addr(C.account) },
          "withdraw(uint256,uint256,uint256,address)");
      });

      h.appendChild(el("hr"));
      h.appendChild(el("div", "k", "THE FEE"));
      kv(h, "Now", m.fee + " bps, to whoever holds the token");
      var fIn = field(h, "SET IT TO, IN BPS", String(m.fee));
      button(h, "Review the fee", true, function () {
        var f = Number(fIn.value);
        if (!(f >= 0) || f !== Math.floor(f)) return say("Whole bps.", "err");
        propose("SET THE FEE", [
          ["Token", "#" + C.id],
          ["From", m.fee + " bps"], ["To", f + " bps"],
          ["Refused while", "the bond stands — a bonded market's terms are promised"]
        ], { to: C.pool, data: C.sel.setFee + enc.uint(C.id) + enc.uint(f) },
          "setFee(uint256,uint16)");
      });

      h.appendChild(el("hr"));
      h.appendChild(el("div", "k", "THE BOND"));
      note(h, "A bond promises the inventory stays: no withdrawal, no fee change, no " +
              "re-anchoring until it lapses. It only ever lengthens, and it survives " +
              "sale — a promise you could shorten would not be one.");
      var bDays = field(h, "BOND FOR HOW MANY DAYS", "7");
      button(h, "Review the bond", true, function () {
        var d = Number(bDays.value);
        if (!d || d < 0 || d !== Math.floor(d)) return say("Days, as a whole number.", "err");
        var untilTs = Math.floor(Date.now() / 1000) + d * 86400;
        propose("BOND THE INVENTORY", [
          ["Token", "#" + C.id],
          ["For", d + (d === 1 ? " day" : " days")],
          ["Reversible", "no — a bond only lengthens, and it survives sale"]
        ], { to: C.pool, data: C.sel.bond + enc.uint(C.id) + enc.uint(untilTs) },
          "bond(uint256,uint64)");
      });

      h.appendChild(el("hr"));
      h.appendChild(el("div", "k", "THE CURVE"));
      /*  The one place the artwork feeds the economics. The anchors move
          here and at deposit/withdraw/open — never in a swap — so
          turning the word and then syncing is the holder repricing on
          purpose, in a transaction with their name on it.               */
      var dr = kv(h, "Against the artwork", "reading…");
      call(C.pool, C.sel.drift + enc.uint(C.id)).then(function (r) {
        if (!r || r.length < 194) { dr.lastChild.textContent = "not reported"; return; }
        var drifted = BigInt("0x" + r.slice(2, 66)) !== 0n;
        var nowB = BigInt("0x" + r.slice(66, 130));
        var would = BigInt("0x" + r.slice(130, 194));
        dr.lastChild.textContent = drifted
          ? "the artwork has turned — anchored at " + nowB + " bps, it implies " + would + " bps"
          : "in agreement";
      }).catch(function () { dr.lastChild.textContent = "not reported"; });
      button(h, "Re-anchor to the artwork", true, function () {
        propose("SYNC THE CURVE", [
          ["Token", "#" + C.id],
          ["Reads", "the orientation word, this block"],
          ["This is", "the only place the artwork moves the price"]
        ], { to: C.pool, data: C.sel.sync + enc.uint(C.id) }, "syncCurve(uint256)");
      });

      h.appendChild(el("hr"));
      h.appendChild(el("div", "k", "CLOSE IT"));
      button(h, "Review the closing", true, function () {
        propose("CLOSE ITS MARKET", [
          ["Token", "#" + C.id],
          ["Refused unless", "the inventory is empty and the bond has lapsed"]
        ], { to: C.pool, data: C.sel.close + enc.uint(C.id) }, "closeMarket(uint256)");
      });
    }

    /*  The OTHER trading surface, pointed at rather than absorbed: who is
        paid the fee must stay loud, and on /swap it is a public pool's
        LPs, not this token's holder.                                    */
    var sw = el("p", "s");
    var swA = el("a", "g", "trading on public pools is its own surface — /swap");
    swA.href = "/swap";
    sw.appendChild(swA);
    h.appendChild(sw);
  };

  /* 4 · HAND IT ON — the sections run shallow to deep, and that ordering
     is the warning: everything above the last heading ends by itself or
     can be taken back, and nothing below it can.                        */
  LANE[4] = function (h) {
    var can = mine();

    /*── FOR AN AFTERNOON ──*/
    h.appendChild(el("div", "k", "FOR AN AFTERNOON"));
    var nowS = Math.floor(Date.now() / 1000);
    var lent = !!(C.user && !/^0x0{40}$/i.test(C.user) && Number(C.userX || 0) > nowS);
    if (!(C.reported & 16)) {
      /*  The bit, not the address: a hub that did not answer userOf is not
          a token nobody borrows.                                        */
      note(h, "Whether it is lent out was not reported.");
    } else if (lent) {
      var ld = Math.floor((Number(C.userX) - nowS) / 86400);
      kv(h, "Lent to", short(C.user) + (ld < 1 ? ", until today"
        : ld === 1 ? ", for one more day" : ", for " + ld + " more days"));
    } else {
      note(h, "Nobody borrows it right now. Lending is free and ends by itself: the " +
              "borrower runs the instrument, and cannot move the token, spend from " +
              "its hands, or speak as it.");
    }
    if (can) {
      var uAddr = field(h, "LEND IT TO", "0x…");
      var uDays = field(h, "FOR HOW MANY DAYS", "1");
      button(h, "Review the loan", false, function () {
        var a = String(uAddr.value).trim();
        if (!/^0x[0-9a-fA-F]{40}$/.test(a)) return say("That is not an address.", "err");
        var d = Number(uDays.value);
        if (!d || d < 0 || d !== Math.floor(d)) return say("Days, as a whole number.", "err");
        var x = Math.floor(Date.now() / 1000) + d * 86400;
        propose("LEND IT, FREE", [
          ["Token", "#" + C.id],
          ["To", short(a)],
          ["For", d + (d === 1 ? " day" : " days")],
          ["Ends", "by itself — nothing to take back"]
        ], { to: C.hub, data: C.sel.setUser + enc.uint(C.id) + enc.addr(a) + enc.uint(x) },
          "setUser(uint256,address,uint64)");
      });
      if (lent) button(h, "Take it back now", true, function () {
        propose("END THE LOAN NOW", [
          ["Token", "#" + C.id],
          ["Was lent to", short(C.user)]
        ], { to: C.hub, data: C.sel.setUser + enc.uint(C.id) +
             enc.addr("0x0000000000000000000000000000000000000000") + enc.uint(0) },
          "setUser(uint256,address,uint64)");
      });
    }

    /*  A session key is the lend built for a program: bounded in time,
        spend and doors. Granting stays at /keys and the key's own door is
        /k — a key's holder is not the token's holder, so their surface is
        their own.                                                       */
    var links = el("p", "s");
    var a1 = el("a", "g", "grant a bounded key at /keys");
    a1.href = "/keys";
    var a2 = el("a", "g", "a granted key's own door is /k/" + C.id + "/‹key›");
    a2.href = "/k/" + C.id + "/" + (C.account || "0x0000000000000000000000000000000000000000");
    links.appendChild(a1);
    links.appendChild(document.createTextNode(" · "));
    links.appendChild(a2);
    h.appendChild(links);

    /*── FOR A SEASON · FOR A PRICE ──*/
    h.appendChild(el("hr"));
    h.appendChild(el("div", "k", "FOR A SEASON"));
    unbuilt(h, "The lease — listing, renting, collecting, settling — is not built into " +
               "the console yet. Its state above was read from the chain this block.");
    h.appendChild(el("div", "k", "FOR A PRICE"));
    unbuilt(h, "Consignment and inheritance are not built into the console yet.");

    /*── FOR GOOD ──*/
    h.appendChild(el("hr"));
    h.appendChild(el("div", "k", "FOR GOOD"));
    /*  The bolt's state is readable by anyone; only the acts are gated. */
    var bolt = kv(h, "The bolt", "reading…");
    call(C.hub, C.sel.locked + enc.uint(C.id)).then(function (r) {
      if (!r || r === "0x") { bolt.lastChild.textContent = "not reported"; return; }
      bolt.lastChild.textContent = BigInt(r) === 0n
        ? "open — it can move" : "shut — nothing can move it";
    }).catch(function () { bolt.lastChild.textContent = "not reported"; });

    if (!onlyHolder(h)) return;
    note(h, "A transfer ends everything the token was doing under you — a loan, a " +
            "lease, a session key, a consignment. It is the only act in this lane " +
            "that cannot be undone.");
    var to = field(h, "SEND IT TO", "0x…");
    button(h, "Review the transfer", false, function () {
      var a = String(to.value).trim();
      if (!/^0x[0-9a-fA-F]{40}$/.test(a)) return say("That is not an address.", "err");
      if (a.toLowerCase() === C.owner.toLowerCase()) return say("It is already theirs.", "err");
      propose("HAND IT ON, FOR GOOD", [
        ["Token", "#" + C.id],
        ["From", short(C.owner)],
        ["To", short(a)],
        ["Reversible", "no"]
      ], { to: C.hub, data: C.sel.xfer + enc.addr(C.owner) + enc.addr(a) + enc.uint(C.id) },
        "transferFrom(address,address,uint256)");
    });

    /*  §D.4 #5: the bolt lives under FOR GOOD because it is the refusal to
        hand on — while it is shut nothing, not a sale, not a market, not a
        mistake in another tab, can move the token. The holder can always
        unbolt; the wrong button is refused by the chain, not hidden.    */
    h.appendChild(el("div", "k", "BOLT IT SHUT"));
    button(h, "Bolt it shut", true, function () {
      propose("BOLT IT SHUT", [
        ["Token", "#" + C.id],
        ["While shut", "nothing can move it, including you"],
        ["Undone by", "you, at any time"]
      ], { to: C.hub, data: C.sel.lock + enc.uint(C.id) }, "lock(uint256)");
    });
    button(h, "Unbolt it", true, function () {
      propose("UNBOLT IT", [["Token", "#" + C.id]],
        { to: C.hub, data: C.sel.unlock + enc.uint(C.id) }, "unlock(uint256)");
    });
  };

  /* 5 · SPEAK AS IT */
  LANE[5] = function (h) {
    if (!C.parley || !C.said) {
      note(h, "No Parley contract answered on this chain. That is not the same as this " +
              "token having nothing to say, and the console will not print one as the other.");
      return;
    }

    /*  The sentence CONSOLE.md §D.5 requires this lane to open with,
        because this is the one lane with a past and the past needs its
        justification stated where it is shown.                          */
    note(h, "Everything said in the commons is here, exactly and completely, because " +
            "every message points at the block of the one before it. Nothing else in " +
            "this console shows a past, because nothing else can prove one.");

    h.appendChild(el("div", "k", "THE COMMONS"));
    var feed = el("div");
    feed.style.marginTop = "8px";
    h.appendChild(feed);
    var status = note(h, "reading…");

    /*  The walk. One `stateOf` for the newest block, then one SINGLE-BLOCK
        eth_getLogs per message-bearing block, each hop taken from the
        oldest message's `prev` pointer. No ranges, no indexer, no cache:
        the archive's own back-links are the pagination. Twelve blocks of
        talk, then the count of what lies deeper.                        */
    function row(from, text, muted) {
      var d = el("div", "kv");
      d.appendChild(el("span", "k", "#" + from));
      var v = el("span", "v", text);
      if (muted) v.style.opacity = ".55";
      d.appendChild(v);
      feed.appendChild(d);
    }
    function said(log) {
      var d = log.data.slice(2);
      var prev = BigInt("0x" + d.substr(0, 64));
      var kind = parseInt(d.substr(64 * 3, 64), 16);
      var off = parseInt(d.substr(64 * 4, 64), 16) * 2;
      var len = parseInt(d.substr(off, 64), 16);
      var from = BigInt(log.topics[2]).toString();
      var text;
      if (kind === 1) {
        text = "— a sealed message —";
      } else {
        text = deHex(d.substr(off + 64, len * 2));
        if (text == null) text = "— not text —";
      }
      return { prev: prev, from: from, text: text, muted: kind === 1 || text.charAt(0) === "—" };
    }
    function walk() {
      var p = provider();
      call(C.parley, C.sel.state + enc.uint(0)).then(function (r) {
        if (!r || r.length < 130) { status.textContent = "The commons did not answer."; return; }
        var last = BigInt("0x" + r.slice(2, 66));
        var count = BigInt("0x" + r.slice(66, 130));
        if (last === 0n) {
          status.textContent = "Nothing has ever been said in the commons on this chain.";
          return;
        }
        var shown = 0, hops = 0;
        var step = function (blk) {
          if (blk === 0n) {
            status.textContent = "All " + count + (count === 1n ? " message." : " messages.");
            return;
          }
          if (hops >= 12) {
            status.textContent = "…and older messages, back past block " + blk + ". " +
                                 count + " ever said here.";
            return;
          }
          hops += 1;
          p.request({ method: "eth_getLogs", params: [{
            address: C.parley,
            fromBlock: "0x" + blk.toString(16),
            toBlock: "0x" + blk.toString(16),
            topics: [C.said, "0x" + "0".repeat(64)]
          }] }).then(function (logs) {
            if (!logs || !logs.length) {
              status.textContent = "The chain would not answer for block " + blk.toString() + ".";
              return;
            }
            /*  Newest first on screen, so a block's logs render in reverse;
                the pointer onward is the OLDEST message's prev — messages
                that share a block point within it, and only the first one
                points out of it.                                        */
            for (var i = logs.length - 1; i >= 0; i--) {
              var s = said(logs[i]);
              row(s.from, s.text, s.muted);
              shown += 1;
            }
            step(said(logs[0]).prev);
          }).catch(function () {
            status.textContent = "The wallet's node refused eth_getLogs — the walk cannot start.";
          });
        };
        step(last);
      }).catch(function () { status.textContent = "The commons did not answer."; });
    }
    if (!provider()) {
      status.textContent = "Reading the commons needs a wallet's node — connect one and " +
                           "the walk starts from the newest block.";
    } else {
      walk();
    }

    /*── heard from other chains ──*/
    /*  The second archive, kept visibly second. The port deliberately
        cannot write into Parley — nothing may impersonate a local token —
        so a foreign voice arrives as the port's own `Echoed` log, walked
        here by the same single-block step, labeled by the chain it came
        from, and never mixed into the local column above.               */
    h.appendChild(el("hr"));
    h.appendChild(el("div", "k", "HEARD FROM OTHER CHAINS"));
    if (!C.port || !C.echoed) {
      note(h, "No port is wired on this chain, so other chains' commons do not " +
              "arrive here. The local commons above is the whole of what this " +
              "chain can hear.");
    } else {
      var ffeed = el("div");
      ffeed.style.marginTop = "8px";
      h.appendChild(ffeed);
      var fstatus = note(h, "reading…");
      var eidName = function (n) {
        return (C.eids && C.eids[String(n)]) ? C.eids[String(n)] : "eid " + n;
      };
      var frow = function (from, origin, text, muted) {
        var d = el("div", "kv");
        d.appendChild(el("span", "k", "#" + from + " · " + origin));
        var v = el("span", "v", text);
        if (muted) v.style.opacity = ".55";
        d.appendChild(v);
        ffeed.appendChild(d);
      };
      var fwalk = function () {
        call(C.port, C.sel.echoLast).then(function (r) {
          if (!r || r === "0x") { fstatus.textContent = "The port did not answer."; return; }
          var last = BigInt(r);
          if (last === 0n) {
            /*  A genuine zero from a live getter: the port stands and has
                heard nothing. Different fact from the line above it.    */
            fstatus.textContent = "Nothing has arrived from another chain yet.";
            return;
          }
          var hops = 0;
          var step = function (blk) {
            if (blk === 0n) {
              fstatus.textContent = "That is every foreign voice ever heard here.";
              return;
            }
            if (hops >= 8) {
              fstatus.textContent = "…and older arrivals, back past block " + blk + ".";
              return;
            }
            hops += 1;
            provider().request({ method: "eth_getLogs", params: [{
              address: C.port,
              fromBlock: "0x" + blk.toString(16),
              toBlock: "0x" + blk.toString(16),
              topics: [C.echoed]
            }] }).then(function (logs) {
              if (!logs || !logs.length) {
                fstatus.textContent = "The chain would not answer for block " + blk.toString() + ".";
                return;
              }
              /*  Echoed's head is one word shorter than Said's — no
                  prevFrom, the origin rides in a topic — so kind sits at
                  word 2 and the body offset at word 3.                  */
              for (var i = logs.length - 1; i >= 0; i--) {
                var d = logs[i].data.slice(2);
                var kind = parseInt(d.substr(64 * 2, 64), 16);
                var o = parseInt(d.substr(64 * 3, 64), 16) * 2;
                var len = parseInt(d.substr(o, 64), 16);
                var text = kind === 1 ? "— a sealed message —"
                  : (deHex(d.substr(o + 64, len * 2)) || "— not text —");
                frow(BigInt(logs[i].topics[2]).toString(),
                     eidName(Number(BigInt(logs[i].topics[1]))),
                     text, kind === 1 || text.charAt(0) === "—");
              }
              step(BigInt("0x" + logs[0].data.slice(2, 66)));
            }).catch(function () {
              fstatus.textContent = "The wallet's node refused eth_getLogs — the walk cannot start.";
            });
          };
          step(last);
        }).catch(function () { fstatus.textContent = "The port did not answer."; });
      };
      if (!provider()) {
        fstatus.textContent = "Reading needs a wallet's node.";
      } else {
        fwalk();
      }
    }

    /*── the composer ──*/
    if (mine()) {
      h.appendChild(el("hr"));
      h.appendChild(el("div", "k", "SAY SOMETHING"));
      var msg = field(h, "AS #" + C.id, "a log, forever, readable by anyone");
      button(h, "Review the message", false, function () {
        var s = String(msg.value);
        if (!s.trim()) return say("Something to say.", "err");
        var hx = utf8hex(s);
        var bytes = hx.length / 2;
        if (bytes > 1024) {
          return say("The commons takes 1024 bytes and that is " + bytes +
                     ". Say it in two.", "err");
        }
        var padded = hx + "0".repeat((64 - (hx.length % 64)) % 64);
        propose("SPEAK AS IT", [
          ["Room", "the commons — every token reads it, forever"],
          ["Token", "#" + C.id],
          ["Says", s.length > 70 ? s.slice(0, 70) + "…" : s]
        ], { to: C.parley, data: C.sel.speak + enc.uint(0) + enc.uint(C.id) + enc.uint(0) +
             enc.uint(128) + enc.uint(bytes) + padded },
          "speak(uint256,uint256,uint8,bytes)");
      });
      note(h, "Deleting is not offered because it is not possible: a message is a log, " +
              "and the chain keeps those.");
    } else {
      note(h, C.account
        ? "Only the holder — or the token's own Reach — may speak as it. A renter " +
          "buys the instrument's use, not its name."
        : "Connect the holding wallet to speak as it.");
    }

    unbuilt(h, "Whispers, rooms and what it signs are not built into the console yet. " +
               "They are live at the collection's own contracts and the console does " +
               "not pretend otherwise.");
  };

  /* 6 · MAKE SOMETHING WITH IT */
  LANE[6] = function (h) {
    h.appendChild(el("div", "k", "DRAW THE NEXT ONE"));
    note(h, "Every token is minted on the chain whose band its number falls in. This " +
            "chain issues " + C.first + " to " + C.last + ".");

    /*  The price, read before the button and attached to the send. The
        first version claimed "read by the wallet from the contract" and
        sent no value at all — a payable mint proposed at zero, which
        reverts, on the strength of a thing no injected wallet actually
        does. The cost is stated before the button, and the button sends
        what was stated; a price that does not answer refuses to guess. */
    var price = null;
    var row = kv(h, "Price now", "reading…");
    call(C.hub, C.sel.price).then(function (r) {
      if (r && r !== "0x") {
        price = BigInt(r);
        row.lastChild.textContent = eth(price) + " ETH, to the collection";
      } else {
        row.lastChild.textContent = "not reported";
      }
    }).catch(function () { row.lastChild.textContent = "not reported"; });

    button(h, "Review the mint", false, function () {
      if (price == null)
        return say("The price did not answer, and the console will not guess a payable value.", "err");
      propose("DRAW THE NEXT ONE", [
        ["On", "chain " + C.chain],
        ["Band", "#" + C.first + " to #" + C.last]
      ], { to: C.hub, data: C.sel.mint, value: "0x" + price.toString(16) },
        "mint()");
    });
    unbuilt(h, "Launching a coin and giving the token a name are not built into the " +
               "console yet.");
  };

  /* 7 · LOOK AT ANOTHER ONE */
  LANE[7] = function (h) {
    h.appendChild(el("div", "k", "ANY OF THEM"));
    note(h, "Walking into another token adds a rule to the left margin in that token's " +
            "colour. The rule is the way back. What opens there is its still, drawn on " +
            "chain — never its instrument, because two of those on one thread is what " +
            "made a phone hot.");
    var n = field(h, "BY NUMBER", "#" + C.first);
    button(h, "Walk into it", false, function () {
      C.walkTo(String(n.value).replace(/^#/, ""));
    });

    h.appendChild(el("hr"));
    h.appendChild(el("div", "k", "NEARBY"));
    var strip = el("div");
    strip.style.marginTop = "8px";
    for (var d = -3; d <= 3; d++) {
      var id = C.id + d;
      if (d === 0 || id < C.first || id > C.last) continue;
      (function (tid) {
        var b = el("button", "chip", "#" + tid);
        b.type = "button";
        b.addEventListener("click", function () { C.walkTo(tid); });
        strip.appendChild(b);
      })(id);
    }
    h.appendChild(strip);
  };

  /*───────────────────────── arrival ─────────────────────────*/

  var lane = $("#lane");
  if (lane && C.verb && LANE[C.verb]) {
    /*  After the wallet has answered, because whether these controls may
        act depends on who is holding it, and a lane painted before that
        answer told a holder to connect while the crest said "you".     */
    Promise.resolve(C.ready).then(function () {
      /*  The contract's note says the controls need a script. They are
          about to exist, so it goes — a surface that keeps apologising
          after it has delivered is a surface nobody trusts.           */
      var n = $("#lane-note");
      if (n) n.remove();
      var hold = el("div");
      hold.style.marginTop = "14px";
      lane.appendChild(hold);
      try { LANE[C.verb](hold); }
      catch (e) { say("This lane failed to open: " + (e && e.message), "err"); }
    });
  }
})();

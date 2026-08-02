// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";

/*───────────────────────────────────────────────────────────────────────────
  Chrome — the parts of the site that are the same on every page

  Five contracts render pages, and EIP-170 is why there are five rather than
  one. Left to themselves each would carry its own copy of the stylesheet
  and its own copy of the wallet client, which wastes the bytes twice over:
  once in code size, and once when the copies drift and the site stops
  looking like one site. So the shell lives here and the pages call it.

  The application itself lives in `Desk.sol`, which outgrew this contract
  the moment the pages stopped being reference sheets and started being
  something a person could use. This holds what every page looks like: the
  stylesheet, the navigation, and the footer.
───────────────────────────────────────────────────────────────────────────*/
contract Chrome {
    using LibNum for uint256;

    /*═══════════════════ the shell ═══════════════════*/

    function head(string memory title) external pure returns (string memory) {
        return string.concat(
            "<!doctype html><meta charset=utf-8>"
            "<meta name=viewport content=\"width=device-width,initial-scale=1\">"
            "<title>", title, "</title><style>", CSS, "</style>"
        );
    }

    string internal constant CSS =
        ":root{color-scheme:dark}"
        "body{background:#07080c;color:#c9d3e6;font:15px/1.65 ui-sans-serif,system-ui,sans-serif;"
        "max-width:62rem;margin:0 auto;padding:2.2rem 1.5rem 6rem}"
        "h1{font-weight:500;letter-spacing:.22em;font-size:1.5rem;margin:0 0 .3rem}"
        "h2{font-weight:500;letter-spacing:.14em;font-size:.8rem;text-transform:uppercase;"
        "color:#8b95ad;margin:2.6rem 0 .8rem}"
        "h3{font-weight:500;font-size:1rem;margin:1.6rem 0 .4rem;color:#dbe4f5}"
        "a{color:#7fd4ff}.b{text-decoration:none;color:#8b95ad}"
        ".g{display:inline-block;border:1px solid #2a3550;border-radius:.4rem;"
        "padding:.5rem .9rem;text-decoration:none;margin:0 .4rem .6rem 0}"
        ".e{color:#8b95ad;font-size:.92rem}"
        ".w{color:#ffb27f}.ok{color:#7fe0a8}.no{color:#ff8a8a}"
        "code{font:12.5px ui-monospace,monospace;color:#9fb0cc;overflow-wrap:anywhere}"
        "dl{display:grid;grid-template-columns:9.5rem 1fr;gap:.35rem 1rem;margin:1.4rem 0}"
        "dt{color:#6c7689;font-size:.82rem;letter-spacing:.1em;text-transform:uppercase}"
        "dd{margin:0}"
        "ul.r{list-style:none;padding:0;display:grid;"
        "grid-template-columns:repeat(auto-fill,minmax(11rem,1fr));gap:.5rem}"
        "ul.r li{border:1px solid #1a2030;border-radius:.4rem;padding:.6rem .8rem}"
        ".m{color:#6c7689;font-size:.8rem;display:block}"
        "iframe,img{width:100%;max-width:38rem;aspect-ratio:1;border:1px solid #1a2030;"
        "border-radius:.5rem;background:#000;display:block}"
        "nav{display:flex;flex-wrap:wrap;gap:.3rem;margin:.2rem 0 1.8rem;"
        "border-bottom:1px solid #161c2a;padding-bottom:1rem}"
        "nav a{font-size:.82rem;letter-spacing:.08em;text-transform:uppercase;"
        "text-decoration:none;color:#8b95ad;padding:.32rem .6rem;border-radius:.3rem}"
        "nav a.on{background:#141a28;color:#cfe3ff}"
        ".card{border:1px solid #1a2030;border-radius:.55rem;padding:1.1rem 1.2rem;margin:.9rem 0}"
        ".card h3{margin-top:0}"
        "table{border-collapse:collapse;width:100%;font-size:.9rem;margin:1rem 0}"
        "th{text-align:left;color:#6c7689;font-weight:500;font-size:.78rem;"
        "letter-spacing:.1em;text-transform:uppercase;padding:.4rem .6rem .4rem 0}"
        "td{padding:.4rem .6rem .4rem 0;border-top:1px solid #141a28}"
        "input{background:#0c0f16;border:1px solid #232c42;border-radius:.35rem;color:#dbe4f5;"
        "font:13px ui-monospace,monospace;padding:.45rem .6rem;width:100%;max-width:22rem}"
        "select{background:#0e131d;border:1px solid #24304a;border-radius:.5rem;"
        "color:#eaf1ff;font:15px ui-sans-serif,system-ui,sans-serif;padding:.55rem .7rem;"
        "width:100%;margin-top:.15rem}"
        "select:focus{outline:none;border-color:#2f3f61}"
        "label{display:block;color:#6c7689;font-size:.78rem;letter-spacing:.08em;"
        "text-transform:uppercase;margin:.7rem 0 .25rem}"
        "button{background:#16203a;border:1px solid #2a3550;border-radius:.4rem;color:#cfe3ff;"
        "font:13px ui-sans-serif,system-ui,sans-serif;padding:.5rem .95rem;cursor:pointer;"
        "margin:.8rem .4rem 0 0}"
        "button:hover{background:#1d2a4a}"
        "#s{margin-top:.9rem;font:12.5px ui-monospace,monospace;color:#8b95ad;"
        "overflow-wrap:anywhere;min-height:1.2em}"
        /*  the exchange card. One column, wide fields, the button doing the
            talking — the shape every exchange on the web has converged on,
            because it is the one where a person can see what they are about
            to sign without reading a paragraph first.                     */
        ".app{max-width:29rem;margin:0 auto;border:1px solid #1e2636;border-radius:1.1rem;"
        "padding:1rem;background:#0a0d14}"
        ".hd{display:flex;align-items:center;justify-content:space-between;"
        "margin:.1rem .3rem .8rem}"
        ".hd b{font-weight:500;letter-spacing:.1em;text-transform:uppercase;font-size:.82rem;"
        "color:#cfe3ff}"
        ".ico{background:none;border:0;color:#6c7689;cursor:pointer;font-size:.78rem;"
        "letter-spacing:.08em;text-transform:uppercase;margin:0;padding:.3rem}"
        ".ico:hover{color:#cfe3ff;background:none}"
        ".fld{background:#0e131d;border:1px solid #1a2233;border-radius:.8rem;"
        "padding:.75rem .9rem;margin:.35rem 0}"
        ".fld:focus-within{border-color:#2f3f61}"
        ".lbl{display:flex;justify-content:space-between;color:#6c7689;font-size:.76rem;"
        "letter-spacing:.06em;margin-bottom:.35rem;text-transform:none}"
        ".row{display:flex;align-items:center;gap:.5rem}"
        ".row input{background:none;border:0;padding:0;font:400 1.55rem/1.2 "
        "ui-sans-serif,system-ui,sans-serif;color:#eaf1ff;max-width:none;flex:1;min-width:0}"
        ".row input:focus{outline:none}"
        ".row input::placeholder{color:#39445c}"
        ".tk{background:#161d2c;border:1px solid #24304a;border-radius:2rem;"
        "padding:.32rem .8rem;font-size:.9rem;color:#dbe4f5;white-space:nowrap;"
        "max-width:9rem;overflow:hidden;text-overflow:ellipsis}"
        ".mx{background:none;border:0;color:#7fd4ff;font-size:.72rem;letter-spacing:.08em;"
        "cursor:pointer;margin:0;padding:.2rem .35rem}"
        ".mx:hover{background:none;color:#b9e7ff}"
        ".flip{display:block;margin:-.7rem auto;position:relative;z-index:1;"
        "width:2rem;height:2rem;padding:0;border-radius:.6rem;background:#141b28;"
        "border:1px solid #23304a;color:#8fa6cc;line-height:1}"
        ".det{margin:.7rem .3rem .2rem;font-size:.83rem;color:#8b95ad}"
        ".det div{display:flex;justify-content:space-between;padding:.16rem 0;gap:1rem}"
        ".det b{font-weight:400;color:#cfe3ff;text-align:right}"
        ".go{width:100%;margin:.9rem 0 0;padding:.85rem;border-radius:.75rem;"
        "font-size:.98rem;background:#1d3a6b;border-color:#2c518f;color:#e6f0ff}"
        ".go:hover:not(:disabled){background:#24478119}"
        ".go:disabled{background:#131a27;border-color:#1e2636;color:#59637a;cursor:default}"
        ".set{background:#0e131d;border:1px solid #1a2233;border-radius:.7rem;"
        "padding:.7rem .8rem;margin:0 0 .5rem;font-size:.82rem}"
        ".set button{margin:.3rem .3rem 0 0;padding:.3rem .6rem;font-size:.78rem;"
        "border-radius:2rem}"
        ".set input{width:5rem;display:inline-block;margin-top:.3rem}"
        ".tabs{display:flex;gap:.4rem;justify-content:center;margin:0 0 1rem}"
        ".tabs a{font-size:.8rem;letter-spacing:.08em;text-transform:uppercase;"
        "text-decoration:none;color:#8b95ad;padding:.35rem .8rem;border-radius:2rem;"
        "border:1px solid transparent}"
        ".tabs a.on{border-color:#24304a;background:#131a27;color:#cfe3ff}"
        /*  the fee-tier row on the Uniswap card: which pools exist for this
            pair, and which one the quote came through                     */
        ".tr{margin:.15rem .3rem 0 0;padding:.25rem .6rem;font-size:.76rem;"
        "border-radius:2rem;background:#0e131d;border-color:#1e2636;color:#8b95ad}"
        ".tr.on{background:#1d3a6b;border-color:#2c518f;color:#e6f0ff}"
        /*  the chart: bars drawn from the pool's own oracle, no canvas and
            no library — a div per observation, height as a percentage      */
        ".ch{display:flex;align-items:flex-end;gap:2px;height:9rem;margin:1rem 0;"
        "border-bottom:1px solid #1a2030;padding-bottom:2px}"
        ".ch i{flex:1;background:#1d3a6b;border-top:1px solid #4a7fd4;min-height:1px;"
        "border-radius:1px 1px 0 0}"
        ".ch i:hover{background:#2c518f}"
        ".two{display:grid;grid-template-columns:1fr 1fr;gap:.6rem}"
        "@media(max-width:30rem){.two{grid-template-columns:1fr}}";

    /*═══════════════════ navigation ═══════════════════*/

    /// @dev `here` is an index into the same order the links are written in,
    ///      so the current page is not a link to itself. 255 means none.
    function nav(uint256 id, uint8 here) external pure returns (string memory) {
        string memory t = id.str();
        return string.concat(
            "<nav>",
            _tab("/", "index", here == 0),
            _tab(string.concat("/token/", t), "token", here == 1),
            _tab(string.concat("/token/", t, "/live"), "instrument", here == 2),
            _tab(string.concat("/token/", t, "/market"), "market", here == 3),
            _tab(string.concat("/token/", t, "/rent"), "rent", here == 4),
            _tab(string.concat("/token/", t, "/vault"), "vault", here == 5),
            _tab(string.concat("/token/", t, "/services.json"), "json", here == 6),
            "</nav>"
        );
    }

    /// @dev The counter's own tabs, under the site nav: the four things a
    ///      token will do, in the order a person meets them.
    function tabs(string memory t, uint8 here) external pure returns (string memory) {
        return string.concat(
            "<div class=tabs>",
            _tab(string.concat("/token/", t, "/market"), "swap", here == 0),
            _tab(string.concat("/token/", t, "/pool"), "pool", here == 1),
            _tab(string.concat("/token/", t, "/rent"), "rent", here == 2),
            _tab(string.concat("/token/", t, "/vault"), "vault", here == 3),
            "</div>"
        );
    }

    /// @dev Two groups, in one bar. The Uniswap surfaces first, because a
    ///      stranger arriving at this site wants to trade something before
    ///      they want to read about the collection; the collection's own
    ///      markets after, because that is the thing that is not available
    ///      anywhere else.
    function navTop(uint8 here) external pure returns (string memory) {
        return string.concat(
            "<nav>",
            _tab("/", "index", here == 0),
            _tab("/swap", "swap", here == 9),
            _tab("/explore", "explore", here == 11),
            _tab("/pools", "pools", here == 10),
            _tab("/limit", "limit", here == 14),
            _tab("/launch", "launch", here == 15),
            _tab("/earn", "earn", here == 12),
            _tab("/vote", "vote", here == 13),
            _tab("/open", "markets", here == 7),
            _tab("/assets", "assets", here == 8),
            _tab("/services.json", "json", here == 6),
            "</nav>"
        );
    }

    function _tab(string memory href, string memory label, bool on)
        private pure returns (string memory)
    {
        return string.concat(
            "<a", on ? " class=on" : "", " href=\"", href, "\">", label, "</a>"
        );
    }

    /*═══════════════════ the footer, and the client ═══════════════════*/

    function foot(address premises, uint256 chainId) external pure returns (string memory) {
        return string.concat(
            "<h2>about this page</h2>"
            "<p class=e>An ERC-5219 contract at <code>", LibNum.hexAddr(premises),
            "</code> on chain <code>", chainId.str(),
            "</code>, reached over <code>web3://</code> with no DNS and no server. "
            "It holds none of the artwork: every token renders identically whether "
            "this contract exists, is abandoned, or is replaced. Every transaction "
            "offered here is built on chain &mdash; the selector in each "
            "<code>data-call</code> came out of a contract, not out of this page's "
            "JavaScript, and you can check it against the ABI yourself.</p>"
            "<div id=s></div>"
        );
    }

}

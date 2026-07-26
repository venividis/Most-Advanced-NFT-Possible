// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Section} from "./lib/Types.sol";

interface IIpseityIndex {
    function totalSupply() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
    function ownerOf(uint256 id) external view returns (address);
    function tokenURI(uint256 id) external view returns (string memory);
    function sectionOf(uint256 id) external view returns (uint256);
    function kernelStatus(uint256 id) external view returns (uint8);
    function locked(uint256 id) external view returns (bool);
    function account(uint256 id) external view returns (address);
    function grip(uint256 id) external view returns (address);
}

/*═══════════════════════════════════════════════════════════════════════════

  THE FRONT DOOR

  Every token in this collection is already a website. `tokenURI` returns a
  complete WebGL2 application with a keccak, an ABI coder and a wallet
  client inside it, held in contract code and handed back as a `data:` URI.
  Nothing is fetched. That part was never the problem.

  What was missing is somewhere to send a person who does not own one yet.
  A front door. This is that, and it is deliberately a different kind of
  thing from the artwork.

  ── the line this contract will not cross ──

  **Premises never serves the artwork.** It serves a document that *names*
  the artwork, by emitting the token's own `data:` URI, produced on chain by
  the same renderer the token uses. The bytes a viewer executes still come
  out of `tokenURI`, exactly as they would if this contract had never been
  deployed.

  That is the whole design constraint, and it is what makes the front door
  safe to have. If this contract is never deployed, every token renders. If
  it is deployed and then abandoned, every token renders. If it is deployed
  and then compromised, an attacker controls a page that links to the
  artwork — and cannot change one byte of the artwork, because they do not
  hold the bytes.

  Compare the arrangement this replaces in most collections: a hostname
  compiled into immutable bytecode, one DNS record for the whole supply,
  fetched bytes going straight into `new Function`. That is a supply-chain
  attack with a single target, and it is fatal to a claim of permanence. The
  answer is not a better server. The answer is that the work does not need
  one, and the index is allowed to be ordinary because nothing depends on
  it.

  ── ERC-5219: the contract is the origin ──

  `request(resource, params)` is an HTTP handler written in Solidity. It
  returns a status code, a body and headers, and an ERC-4804 / ERC-6860
  client reaches it over `web3://` with no DNS involved:

      web3://<this address>/                  the index
      web3://<this address>/token/42          one token
      web3://<this address>/token/42/raw      that token's tokenURI, plain

  Point an ENS `contenthash` at it and a name resolves natively in any
  web3://-aware client. An HTTP gateway is a convenience for everyone else,
  and a convenience is exactly what it should be: when the gateway is down
  the tokens are unaffected, which is the property the hostname-in-bytecode
  arrangement can never have.

  ── what is deliberately not here ──

  No chunked file store, no SHA-256 integrity manifest, no multi-transport
  loader, no compression codec. Those solve the problem of shipping a large
  application over a wire and proving it arrived intact. This contract ships
  a few kilobytes of index and proves nothing, because it asserts nothing:
  every number on the page is one an ERC-5219 client can re-read from the
  hub itself, and the artwork it points at carries its own guarantee.

═══════════════════════════════════════════════════════════════════════════*/
contract Premises {
    using LibNum for uint256;
    using Section for uint256;

    IIpseityIndex public immutable HUB;

    struct KeyValue { string key; string value; }

    /// @dev Long, because the answer is the same until the chain changes and
    ///      a client that caches it is a client that is not making requests.
    string private constant CACHE = "public, max-age=60";

    constructor(IIpseityIndex hub) {
        HUB = hub;
    }

    /*═══════════════════ ERC-5219 ═══════════════════*/

    /// @notice The origin. Routing, status codes and content types, decided
    ///         on chain.
    function request(string[] memory resource, KeyValue[] memory params)
        external view
        returns (uint16 statusCode, string memory body, KeyValue[] memory headers)
    {
        params;   // no query parameters are read; the path is the whole API

        if (resource.length == 0) {
            return (200, _index(), _headers("text/html; charset=utf-8"));
        }

        if (_eq(resource[0], "token")) {
            if (resource.length < 2) return _notFound();

            (bool ok, uint256 id) = _toUint(resource[1]);
            if (!ok) return _notFound();
            if (!_exists(id)) return _notFound();

            // /token/<id>/raw — the token's own URI, unwrapped, for a client
            // that would rather have the artifact than a page about it
            if (resource.length >= 3 && _eq(resource[2], "raw")) {
                return (200, HUB.tokenURI(id), _headers("text/plain; charset=utf-8"));
            }
            return (200, _token(id), _headers("text/html; charset=utf-8"));
        }

        return _notFound();
    }

    function _notFound() private pure returns (uint16, string memory, KeyValue[] memory) {
        return (
            404,
            "<!doctype html><meta charset=utf-8><title>no such section</title>"
            "<body style=\"background:#07080c;color:#8b95ad;font:14px ui-monospace,monospace;padding:3rem\">"
            "<p>There is no token at that address of the collection.</p>"
            "<p><a style=\"color:#7fd4ff\" href=\"/\">back to the index</a></p>",
            _headers("text/html; charset=utf-8")
        );
    }

    function _headers(string memory contentType) private pure returns (KeyValue[] memory h) {
        h = new KeyValue[](2);
        h[0] = KeyValue("Content-Type", contentType);
        h[1] = KeyValue("Cache-Control", CACHE);
    }

    /*═══════════════════ the pages ═══════════════════*/

    function _index() private view returns (string memory) {
        uint256 supply = HUB.totalSupply();
        uint256 ceiling = HUB.MAX_SUPPLY();

        return string.concat(
            _head("IPSEITY"),
            "<h1>IPSEITY</h1>"
            "<p class=e>ipseity, n. &mdash; the property of being oneself; selfhood as "
            "distinct from any of its appearances.</p>"
            "<p>A four-dimensional solid, and the instrument for turning it, are the same "
            "token. What a holder sees is a three-dimensional section of a 4-polytope: the "
            "solid is never on screen, only the 3-space that currently cuts through it.</p>"
            "<p>Every token below returns its own control surface from <code>tokenURI</code> "
            "&mdash; a WebGL2 engine, a keccak-256, an ABI coder and a wallet client, held in "
            "this chain's state as contract bytecode. Nothing is fetched, including by this "
            "page: what it hands you is the token's own bytes.</p>",
            "<dl><dt>issued</dt><dd>", supply.str(), " of ", ceiling.str(), "</dd>",
            "<dt>collection</dt><dd><code>", LibNum.hexAddr(address(HUB)), "</code></dd>",
            "<dt>this index</dt><dd><code>", LibNum.hexAddr(address(this)), "</code></dd></dl>",
            _roll(supply),
            _foot()
        );
    }

    /// @dev The most recent twelve. An index that tries to list four thousand
    ///      tokens in one `eth_call` is an index that stops answering — the
    ///      same quadratic wall that eventually breaks any contract which
    ///      assembles its whole output on every request.
    function _roll(uint256 supply) private view returns (string memory out) {
        if (supply == 0) return "<p class=e>None issued yet.</p>";
        uint256 from = supply > 12 ? supply - 11 : 1;
        out = "<h2>most recent</h2><ul class=r>";
        for (uint256 id = supply; id >= from; --id) {
            uint256 w = HUB.sectionOf(id);
            out = string.concat(
                out,
                "<li><a href=\"/token/", id.str(), "\">#", id.str(), "</a> ",
                "<span class=m>", _form(w.form()), "</span></li>"
            );
            if (id == 1) break;
        }
        return string.concat(out, "</ul>");
    }

    function _token(uint256 id) private view returns (string memory) {
        uint256 w = HUB.sectionOf(id);
        return string.concat(
            _head(string.concat("IPSEITY #", id.str())),
            "<p><a class=b href=\"/\">&larr; index</a></p>",
            "<h1>IPSEITY #", id.str(), "</h1>",
            "<dl><dt>solid</dt><dd>", _form(w.form()), "</dd>",
            "<dt>held by</dt><dd><code>", LibNum.hexAddr(HUB.ownerOf(id)), "</code></dd>",
            "<dt>bound</dt><dd>", HUB.locked(id) ? "yes" : "no", "</dd>",
            "<dt>kernel</dt><dd>", _kernel(HUB.kernelStatus(id)), "</dd>",
            "<dt>reach</dt><dd><code>", LibNum.hexAddr(HUB.account(id)), "</code></dd>",
            "<dt>grip</dt><dd><code>", LibNum.hexAddr(HUB.grip(id)), "</code></dd>",
            "<dt>section word</dt><dd><code>", w.str(), "</code></dd></dl>",
            _frame(id),
            _foot()
        );
    }

    /// @dev The one line that matters. The `src` is the token's own data URI,
    ///      read from the hub at request time — so the bytes a viewer runs
    ///      come from `tokenURI` and not from this contract's opinion of it.
    ///      Nothing is fetched over a network to fill this frame.
    function _frame(uint256 id) private view returns (string memory) {
        return string.concat(
            "<h2>the instrument</h2>"
            "<iframe title=\"IPSEITY #", id.str(), "\" src=\"", HUB.tokenURI(id), "\"></iframe>",
            "<p class=e>Those bytes came out of <code>tokenURI(", id.str(), ")</code>. This page "
            "did not fetch them from anywhere and could not have altered them if it wanted to. "
            "<a href=\"/token/", id.str(), "/raw\">read the URI itself</a>.</p>"
        );
    }

    /*═══════════════════ chrome ═══════════════════*/

    function _head(string memory title) private pure returns (string memory) {
        return string.concat(
            "<!doctype html><meta charset=utf-8>"
            "<meta name=viewport content=\"width=device-width,initial-scale=1\">"
            "<title>", title, "</title><style>"
            ":root{color-scheme:dark}"
            "body{background:#07080c;color:#c9d3e6;font:15px/1.65 ui-sans-serif,system-ui,sans-serif;"
            "max-width:60rem;margin:0 auto;padding:3rem 1.5rem 6rem}"
            "h1{font-weight:500;letter-spacing:.22em;font-size:1.5rem;margin:0 0 .3rem}"
            "h2{font-weight:500;letter-spacing:.14em;font-size:.8rem;text-transform:uppercase;"
            "color:#8b95ad;margin:2.6rem 0 .8rem}"
            "a{color:#7fd4ff}.b{text-decoration:none;color:#8b95ad}"
            ".e{color:#8b95ad;font-size:.92rem}"
            "code{font:12.5px ui-monospace,monospace;color:#9fb0cc;overflow-wrap:anywhere}"
            "dl{display:grid;grid-template-columns:8.5rem 1fr;gap:.35rem 1rem;margin:1.6rem 0}"
            "dt{color:#6c7689;font-size:.82rem;letter-spacing:.1em;text-transform:uppercase}"
            "dd{margin:0}"
            "ul.r{list-style:none;padding:0;display:grid;"
            "grid-template-columns:repeat(auto-fill,minmax(11rem,1fr));gap:.5rem}"
            "ul.r li{border:1px solid #1a2030;border-radius:.4rem;padding:.6rem .8rem}"
            ".m{color:#6c7689;font-size:.8rem;display:block}"
            "iframe{width:100%;aspect-ratio:16/10;border:1px solid #1a2030;border-radius:.5rem;"
            "background:#000}"
            "</style>"
        );
    }

    function _foot() private view returns (string memory) {
        return string.concat(
            "<h2>about this page</h2>"
            "<p class=e>This index is an ERC-5219 contract at <code>",
            LibNum.hexAddr(address(this)),
            "</code>, reached over <code>web3://</code> with no DNS and no server. It is "
            "convenience, not infrastructure: it holds none of the artwork, and every token "
            "renders identically whether this contract exists, is abandoned, or is replaced. "
            "The bytes are in the collection.</p>"
        );
    }

    /*═══════════════════ small things ═══════════════════*/

    function _form(uint8 f) private pure returns (string memory) {
        if (f == 0) return "Tesseract";
        if (f == 1) return "Hexadecachoron";
        if (f == 2) return "Icositetrachoron";
        if (f == 3) return "Duocylinder";
        if (f == 4) return "Clifford torus";
        if (f == 5) return "Tiger";
        if (f == 6) return "Ditorus";
        return "Quaternion Julia";
    }

    function _kernel(uint8 k) private pure returns (string memory) {
        if (k == 0) return "none";
        if (k == 1) return "current";
        return "stale &mdash; sealed to a previous holder";
    }

    function _exists(uint256 id) private view returns (bool) {
        (bool ok, bytes memory out) =
            address(HUB).staticcall(abi.encodeWithSelector(IIpseityIndex.ownerOf.selector, id));
        return ok && out.length >= 32 && abi.decode(out, (address)) != address(0);
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /// @dev A path segment is text. Anything that is not a plain decimal
    ///      number is not a token id, and saying so is a 404 rather than a
    ///      revert — a client asking for nonsense deserves an answer.
    function _toUint(string memory s) private pure returns (bool ok, uint256 v) {
        bytes memory b = bytes(s);
        if (b.length == 0 || b.length > 10) return (false, 0);
        for (uint256 i; i < b.length; ++i) {
            uint8 ch = uint8(b[i]);
            if (ch < 0x30 || ch > 0x39) return (false, 0);
            v = v * 10 + (ch - 0x30);
        }
        return (true, v);
    }
}

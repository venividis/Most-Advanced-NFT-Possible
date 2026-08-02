// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHub, IRendererDoc, ISigilDraw, IChrome} from "./interfaces/Site.sol";
import {LibNum} from "./lib/LibNum.sol";
import {TokenView} from "./lib/Types.sol";

interface IPageToken {
    function index() external view returns (string memory);
    function token(uint256 id) external view returns (string memory);
    function faces(uint256 id) external view returns (string memory);
}

interface IPageMarket {
    function market(uint256 id) external view returns (string memory);
    function open(uint256 page) external view returns (string memory);
}

interface IPageSwap {
    function swap() external view returns (string memory);
    function assets(uint256 page) external view returns (string memory);
}

interface IPagePools {
    function pools() external view returns (string memory);
    function limit() external view returns (string memory);
}

interface IPageExplore {
    function explore(address token) external view returns (string memory);
}

interface IPageCivic {
    function earn(address vault) external view returns (string memory);
    function vote() external view returns (string memory);
}

interface IPagePool {
    function pool(uint256 id) external view returns (string memory);
}

interface IPageServices {
    function rent(uint256 id) external view returns (string memory);
    function vault(uint256 id) external view returns (string memory);
}

interface IPageManifest {
    function token(uint256 id) external view returns (string memory);
    function index(uint256 page) external view returns (string memory);
}

/*═══════════════════════════════════════════════════════════════════════════

  THE FRONT DOOR

  Every token in this collection is already a website. `tokenURI` returns a
  complete WebGL2 application with a keccak, an ABI coder and a wallet
  client inside it, held in contract code and handed back as a `data:` URI.
  Nothing is fetched. That part was never the problem.

  What was missing is a place a stranger can stand. Not to look at the
  artwork — the artwork can be looked at without help — but to see that each
  of these objects runs an exchange, rents itself out, holds a vault nobody
  can empty, and draws any four-dimensional form it is handed, and then to
  actually use one of those without asking anybody's permission.

  ── the line this contract will not cross ──

  **Premises never serves the artwork through a page contract.** `/raw` and
  `/live` are handled here, in this file, from the hub and the renderer
  directly. Every other route delegates to a page contract, and every page
  contract is an immutable constructor argument.

  That split is the whole safety argument. The pages are the mutable-ish
  part of the system in the only sense that matters — replacing them means
  deploying a new Premises and pointing a name at it — and they are exactly
  the routes where being wrong is cosmetic. The two routes where being wrong
  would mean serving someone else's bytes as the artwork do not touch them.

  Even so, the honest claim is narrow: a compromised front door controls
  pages that link to and frame the artwork, and cannot alter one byte of the
  artwork itself, because it does not hold those bytes. If this contract is
  never deployed, every token renders. If it is abandoned, every token
  renders. If it is replaced, every token renders identically.

  ── ERC-5219: the contract is the origin ──

  `request(resource, params)` is an HTTP handler written in Solidity. An
  ERC-4804 / ERC-6860 client reaches it over `web3://` with no DNS:

      /                          the collection, and what it offers
      /swap                      any pair of ERC-20s, on Uniswap v3
      /pools                     liquidity, at a range you choose
      /limit                     a range order: an order without a server
      /explore  /explore/<token>  what a token trades at, and its own chart
      /earn  /earn/<vault>        an ERC-4626 vault, verified before it is used
      /vote                       Uniswap governance, from the governor itself
      /open  /open/<n>           every market that exists, from the pool's own list
      /assets  /assets/<n>        every asset any of those markets trades
      /services.json  /services.json/<n>    the same, for a program
      /token/<id>                one token's counter
      /token/<id>/live           the instrument, on a real origin
      /token/<id>/raw            that token's tokenURI, plain
      /token/<id>/face/<n>       one ERC-7160 face, plain
      /token/<id>/sigil.svg      the still, as an image
      /token/<id>/faces          what the three faces are
      /token/<id>/market         the swap card
      /token/<id>/pool           the holder's side: inventory, fee, bond, curve
      /token/<id>/rent           lease the instrument by the day
      /token/<id>/vault          the two hands, give, draw, verify
      /token/<id>/services.json  everything above, machine-readable

  Point an ENS `contenthash` here and a name resolves natively in any
  web3://-aware client. An HTTP gateway is a convenience for everyone else,
  and a convenience is exactly what it should be: when the gateway is down
  the tokens are unaffected, which is the property a hostname compiled into
  bytecode can never have.

═══════════════════════════════════════════════════════════════════════════*/
contract Premises {
    IHub          public immutable HUB;
    IChrome       public immutable CHROME;
    IPageToken    public immutable P_TOKEN;
    IPageMarket   public immutable P_MARKET;
    IPagePool     public immutable P_POOL;
    IPageServices public immutable P_SERVICES;
    IPageManifest public immutable P_MANIFEST;
    IPageSwap     public immutable P_SWAP;
    IPagePools    public immutable P_POOLS;
    IPageCivic    public immutable P_CIVIC;
    IPageExplore  public immutable P_EXPLORE;

    struct KeyValue { string key; string value; }

    string private constant HTML = "text/html; charset=utf-8";
    string private constant TEXT = "text/plain; charset=utf-8";
    string private constant JSON = "application/json";
    string private constant SVG  = "image/svg+xml";

    /// @dev Short, because half of what this site reports is a live balance
    ///      and a cached market is a market that quotes last minute's price.
    string private constant CACHE = "public, max-age=15";

    constructor(
        IHub hub,
        IChrome chrome,
        IPageToken pToken,
        IPageMarket pMarket,
        IPagePool pPool,
        IPageServices pServices,
        IPageManifest pManifest,
        IPageSwap pSwap,
        IPagePools pPools,
        IPageCivic pCivic,
        IPageExplore pExplore
    ) {
        HUB = hub;
        CHROME = chrome;
        P_TOKEN = pToken;
        P_MARKET = pMarket;
        P_POOL = pPool;
        P_SERVICES = pServices;
        P_MANIFEST = pManifest;
        P_SWAP = pSwap;
        P_POOLS = pPools;
        P_CIVIC = pCivic;
        P_EXPLORE = pExplore;
    }

    /*═══════════════════ ERC-6860 ═══════════════════*/

    /// @notice Declares that this contract answers in ERC-5219 mode.
    /// @dev    Not optional, and its absence is silent. ERC-6860 resolves
    ///         the mode by calling this and treating a revert as "auto" —
    ///         and in auto mode `web3://<addr>/` is an empty call to a
    ///         contract with no fallback, and `web3://<addr>/token/1` is a
    ///         call to a method named `token` taking a uint256. Neither
    ///         exists here, so both revert.
    ///
    ///         Without these four bytes the whole claim in the header —
    ///         that a name pointed here resolves natively in any
    ///         web3://-aware client — is false, and the site is reachable
    ///         only from a gateway that happens to hard-code ERC-5219 for
    ///         this address. Which is a server, which is the thing this
    ///         contract exists not to need.
    function resolveMode() external pure returns (bytes32) {
        return "5219";
    }

    /*═══════════════════ ERC-5219 ═══════════════════*/

    function request(string[] memory resource, KeyValue[] memory params)
        external view
        returns (uint16 statusCode, string memory body, KeyValue[] memory headers)
    {
        params;   // no query parameters are read; the path is the whole API

        /*  One resource, one URL. A trailing slash arrives as an empty last
            segment, so `/token/1/` is dropped to `/token/1` rather than
            404ing while `/token/1` succeeds; and past that, a leaf handler
            that ignores whatever follows it would serve the same page at
            unboundedly many addresses. Every response carries a
            Cache-Control, so "the same page at any URL you like" is an
            invitation to fill a gateway's cache with distinct entries for
            one document until the real ones are evicted.                 */
        uint256 n = resource.length;
        if (n > 0 && bytes(resource[n - 1]).length == 0) --n;

        if (n == 0) {
            return (200, P_TOKEN.index(), _headers(HTML));
        }

        /*───── collection-wide ─────*/

        if (_eq(resource[0], "open")) {
            if (n > 2) return _notFound();
            uint256 page;
            if (n == 2) {
                (bool ok, uint256 v) = _toUint(resource[1]);
                if (!ok) return _notFound();
                page = v;
            }
            return (200, P_MARKET.open(page), _headers(HTML));
        }

        if (_eq(resource[0], "assets")) {
            if (n > 2) return _notFound();
            uint256 page;
            if (n == 2) {
                (bool ok, uint256 v) = _toUint(resource[1]);
                if (!ok) return _notFound();
                page = v;
            }
            return (200, P_SWAP.assets(page), _headers(HTML));
        }

        /*───── the rest of the chain ─────*/

        if (_eq(resource[0], "swap")) {
            if (n != 1) return _notFound();
            return (200, P_SWAP.swap(), _headers(HTML));
        }

        if (_eq(resource[0], "pools")) {
            if (n != 1) return _notFound();
            return (200, P_POOLS.pools(), _headers(HTML));
        }

        /*  Governance is about the collection's chain, not about an address
            you name, so it takes no segment — and it is routed on its own
            rather than folded in with the two that do.

            It was folded in, and that was the exact failure the length
            gates above exist to prevent: `vote()` ignores its argument, so
            every one of 2^160 `/vote/<address>` URLs answered 200 with a
            byte-identical document. Every response here carries a
            Cache-Control, so "the same page at any address you like" is an
            invitation to fill a gateway's cache with distinct entries for
            one document until the real ones are evicted.                 */
        if (_eq(resource[0], "vote")) {
            if (n != 1) return _notFound();
            return (200, P_CIVIC.vote(), _headers(HTML));
        }

        /*  Two routes that take an optional contract address. With none
            they are an index; with one they are a page about that address,
            rendered here rather than fetched by a script — which is why
            `/explore/<token>` works in a client with JavaScript switched
            off entirely.                                                 */
        if (_eq(resource[0], "explore") || _eq(resource[0], "earn")) {
            if (n > 2) return _notFound();
            address subject;
            if (n == 2) {
                (bool okA, address v, bool canon) = _toAddr(resource[1]);
                if (!okA) return _notFound();
                /*  One resource, one URL — so one spelling. An address
                    pasted from a block explorer is EIP-55 mixed case and is
                    a perfectly good address; it is just not this document's
                    address. Sent there rather than refused.              */
                if (!canon) {
                    return _moved(string.concat("/", resource[0], "/", LibNum.hexAddr(v)));
                }
                subject = v;
            }
            if (_eq(resource[0], "explore")) {
                return (200, P_EXPLORE.explore(subject), _headers(HTML));
            }
            return (200, P_CIVIC.earn(subject), _headers(HTML));
        }

        if (_eq(resource[0], "limit")) {
            if (n != 1) return _notFound();
            return (200, P_POOLS.limit(), _headers(HTML));
        }

        if (_eq(resource[0], "services.json")) {
            if (n > 2) return _notFound();
            uint256 page;
            if (n == 2) {
                (bool ok, uint256 v) = _toUint(resource[1]);
                if (!ok) return _notFound();
                page = v;
            }
            return (200, P_MANIFEST.index(page), _headers(JSON));
        }

        /*───── one token ─────*/

        if (!_eq(resource[0], "token")) return _notFound();
        if (n < 2) return _notFound();

        (bool valid, uint256 id) = _toUint(resource[1]);
        if (!valid || !_exists(id)) return _notFound();

        if (n == 2) return (200, P_TOKEN.token(id), _headers(HTML));

        string memory leaf = resource[2];

        /*  `face` is the only route that takes a fourth segment, and it
            *requires* one — the gate has to be an exact length per leaf
            rather than "three, or four if it is face", because the latter
            lets `/token/1/face` through to read `resource[3]` and panic.
            A 404 and an out-of-bounds panic look nothing alike to a
            client: one is an answer, the other is a broken origin.     */
        if (_eq(leaf, "face")) {
            if (n != 4) return _notFound();
        } else if (n != 3) {
            return _notFound();
        }

        /*  The two routes that hand over the artwork itself. Answered here,
            from the hub and the renderer, so that no page contract sits on
            the path between a viewer and the bytes they came for.       */

        if (_eq(leaf, "raw")) {
            return (200, HUB.tokenURI(id), _headers(TEXT));
        }

        /*  /live exists for one specific reason and it is not aesthetics. A
            `data:` document gets an opaque origin, and wallet extensions do
            not inject into one — so an instrument embedded in a frame
            renders perfectly and cannot connect to anything. It can be
            looked at and not used. Served here it has a real origin under
            `web3://`, EIP-6963 discovery works, and the instruments do what
            they were built to do.

            The bytes are `Renderer.document(...)` — exactly what `tokenURI`
            base64s, one step earlier, read from the same renderer the token
            itself uses. Nothing is stored here.                          */
        if (_eq(leaf, "live")) {
            return (
                200,
                string(IRendererDoc(HUB.renderer()).document(HUB.viewOf(id))),
                _headers(HTML)
            );
        }

        /*  The still, as an image rather than as a page.

            The counter page used to embed the whole instrument in an
            iframe, and measuring it said what prose had not: 21M gas of
            `eth_call` for the shopfront, against 0.2M for every other
            service page — to show a preview that a viewer cannot use,
            because a `data:` frame has an opaque origin and no wallet will
            inject into it. Strictly worse on both axes than the link
            beside it.

            An asset is its own request. The page costs what a page costs,
            the picture costs what a picture costs, and a browser that
            wants both makes two calls instead of one that no cautious node
            will run.                                                     */
        if (_eq(leaf, "sigil.svg")) {
            address sig = IRendererDoc(HUB.renderer()).sigil();
            if (sig == address(0)) return _notFound();
            TokenView memory v = HUB.viewOf(id);
            return (
                200,
                string(ISigilDraw(sig).svg(v.id, v.word, v.seed, v.strata)),
                _headers(SVG)
            );
        }

        /*  One ERC-7160 face, unwrapped. Also answered here: a face is the
            artwork too, just a different one.                            */
        if (_eq(leaf, "face")) {
            (bool okf, uint256 face) = _toUint(resource[3]);
            if (!okf) return _notFound();
            /*  `tokenURIAt` reverts BadIndex past the last face, and a
                revert is not an answer. Asking for face 9 of 3 is the same
                kind of mistake as asking for token 9999, and deserves the
                same reply.                                              */
            if (face >= IRendererDoc(HUB.renderer()).facetCount()) return _notFound();
            return (200, HUB.tokenURIAt(id, face), _headers(TEXT));
        }

        /*───── the counter ─────*/

        if (_eq(leaf, "faces"))         return (200, P_TOKEN.faces(id),      _headers(HTML));
        if (_eq(leaf, "market"))        return (200, P_MARKET.market(id),    _headers(HTML));
        if (_eq(leaf, "pool"))          return (200, P_POOL.pool(id),        _headers(HTML));
        if (_eq(leaf, "rent"))          return (200, P_SERVICES.rent(id),    _headers(HTML));
        if (_eq(leaf, "vault"))         return (200, P_SERVICES.vault(id),   _headers(HTML));
        if (_eq(leaf, "services.json")) return (200, P_MANIFEST.token(id),   _headers(JSON));

        return _notFound();
    }

    /*═══════════════════ answers that are not pages ═══════════════════*/

    /// @dev A 404 rather than a revert. A client asking for nonsense
    ///      deserves an answer, and the path is never echoed back — the one
    ///      thing on this page an attacker could have chosen is the one
    ///      thing that would be rendered.
    function _notFound() private pure returns (uint16, string memory, KeyValue[] memory) {
        return (
            404,
            "<!doctype html><meta charset=utf-8><title>no such section</title>"
            "<body style=\"background:#07080c;color:#8b95ad;font:14px ui-monospace,monospace;padding:3rem\">"
            "<p>There is nothing at that address of the collection.</p>"
            "<p><a style=\"color:#7fd4ff\" href=\"/\">back to the index</a></p>",
            _headers(HTML)
        );
    }

    /// @dev A 301 to the canonical spelling. Cached hard, because where a
    ///      resource lives does not change and a gateway that re-asked on
    ///      every request would have turned a de-duplication into a second
    ///      round trip.
    function _moved(string memory to)
        private pure returns (uint16, string memory, KeyValue[] memory)
    {
        KeyValue[] memory h = new KeyValue[](3);
        h[0] = KeyValue("Content-Type", HTML);
        h[1] = KeyValue("Cache-Control", "public, max-age=86400");
        h[2] = KeyValue("Location", to);
        return (
            301,
            string.concat(
                "<!doctype html><meta charset=utf-8><title>moved</title>"
                "<body style=\"background:#07080c;color:#8b95ad;"
                "font:14px ui-monospace,monospace;padding:3rem\">"
                "<p>That is the right address, written a different way.</p>"
                "<p><a style=\"color:#7fd4ff\" href=\"", to, "\">", to, "</a></p>"),
            h
        );
    }

    function _headers(string memory contentType) private pure returns (KeyValue[] memory h) {
        h = new KeyValue[](2);
        h[0] = KeyValue("Content-Type", contentType);
        h[1] = KeyValue("Cache-Control", CACHE);
    }

    /*═══════════════════ small things ═══════════════════*/

    function _exists(uint256 id) private view returns (bool) {
        (bool ok, bytes memory out) =
            address(HUB).staticcall(abi.encodeWithSelector(IHub.ownerOf.selector, id));
        return ok && out.length >= 32 && abi.decode(out, (address)) != address(0);
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /*  A path segment that names a contract.

        `/explore/0xC02aaA39...` renders a whole token page — its pools, its
        depth at each fee tier, and a price chart out of the pool's own
        oracle — with no JavaScript involved at all. That is only possible
        if an address can be a resource, so it is parsed here with the same
        strictness the numeric parser has: exactly forty hex digits after
        `0x`, one canonical spelling, and anything else is a 404 rather than
        a revert.

        One spelling, for the same reason `_toUint` refuses a leading zero:
        the file above argues that one resource must have one URL because
        every response carries a Cache-Control, and `/explore/0xABC…` and
        `/explore/0xabc…` are the same resource. Mixed case is *accepted* —
        refusing an address pasted from a block explorer would be refusing
        the common case — but it is not a second address: the canonical form
        is lower case with a lower-case `0x`, and anything else is redirected
        there rather than served in place.

        A checksum is deliberately not enforced. It would catch a mistyped
        address, which is worth something, but this parser is mostly reached
        by links the page itself wrote, and a page that 404s a valid address
        because its capitalisation is unfashionable is worse. The page prints
        back the address it read, which is the check that actually helps. */
    /// @return ok    whether it is an address at all
    /// @return a     the address
    /// @return canon whether it was written the one way this site writes it:
    ///               lower-case `0x`, lower-case digits. Anything else is a
    ///               different URL for the same document, and gets a 301.
    function _toAddr(string memory s)
        private pure returns (bool ok, address a, bool canon)
    {
        bytes memory b = bytes(s);
        if (b.length != 42 || b[0] != "0") return (false, address(0), false);
        if (b[1] != "x" && b[1] != "X") return (false, address(0), false);
        canon = b[1] == "x";
        uint256 v;
        for (uint256 i = 2; i < 42; ++i) {
            uint8 ch = uint8(b[i]);
            uint256 d;
            if (ch >= 0x30 && ch <= 0x39) d = ch - 0x30;
            else if (ch >= 0x61 && ch <= 0x66) d = ch - 0x61 + 10;
            else if (ch >= 0x41 && ch <= 0x46) { d = ch - 0x41 + 10; canon = false; }
            else return (false, address(0), false);
            v = v * 16 + d;
        }
        return (true, address(uint160(v)), canon);
    }

    /// @dev A path segment is text. Anything that is not a plain decimal
    ///      number is not an index, and saying so is a 404 rather than a
    ///      revert.
    ///
    ///      A leading zero is refused, so `/token/0000000001` is not a
    ///      second address for token 1. The pager links and the manifest's
    ///      `next` both assume there is one canonical URL per resource,
    ///      and a caching layer in front of this contract assumes it much
    ///      more strongly than they do.
    function _toUint(string memory s) private pure returns (bool ok, uint256 v) {
        bytes memory b = bytes(s);
        if (b.length == 0 || b.length > 10) return (false, 0);
        if (b.length > 1 && b[0] == "0") return (false, 0);
        for (uint256 i; i < b.length; ++i) {
            uint8 ch = uint8(b[i]);
            if (ch < 0x30 || ch > 0x39) return (false, 0);
            v = v * 10 + (ch - 0x30);
        }
        return (true, v);
    }
}

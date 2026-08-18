// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Web} from "./lib/Web.sol";
import {IChrome} from "./interfaces/Site.sol";

interface IFoundryRead {
    function count() external view returns (uint256);
    function launchAt(uint256 i)
        external view
        returns (address coin, uint256 by, uint64 at, uint8 decimals_, uint256 supply);
}

/*───────────────────────────────────────────────────────────────────────────
  PageMint — the coins, with nothing up their sleeve

  Every coin the foundry pours is fixed-supply, minted once, entirely to
  the launcher — no owner, no mint, no pause, no upgrade. This page is the
  ledger of pours: the contract address is the headline, because the
  address is the product — copy it, watch it in a wallet, verify there is
  no power hiding in it. Pouring happens in the terminal:
  `coin <name> <sym> <decimals> <supply>`.
───────────────────────────────────────────────────────────────────────────*/
contract PageMint {
    using LibNum for uint256;

    IChrome      public immutable CHROME;
    IFoundryRead public immutable FOUNDRY;

    constructor(IChrome chrome, IFoundryRead foundry) {
        CHROME = chrome; FOUNDRY = foundry;
    }

    function coins() external view returns (string memory) {
        uint256 n = FOUNDRY.count();
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 coins"),
            CHROME.navTop(23),
            "<h1>coins</h1>"
            "<p class=e><b>", n.str(), "</b> poured. Each is the same shape: a fixed "
            "supply, minted once, entirely to whoever poured it &mdash; no owner, no "
            "mint function, no pause, no blacklist, no upgrade path. The address is "
            "the whole product. Pour one from the <a href=\"/terminal\">terminal</a>: "
            "<code>coin &lt;name&gt; &lt;sym&gt; &lt;decimals&gt; &lt;supply&gt;</code>.</p>",
            _list(n),
            "<div id=s></div>",
            _js(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    function _list(uint256 n) private view returns (string memory out) {
        if (n == 0) return "<p class=e>Nothing poured yet.</p>";
        uint256 from = n > 16 ? n - 16 : 0;
        for (uint256 i = n; i > from; --i) out = string.concat(out, _one(i - 1));
    }

    function _one(uint256 i) private view returns (string memory) {
        (address coin, uint256 by,, uint8 dec, uint256 supply) = FOUNDRY.launchAt(i);
        string memory a = LibNum.hexAddr(coin);
        return string.concat(
            "<div class=card><h3>", Web.esc(Web.nameOf(coin)), " \xc2\xb7 ",
            Web.esc(Web.symbolOf(coin)), "</h3>",
            "<p><code class=coinaddr>", a, "</code></p>",
            "<p class=e>supply ", Web.amount(supply, dec, 4),
            " \xc2\xb7 ", uint256(dec).str(), " decimals \xc2\xb7 poured by "
            "<a href=\"/token/", by.str(), "\">token #", by.str(), "</a></p>",
            "<button class=copy data-a=\"", a, "\">copy address</button>",
            "<button class=watch data-a=\"", a, "\" data-s=\"", Web.esc(Web.symbolOf(coin)),
            "\" data-d=\"", uint256(dec).str(), "\">add to wallet</button>",
            "</div>"
        );
    }

    /// @dev Two conveniences, both against the wallet the visitor chose:
    ///      the clipboard, and EIP-747 wallet_watchAsset.
    function _js() private pure returns (string memory) {
        return
            "<script>(()=>{const I=window.IP;"
            "document.querySelectorAll('.copy').forEach(b=>b.addEventListener('click',"
            "async()=>{try{await navigator.clipboard.writeText(b.dataset.a);"
            "I.say('copied '+b.dataset.a,'ok')}catch(e){I.say('clipboard refused \\u2014 "
            "select the address by hand','no')}}));"
            "document.querySelectorAll('.watch').forEach(b=>b.addEventListener('click',"
            "async()=>{try{const p=I.pv();if(!p)throw new Error('no wallet');"
            "await p.request({method:'wallet_watchAsset',params:{type:'ERC20',"
            "options:{address:b.dataset.a,symbol:b.dataset.s,"
            "decimals:Number(b.dataset.d)}}});I.say('watching','ok')}"
            "catch(e){I.say(String(e&&e.message||e),'no')}}))})()</script>";
    }
}

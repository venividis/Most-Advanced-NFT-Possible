// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChrome} from "./interfaces/Site.sol";

/*───────────────────────────────────────────────────────────────────────────
  PageCharts — the one tab that leaves the chain, and says so

  Everything else on this site is served by the contract and read from the
  chain. This page embeds GeckoTerminal — a third party, reached by YOUR
  browser, seeing YOUR requests — because live candles for the wider market
  are a thing people want and a thing no view function can honestly
  provide. The trade is stated instead of hidden; the collection's own
  markets chart themselves on their token pages, from the pool's own
  numbers, fetching nothing.
───────────────────────────────────────────────────────────────────────────*/
contract PageCharts {
    IChrome public immutable CHROME;

    constructor(IChrome chrome) { CHROME = chrome; }

    function charts() external view returns (string memory) {
        return string.concat(
            CHROME.head("IPSEITY \xc2\xb7 charts"),
            CHROME.navTop(24),
            "<h1>charts</h1>"
            "<p class=e><b>This is the one page that talks to somebody's server.</b> "
            "The frame below is GeckoTerminal, loaded by your browser from their "
            "domain; nothing else on this site does that. Close the tab and the site "
            "has forgotten it exists.</p>"
            "<div class=set>"
            "<button id=pEth>ETH / USDC</button>"
            "<button id=pBtc>WBTC / ETH</button>"
            "<label for=gt>or paste a GeckoTerminal pool URL</label>"
            "<input id=gt placeholder=\"https://www.geckoterminal.com/eth/pools/0x\xe2\x80\xa6\" "
            "style=\"max-width:100%\">"
            "<button id=go2>load</button>"
            "</div>"
            "<div id=chart></div>"
            "<p class=e>The collection's own markets need none of this: each token "
            "page charts its pool from the contract's own numbers, fetching "
            "nothing.</p>"
            "<div id=s></div>",
            _js(),
            CHROME.foot(msg.sender, block.chainid)
        );
    }

    /// @dev The only URL that may enter the frame is one on GeckoTerminal's
    ///      own origin — anything else is refused, because an iframe src a
    ///      visitor can choose is otherwise an open redirect with a chart's
    ///      reputation.
    function _js() private pure returns (string memory) {
        return
            "<script>(()=>{const I=window.IP,$=I.$;"
            "const OK='https://www.geckoterminal.com/';"
            "const show=u=>{if(!String(u).startsWith(OK))"
            "{I.say('only geckoterminal.com URLs load here','no');return}"
            "const box=$('chart');box.textContent='';"
            "const f=document.createElement('iframe');"
            "f.src=u+(u.includes('?')?'&':'?')+'embed=1&info=0&swaps=1';"
            "f.setAttribute('title','GeckoTerminal');f.setAttribute('frameborder','0');"
            "f.className='gtframe';f.setAttribute('allow','clipboard-write');"
            "box.append(f);I.say('loaded \\u2014 served by geckoterminal.com','ok')};"
            "$('pEth').addEventListener('click',()=>show(OK+'eth/pools/"
            "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640'));"
            "$('pBtc').addEventListener('click',()=>show(OK+'eth/pools/"
            "0xcbcdf9626bc03e24f779434178a73a0b4bad62ed'));"
            "$('go2').addEventListener('click',()=>show(($('gt')||{}).value||''));"
            "})()</script>";
    }
}

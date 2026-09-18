// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Static launchpad markup split out solely to stay below EIP-170.
contract LaunchView {
    function liquidity() external pure returns (string memory) {
        return
            "<h2>4 &middot; the liquidity</h2>"
            "<div class=app><div class=hd><b>Mint the position</b></div>"
            "<label>lower tick <span class=m>must be on the spacing grid</span></label>"
            "<input id=ll placeholder=\"-887220\">"
            "<label>upper tick</label><input id=lu placeholder=\"887220\">"
            "<div class=two><div><label>maximum token 0</label>"
            "<input id=l0 placeholder=\"0\"></div><div><label>maximum token 1</label>"
            "<input id=l1 placeholder=\"0\"></div></div>"
            "<label>position owner and fee controller <span class=m>your wallet, the "
            "NFT Reach, or any address; this address controls liquidity and LP fees</span></label>"
            "<input id=lo placeholder=\"0x&hellip;\">"
            "<div class=two><div><label>deadline (minutes)</label><input id=ld value=\"20\"></div>"
            "<div><label>hook data <span class=m>hex</span></label><input id=lh value=\"0x\"></div></div>"
            "<div class=det id=lplan></div>"
            "<button id=lcheck>Build and inspect the position</button>"
            "<button id=lapprove>Approve both currencies</button>"
            "<button class=go id=lgo disabled>Mint liquidity position</button>"
            "<div id=s></div></div>"
            "<p class=e>The planner is read-only: it takes no assets and receives no "
            "approval. Solidity builds the canonical <code>MINT_POSITION + SETTLE_PAIR</code> "
            "action plan, then your wallet sends those bytes straight to Uniswap's v4 "
            "PositionManager. The position is an NFT; whoever you name above controls "
            "withdrawals and where its accrued LP fees go. Choosing somebody else gives "
            "them that power.</p>"
            "<p class=\"e w\"><b>Permissionless means permissionless.</b> These controls "
            "govern this official position only. Any holder can create another pool or "
            "position; neither the NFT owner nor this planner can globally control all "
            "liquidity or fees for the token.</p>"
            "<p class=e>ERC-20 funding uses Uniswap Permit2: each currency first approves "
            "Permit2, then grants this chain's PositionManager a bounded Permit2 allowance. "
            "Native currency needs neither approval and is sent as transaction value.</p>";
    }
}

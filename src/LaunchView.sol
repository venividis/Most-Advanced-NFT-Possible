// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";
import {Hook} from "./lib/Hook.sol";

/// @notice Static launchpad markup split out solely to stay below EIP-170.
contract LaunchView {
    using LibNum for uint256;

    function config(
        address kiln, address hub, address manager, address planner,
        address positions, address permit2, address stateView, bool v4, address wrapped
    ) external pure returns (string memory) {
        return string.concat(
            "<script type=\"application/json\" id=\"K\">{\"kiln\":\"", LibNum.hexAddr(kiln),
            "\",\"hub\":\"", LibNum.hexAddr(hub), "\",\"manager\":\"", LibNum.hexAddr(manager),
            "\",\"planner\":\"", LibNum.hexAddr(planner), "\",\"positionManager\":\"", LibNum.hexAddr(positions),
            "\",\"permit2\":\"", LibNum.hexAddr(permit2), "\",\"stateView\":\"", LibNum.hexAddr(stateView),
            "\",\"v4\":", v4 ? "true" : "false", ",\"wrapped\":\"", LibNum.hexAddr(wrapped),
            "\",\"dynamicFee\":", uint256(Hook.DYNAMIC_FEE).str(), ",\"maxFee\":", uint256(Hook.MAX_FEE).str(),
            ",\"sel\":{\"launch\":\"", _sel("launch(uint256,string,string,uint8,uint256,bytes32)"),
            "\",\"coinAt\":\"", _sel("coinAt(address,string,string,uint8,uint256,bytes32)"),
            "\",\"mine\":\"", _sel("mine(bytes32,uint16,uint256,uint256)"),
            "\",\"recipeHash\":\"", _sel("recipeHash(uint8,bytes32)"),
            "\",\"band\":\"", _sel("band(uint256,uint24,uint24)"),
            "\",\"facetArg\":\"", _sel("facetArg(uint256,uint24,uint24)"),
            "\",\"gateFacetArg\":\"", _sel("gateFacetArg(uint256,uint24,uint24,uint64,uint64)"),
            "\",\"deployHook\":\"", _sel("deployHook(uint8,bytes32,bytes32)"),
            "\",\"initV4\":\"", _sel("initialize((address,address,uint24,int24,address),uint160)"),
            "\",\"mintPlan\":\"", _sel("mintPlan(uint256,address,((address,address,uint24,int24,address),int24,int24,uint160,uint128,uint128,address,uint256,bytes))"),
            "\",\"increasePlan\":\"", _sel("increasePlan(uint256,uint256,uint128,uint128,uint256,bytes)"),
            "\",\"decreasePlan\":\"", _sel("decreasePlan(uint256,uint256,uint128,uint128,address,uint256,bytes)"),
            "\",\"collectPlan\":\"", _sel("collectPlan(uint256,address,uint256,bytes)"),
            "\",\"burnPlan\":\"", _sel("burnPlan(uint256,uint128,uint128,address,uint256,bytes)"),
            "\",\"positionInfo\":\"", _sel("getPoolAndPositionInfo(uint256)"),
            "\",\"positionLiquidity\":\"", _sel("getPositionLiquidity(uint256)"),
            "\",\"ownerOf\":\"", _sel("ownerOf(uint256)"),
            "\",\"permitApprove\":\"", _sel("approve(address,address,uint160,uint48)"),
            "\",\"permitAllowance\":\"", _sel("allowance(address,address,address)"),
            "\",\"allowance\":\"", _sel("allowance(address,address)"),
            "\",\"account\":\"", _sel("account(uint256)"),
            "\",\"livePrice\":\"", _sel("livePrice((address,address,uint24,int24,address),uint160)"),
            "\"}}</script>"
        );
    }

    function _sel(string memory sig) private pure returns (string memory) {
        bytes4 x = bytes4(keccak256(bytes(sig)));
        bytes memory h = "0123456789abcdef";
        bytes memory o = new bytes(10); o[0] = "0"; o[1] = "x";
        for (uint256 i; i < 4; ++i) { o[2+i*2]=h[uint8(x[i])>>4]; o[3+i*2]=h[uint8(x[i])&15]; }
        return string(o);
    }
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
            "<label>position owner and fee controller <span class=m>this choice controls "
            "liquidity and receives LP fees</span></label>"
            "<select id=lot><option value=wallet>My wallet</option>"
            "<option value=reach>The signing NFT's Reach</option>"
            "<option value=other>Another address</option></select>"
            "<input id=lo placeholder=\"0x&hellip; only for Another address\" style=\"display:none\">"
            "<div class=two><div><label>deadline (minutes)</label><input id=ld value=\"20\"></div>"
            "<div><label>hook data <span class=m>hex</span></label><input id=lh value=\"0x\"></div></div>"
            "<div class=det id=lplan></div>"
            "<button id=lcheck>Build and inspect the position</button>"
            "<button id=lapprove>Approve both currencies</button>"
            "<button id=lrevoke>Revoke PositionManager allowances</button>"
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
            "Native currency needs neither approval and is sent as transaction value.</p>"
            "<h2>5 &middot; manage a position</h2>"
            "<div class=app><div class=hd><b>Inspect, fund, collect or close</b></div>"
            "<label>PositionManager NFT id</label><input id=mi placeholder=\"1\">"
            "<button id=minfo>Inspect position</button><div class=det id=minfod></div>"
            "<label>action</label><select id=ma><option value=collect>Collect fees</option>"
            "<option value=increase>Add liquidity</option><option value=decrease>Remove liquidity</option>"
            "<option value=burn>Burn empty position</option></select>"
            "<label>liquidity <span class=m>required for add/remove; raw liquidity units</span></label>"
            "<input id=ml value=\"0\">"
            "<div class=two><div><label>token 0 limit <span class=m>max for add, min otherwise; base units</span></label>"
            "<input id=mm0 value=\"0\"></div><div><label>token 1 limit</label><input id=mm1 value=\"0\"></div></div>"
            "<label>recipient <span class=m>blank means connected wallet</span></label><input id=mr placeholder=\"0x&hellip;\">"
            "<div class=two><div><label>deadline (minutes)</label><input id=md value=\"20\"></div>"
            "<div><label>hook data</label><input id=mh value=\"0x\"></div></div>"
            "<button id=mpreview>Build and inspect action</button>"
            "<button id=mapprove>Approve add-liquidity limits</button>"
            "<button class=go id=mgo disabled>Send to PositionManager</button>"
            "<div class=det id=mplan></div><div id=s></div></div>"
            "<p class=e>The planner reads the position's real PoolKey from PositionManager; "
            "the form cannot substitute settlement currencies. PositionManager itself "
            "enforces ownership or approval. Fee collection remains available while a "
            "Gate + Facet principal lock is active; removing principal does not.</p>";
    }
}

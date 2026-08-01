// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenView} from "../lib/Types.sol";

/*───────────────────────────────────────────────────────────────────────────
  The site's view of the collection.

  Five contracts render this site, and they read the same eight or nine
  things. Declaring those once is not tidiness — a page that declares its
  own copy of an interface is a page that keeps compiling after the
  contract it reads has changed shape, and then serves a number that means
  something else.
───────────────────────────────────────────────────────────────────────────*/

interface IHub {
    function totalSupply() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
    function price() external view returns (uint256);
    function ownerOf(uint256 id) external view returns (address);
    function tokenURI(uint256 id) external view returns (string memory);
    function tokenURIAt(uint256 id, uint256 index) external view returns (string memory);
    function hasPinnedTokenURI(uint256 id) external view returns (bool);
    function sectionOf(uint256 id) external view returns (uint256);
    function kernelStatus(uint256 id) external view returns (uint8);
    function locked(uint256 id) external view returns (bool);
    function account(uint256 id) external view returns (address);
    function grip(uint256 id) external view returns (address);
    function viewOf(uint256 id) external view returns (TokenView memory);
    function renderer() external view returns (address);
    function userOf(uint256 id) external view returns (address);
    function userExpires(uint256 id) external view returns (uint256);
    function leaseAgentOf(uint256 id) external view returns (address);
    function pool() external view returns (address);
}

interface ISigilDraw {
    function svg(uint256 id, uint256 word, bytes32 seed, uint32 strata)
        external view returns (bytes memory);
}

interface IRendererDoc {
    /// @dev The document before it is base64'd into a data: URI — the same
    ///      bytes, one step earlier.
    function document(TokenView memory v) external view returns (bytes memory);
    function sigil() external view returns (address);
    function facetCount() external view returns (uint256);
}

/*  `market()` returns twelve values, and a page that wants to print all
    twelve alongside four ERC-20 metadata reads runs out of stack even
    through the IR pipeline. One memory struct is one stack slot, so the
    reader packs once and every helper takes the struct.                */
struct MarketView {
    address base;
    address quote;
    uint112 rBase;
    uint112 rQuote;
    uint16  feeBps;
    bool    open;
    uint256 conc;
    uint256 spot;
    uint256 maxBaseOut;
    uint256 maxQuoteOut;
    uint256 trades;
    uint64  bondUntil;
    uint8   dBase;
    uint8   dQuote;
}

interface IPoolRead {
    function market(uint256 id)
        external view
        returns (
            address base, address quote,
            uint112 rBase, uint112 rQuote,
            uint16 feeBps, bool open,
            uint256 concentrationBps,
            uint256 spotBaseInQuote,
            uint256 maxBaseOut, uint256 maxQuoteOut,
            uint256 trades, uint64 bondUntil
        );
    function quote(uint256 id, bool baseIn, uint256 amountIn) external view returns (uint256);
    function isBonded(uint256 id) external view returns (bool);
    function paused() external view returns (bool);
}

interface ILeaseRead {
    function listing(uint256 id)
        external view
        returns (
            bool rentable, uint8 reason,
            uint128 perDay, uint32 minDays, uint32 maxDays,
            address renter, uint64 until,
            uint256 vested, bool bound
        );
    function cost(uint256 id, uint32 dayCount) external view returns (uint256);
    function MAX_DAYS() external view returns (uint32);
}

interface IChrome {
    function head(string memory title) external pure returns (string memory);
    function nav(uint256 id, uint8 here) external pure returns (string memory);
    function navTop(uint8 here) external pure returns (string memory);
    function foot(address premises, uint256 chainId) external pure returns (string memory);
}

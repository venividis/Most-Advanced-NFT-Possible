// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISpeaker} from "./Parley.sol";

/*═══════════════════════════════════════════════════════════════════════════

  AGORA — the tokens decide things out loud

  Governance systems fail in two directions. Most are theatre: a snapshot
  on a server, votes nobody can verify, an outcome somebody's database
  remembers. The rest are foundries of power: an executor holding a
  treasury, where a bug in the counting is a bug in everybody's money.

  This one is neither, on purpose. A proposal is text; a vote is one token,
  one voice, cast before the closing block and never after; the tally is
  arithmetic anybody can redo. **Nothing executes.** The contract has no
  treasury, calls nothing, and owns nothing — what a passed proposal *does*
  is what the holders then do, which is how every constitution actually
  works underneath its formatting.

  Who may vote is the same question Parley answers: the owner, or the
  token's own bound account. Not the renter — a lease buys the instrument's
  use, not its politics.

═══════════════════════════════════════════════════════════════════════════*/
contract Agora {
    ISpeaker public immutable HUB;

    uint256 public constant MAX_TITLE = 96;
    uint256 public constant MAX_BODY = 2048;
    uint32  public constant MIN_DAYS = 1;
    uint32  public constant MAX_DAYS = 30;

    struct Proposal {
        uint256 by;        // the token that proposed
        uint64  opened;    // block timestamp at proposal
        uint64  closes;    // voting ends at this timestamp
        uint32  yes;
        uint32  no;
        string  title;
        string  body_;
    }

    Proposal[] private _props;
    mapping(uint256 => mapping(uint256 => uint8)) public voteOf; // prop → token → 0 none · 1 yes · 2 no

    event Proposed(uint256 indexed id, uint256 indexed by, uint64 closes, string title);
    event Voted(uint256 indexed id, uint256 indexed token, bool support, uint32 yes, uint32 no);

    error NotYours();
    error NoSuchProposal();
    error BadTitle();
    error BadBody();
    error BadWindow();
    error VotingClosed();
    error AlreadyVoted();

    constructor(ISpeaker hub) { HUB = hub; }

    /*  The same voice rule as the parley: the owner, or the token acting as
        itself through its bound account.                                 */
    function mayActAs(uint256 token, address who) public view returns (bool) {
        if (who == address(0)) return false;
        try HUB.ownerOf(token) returns (address o) {
            return who == o || who == HUB.account(token);
        } catch { return false; }
    }

    function _asToken(uint256 token) private view {
        if (!mayActAs(token, msg.sender)) revert NotYours();
    }

    function propose(uint256 by, string calldata title, string calldata body_, uint32 daysOpen)
        external returns (uint256 id)
    {
        _asToken(by);
        if (bytes(title).length == 0 || bytes(title).length > MAX_TITLE) revert BadTitle();
        if (bytes(body_).length > MAX_BODY) revert BadBody();
        if (daysOpen < MIN_DAYS || daysOpen > MAX_DAYS) revert BadWindow();

        id = _props.length;
        _props.push(Proposal({
            by: by,
            opened: uint64(block.timestamp),
            closes: uint64(block.timestamp + uint256(daysOpen) * 1 days),
            yes: 0, no: 0,
            title: title,
            body_: body_
        }));
        emit Proposed(id, by, uint64(block.timestamp + uint256(daysOpen) * 1 days), title);
    }

    /// @notice One token, one voice, once. A vote is cast before the close
    ///         and never changed after — a ballot that can be rewritten is a
    ///         ballot whose count means nothing until the end, and whose end
    ///         is a scramble.
    function vote(uint256 token, uint256 id, bool support) external {
        _asToken(token);
        if (id >= _props.length) revert NoSuchProposal();
        Proposal storage p = _props[id];
        if (block.timestamp >= p.closes) revert VotingClosed();
        if (voteOf[id][token] != 0) revert AlreadyVoted();
        voteOf[id][token] = support ? 1 : 2;
        unchecked { if (support) p.yes += 1; else p.no += 1; }
        emit Voted(id, token, support, p.yes, p.no);
    }

    function count() external view returns (uint256) { return _props.length; }

    function proposalAt(uint256 id)
        external view
        returns (uint256 by, uint64 opened, uint64 closes, uint32 yes, uint32 no,
                 bool open, string memory title, string memory body_)
    {
        if (id >= _props.length) revert NoSuchProposal();
        Proposal storage p = _props[id];
        return (p.by, p.opened, p.closes, p.yes, p.no,
                block.timestamp < p.closes, p.title, p.body_);
    }

    /// @notice The board in one call: ids, closes and tallies for a page of
    ///         proposals, newest first.
    function board(uint256 from, uint256 n)
        external view
        returns (uint256[] memory ids, uint64[] memory closes,
                 uint32[] memory yes, uint32[] memory no)
    {
        uint256 total = _props.length;
        if (from >= total) return (ids, closes, yes, no);
        uint256 take = n < total - from ? n : total - from;
        ids = new uint256[](take);
        closes = new uint64[](take);
        yes = new uint32[](take);
        no = new uint32[](take);
        for (uint256 i; i < take; ++i) {
            uint256 id = total - 1 - from - i;      // newest first
            ids[i] = id;
            closes[i] = _props[id].closes;
            yes[i] = _props[id].yes;
            no[i] = _props[id].no;
        }
    }
}

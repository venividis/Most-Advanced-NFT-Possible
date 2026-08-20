// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IParleyRead {
    function inRoom(uint256 room, uint256 token) external view returns (bool);
    function invited(uint256 room, uint256 token) external view returns (bool);
    function groupKey(uint256 index) external pure returns (uint256);
    function groups() external view returns (uint256);
    function stateOf(uint256 room) external view returns (
        uint64 last, uint64 count, uint64 opened,
        uint32 members, uint8 kind, bool open, uint256 steward, uint256 index,
        string memory name);
}

interface IHubRead {
    function totalSupply() external view returns (uint256);
    function ownerOf(uint256 id) external view returns (address);
}

/*───────────────────────────────────────────────────────────────────────────
  Roster — who is actually in the room

  Parley can tell you a room holds nine tokens. It cannot tell you which
  nine, and that is not an oversight: membership is a mapping, and a mapping
  is not a list. Enumerating it the usual way means replaying `Entered` and
  `Departed` from the beginning of the chain — a range scan, which this
  collection does without on purpose, because a range scan is the thing that
  needs an indexer and an indexer is a server.

  So the answer is asked the other way round. The collection is finite and
  its tokens are numbered from one, so a reader can simply ask about a
  window of them at once: two hundred and fifty-six memberships come back
  packed into a single word, from a single `eth_call`, over state that was
  already public. Nothing is stored here, nothing is written here, and
  nothing about the protocol had to change to make it true — which is the
  whole point. The archive that exists keeps existing; this only reads it.

  ── why this is a separate contract ──

  The messages are the collection's memory, and the contract that holds them
  is kept across every redeploy of this site, because replacing it would not
  migrate a conversation, it would end one. A question that can be answered
  by reading public state should therefore never be a reason to replace it.
  This contract can be thrown away and rewritten every week; the archive
  underneath it does not notice.
───────────────────────────────────────────────────────────────────────────*/
contract Roster {
    IParleyRead public immutable PARLEY;
    IHubRead    public immutable HUB;

    /// @dev One word of answers per call window. Chosen because a `uint256`
    ///      is the largest thing a client with no ABI decoder can read back
    ///      without counting: it is the return value, whole.
    uint256 public constant WINDOW = 256;

    constructor(IParleyRead parley, IHubRead hub) {
        PARLEY = parley;
        HUB = hub;
    }

    /*═══════════════════ who is in a room ═══════════════════*/

    /// @notice Membership for tokens `from` … `from + 255`, one bit each,
    ///         bit 0 being `from`. A set bit is a token in the room.
    /// @dev    The client shifts; the chain counts. Reading 256 tokens costs
    ///         one call and roughly 256 cold storage reads — about 550k gas
    ///         of `eth_call`, which is free to the reader and never mined.
    function inWindow(uint256 room, uint256 from)
        external view returns (uint256 bits)
    {
        uint256 supply = HUB.totalSupply();
        for (uint256 i; i < WINDOW; ++i) {
            uint256 id = from + i;
            if (id == 0 || id > supply) continue;
            if (PARLEY.inRoom(room, id)) bits |= (1 << i);
        }
    }

    /// @notice The same window, for tokens that were invited and have not
    ///         walked in yet. A steward who cannot see this cannot tell an
    ///         ignored invitation from one never sent.
    function invitedInWindow(uint256 room, uint256 from)
        external view returns (uint256 bits)
    {
        uint256 supply = HUB.totalSupply();
        for (uint256 i; i < WINDOW; ++i) {
            uint256 id = from + i;
            if (id == 0 || id > supply) continue;
            if (!PARLEY.inRoom(room, id) && PARLEY.invited(room, id)) bits |= (1 << i);
        }
    }

    /// @notice Membership as a list rather than as bits, for a caller that
    ///         would rather not shift. Bounded by the same window.
    function membersOf(uint256 room, uint256 from)
        external view returns (uint256[] memory ids)
    {
        uint256 supply = HUB.totalSupply();
        uint256[] memory buf = new uint256[](WINDOW);
        uint256 n;
        for (uint256 i; i < WINDOW; ++i) {
            uint256 id = from + i;
            if (id == 0 || id > supply) continue;
            if (PARLEY.inRoom(room, id)) { buf[n] = id; unchecked { ++n; } }
        }
        ids = new uint256[](n);
        for (uint256 i; i < n; ++i) ids[i] = buf[i];
    }

    /*═══════════════════ a token's own rooms ═══════════════════*/

    /// @notice Every group this token is the steward of — the rooms that
    ///         are *its* rooms, and that change hands when it does.
    /// @dev    Group keys are `keccak(1, index)` and the indices run from
    ///         one, so the whole set is derivable: no event replay, no
    ///         registry, nothing to keep in sync. Paged, because a
    ///         collection that founds ten thousand rooms should not punish
    ///         the reader who wants the first ten.
    function stewardedBy(uint256 token, uint256 fromIndex, uint256 count)
        external view returns (uint256[] memory keys, uint256[] memory indexes)
    {
        uint256 total = PARLEY.groups();
        if (fromIndex == 0) fromIndex = 1;
        uint256 end = fromIndex + count;
        if (end > total + 1) end = total + 1;

        uint256[] memory kb = new uint256[](count);
        uint256[] memory ib = new uint256[](count);
        uint256 n;
        for (uint256 i = fromIndex; i < end; ++i) {
            uint256 key = PARLEY.groupKey(i);
            (, , , , , , uint256 steward, ,) = PARLEY.stateOf(key);
            if (steward == token) {
                kb[n] = key;
                ib[n] = i;
                unchecked { ++n; }
            }
        }
        keys = new uint256[](n);
        indexes = new uint256[](n);
        for (uint256 i; i < n; ++i) { keys[i] = kb[i]; indexes[i] = ib[i]; }
    }

    /// @notice Whether a token still exists, for a page that lists members
    ///         and would rather not print a number nobody holds.
    function heldBy(uint256 token) external view returns (address) {
        try HUB.ownerOf(token) returns (address o) { return o; } catch { return address(0); }
    }
}

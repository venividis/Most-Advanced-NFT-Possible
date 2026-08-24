// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenView} from "./lib/Types.sol";
import {IHub, IPoolRead, ILeaseRead} from "./interfaces/Site.sol";

/*═══════════════════════════════════════════════════════════════════════════

  CONSOLE READ — one call, and it cannot revert on you

  The console renders in a single response. That response reads the hub and
  then five satellites, and the satellites are the problem: this collection
  is deployed on five chains and no two of them carry the same set. A pool
  exists on Base and does not on Robinhood. A Nameplate answers on Ethereum
  and there is no ENS registry underneath it anywhere else.

  A page that reads them directly does not degrade on those chains. It
  REVERTS — one absent contract and the whole document is a 500, and the
  holder is told nothing at all about the token in front of them because a
  service they were not asking about is missing.

  So every satellite read is wrapped, and a wrapped read that fails is
  recorded as failed rather than as empty. That distinction is the entire
  reason this contract exists:

      a clear bit means NOBODY ANSWERED
      a set bit with a zero value means THE ANSWER WAS ZERO

  The console prints those differently — "not reported" against "none" —
  because they are different facts and a holder deciding whether to trust a
  number needs to know which one they are looking at. A viewer that renders
  a failed read as a zero is not degrading gracefully; it is lying quietly,
  which is worse than the revert it was trying to avoid.

  Only satellites this contract actually CALLS get a bit. There is no bit
  for a service that has not been wired yet, because a permanently clear
  bit would read as "asked and got nothing" when nobody ever asked.

═══════════════════════════════════════════════════════════════════════════*/
contract ConsoleRead {
    /*──────────────── the satellites, one bit each ────────────────*/

    uint16 internal constant BIT_HUB   = 0x01;   // viewOf
    uint16 internal constant BIT_POOL  = 0x02;   // market
    uint16 internal constant BIT_LEASE = 0x04;   // listing
    uint16 internal constant BIT_OWNER = 0x08;   // ownerOf
    uint16 internal constant BIT_USER  = 0x10;   // userOf / userExpires

    IHub       public immutable HUB;
    IPoolRead  public immutable POOL;
    ILeaseRead public immutable LEASE;

    /*  `try` is not enough on its own, and finding that out is the reason
        this contract has a test.

        Solidity inserts an `extcodesize` check before any external call
        that returns data, and that check reverts BEFORE the call is made —
        so it is not the call failing, and `catch` never sees it. Against an
        address with no code at all, `try POOL.market(id) { } catch { }`
        reverts the whole transaction, which is precisely the failure the
        wrapping was written to prevent.

        Two of the five chains this collection ships on have no pool and no
        lease. Without this check the console is a 500 on both of them, and
        the try/catch reads as protection while providing none.        */
    function _live(address a) private view returns (bool ok_) {
        assembly { ok_ := gt(extcodesize(a), 0) }
    }

    constructor(IHub hub, IPoolRead pool, ILeaseRead lease) {
        HUB = hub;
        POOL = pool;
        LEASE = lease;
    }

    /*──────────────── what a console needs to paint ────────────────*/

    /// @dev Every field a clock is read from, flattened. The console prints
    ///      a date beside the verb it belongs to and never anywhere else, so
    ///      what it needs is the dates — not the objects they came from.
    struct Clocks {
        uint64  leaseUntil;      // the token is rented until
        uint128 leaseVested;     // and this much is collectable now
        uint128 leasePerDay;
        uint32  leaseMinDays;
        uint32  leaseMaxDays;
        address renter;
        bool    rentable;
        uint64  bondUntil;       // the market's inventory is bonded until
        bool    marketOpen;
        uint16  feeBps;
        address base;
        address quote;
        uint64  userExpires;     // ERC-4907, which the lease rides on
        address user;
        uint16  reported;        // which of the above anybody actually answered
    }

    /// @notice Everything the console's first paint needs, in one call.
    /// @dev    `view.id == 0` with BIT_HUB clear is the only genuine
    ///         failure: the hub itself did not answer, and there is no
    ///         token to render. Every other clear bit is a section of the
    ///         console that prints "not reported" and stays useful.
    function look(uint256 id) external view returns (TokenView memory v, Clocks memory c) {
        if (_live(address(HUB))) try HUB.viewOf(id) returns (TokenView memory got) {
            v = got;
            c.reported |= BIT_HUB;
        } catch {
            /*  Left zero on purpose. The console tests BIT_HUB before it
                prints a single fact about the token, because a TokenView of
                zeroes renders as a real token owned by nobody — which is a
                sentence this contract must never be the source of.      */
        }

        /*  Read even when viewOf answered, because `viewOf` is one call to
            one contract and `ownerOf` is the ERC-721 answer. Where they
            disagree the console shows the ERC-721 one and says they
            disagree, which has caught a stale index before.             */
        if (_live(address(HUB))) try HUB.ownerOf(id) returns (address o) {
            v.owner = o;
            c.reported |= BIT_OWNER;
        } catch {}

        if (_live(address(POOL))) try POOL.market(id) returns (
            address base, address quote,
            uint112, uint112,
            uint16 feeBps, bool open,
            uint256, uint256, uint256, uint256, uint256,
            uint64 bondUntil
        ) {
            c.base = base;
            c.quote = quote;
            c.feeBps = feeBps;
            c.marketOpen = open;
            c.bondUntil = bondUntil;
            c.reported |= BIT_POOL;
        } catch {}

        if (_live(address(LEASE))) try LEASE.listing(id) returns (
            bool rentable, uint8,
            uint128 perDay, uint32 minDays, uint32 maxDays,
            address renter, uint64 until,
            uint256 vested, bool
        ) {
            c.rentable = rentable;
            c.leasePerDay = perDay;
            c.leaseMinDays = minDays;
            c.leaseMaxDays = maxDays;
            c.renter = renter;
            c.leaseUntil = until;
            /*  Down-cast deliberately and only after the bound is checked.
                An unchecked cast of a vested balance is a number that wraps
                to something small and plausible, which is the shape of
                error a holder cannot see and cannot argue with.        */
            c.leaseVested = vested > type(uint128).max ? type(uint128).max : uint128(vested);
            c.reported |= BIT_LEASE;
        } catch {}

        /*  ERC-4907 is the standard the lease rides on, and it is answered
            by the hub rather than by the lease. Read separately, because a
            token can carry a user with no listing at all — an outright
            grant is not a rental and the console says so.               */
        if (_live(address(HUB))) try HUB.userOf(id) returns (address u) {
            c.user = u;
            try HUB.userExpires(id) returns (uint256 e) {
                c.userExpires = e > type(uint64).max ? type(uint64).max : uint64(e);
                c.reported |= BIT_USER;
            } catch {}
        } catch {}
    }

    /// @notice Which satellites answered, as words, for a client that would
    ///         rather not carry this contract's bit assignments.
    /// @dev    Public because the console's own JavaScript reads it to decide
    ///         between "not reported" and "none", and a client that has to
    ///         hard-code a bit mask is a client that will be wrong about it
    ///         one deployment from now.
    function bits()
        external pure
        returns (uint16 hub, uint16 pool, uint16 lease, uint16 owner, uint16 user)
    {
        return (BIT_HUB, BIT_POOL, BIT_LEASE, BIT_OWNER, BIT_USER);
    }

    /*═══════════════════ the selector table ═══════════════════*/

    /// @notice Every four-byte selector the console's client sends, as the
    ///         literal `,sel:{…}` fragment of its seed. Solidity has keccak;
    ///         a browser does not, and shipping two kilobytes of it so the
    ///         client can recompute what a contract already knows is a
    ///         client that can be wrong about something it never had to
    ///         decide.
    /// @dev    This lives HERE and not in PageConsole because the lanes'
    ///         second tranche grew the table to twenty-seven entries and
    ///         pushed that contract to 98% of EIP-170 — the exact squeeze
    ///         CONSOLE.md §H.2 planned satellites for. The read side of the
    ///         console had five sixths of its ceiling free, and a selector
    ///         derived on chain is a read.
    ///
    ///         Name, then signature, as DATA driven by one loop rather than
    ///         as twenty-seven concat sites, because every call site pays
    ///         its own codegen and one loop pays once. `price()` exists so
    ///         the mint lane can read the cost and ATTACH it — a payable
    ///         mint proposed at zero value reverts. `approve`/`allowance`
    ///         act on a market's own ERC-20s, never on the hub; they exist
    ///         for the approve-as-current-step button. `speak`/`stateOf`
    ///         act on Parley; the walk itself needs no selector because it
    ///         is logs, not calls.
    function sels() external pure returns (string memory out) {
        string[54] memory t = [
            string("commit"), "commit(uint256,uint256)",
            "embody",     "embody(uint256)",
            "embodyGrip", "embodyGrip(uint256)",
            "xfer",       "transferFrom(address,address,uint256)",
            "mint",       "mint()",
            "price",      "price()",
            "open",       "openMarket(uint256,address,address,uint16)",
            "close",      "closeMarket(uint256)",
            "setFee",     "setFee(uint256,uint16)",
            "bond",       "bond(uint256,uint64)",
            "deposit",    "deposit(uint256,uint256,uint256)",
            "withdraw",   "withdraw(uint256,uint256,uint256,address)",
            "quote",      "quote(uint256,bool,uint256)",
            "swap",       "swap(uint256,bool,uint256,uint256,address,uint256)",
            "sync",       "syncCurve(uint256)",
            "drift",      "pendingCurve(uint256)",
            "approve",    "approve(address,uint256)",
            "allowance",  "allowance(address,address)",
            "setUser",    "setUser(uint256,address,uint64)",
            "lock",       "lock(uint256)",
            "unlock",     "unlock(uint256)",
            "locked",     "locked(uint256)",
            "speak",      "speak(uint256,uint256,uint8,bytes)",
            "state",      "stateOf(uint256)",
            "balance",    "balanceOf(address)",
            "decimals",   "decimals()",
            "symbol",     "symbol()"
        ];
        out = ",sel:{";
        for (uint256 i; i < 54; i += 2) {
            out = string.concat(out, i == 0 ? "" : ",", t[i], ":\"", _sel(t[i + 1]), "\"");
        }
        out = string.concat(out, "}");
    }

    /*  The four bytes a client sends, and nothing about how they were
        arrived at. A signature spelled in two places is a signature that
        will differ in one of them.                                      */
    function _sel(string memory sig) private pure returns (string memory) {
        bytes4 s = bytes4(keccak256(bytes(sig)));
        bytes memory hexd = "0123456789abcdef";
        bytes memory o = new bytes(10);
        o[0] = "0"; o[1] = "x";
        for (uint256 k; k < 4; ++k) {
            o[2 + k * 2] = hexd[uint8(s[k]) >> 4];
            o[3 + k * 2] = hexd[uint8(s[k]) & 0x0f];
        }
        return string(o);
    }
}

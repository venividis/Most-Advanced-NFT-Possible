// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*───────────────────────────────────────────────────────────────────────────
  Locker — the vault where a promise is kept by the clock

  "The team's tokens are locked for two years" is the most broken promise in
  this industry, because it is usually kept by a multisig, a spreadsheet, or
  nothing. This contract keeps it the only way a contract can: the tokens
  sit here, the unlock time is written once, and there is no function that
  ends a lock early — not for the locker, not for a curator, not for anyone,
  because no such function exists to call.

  ── what it will and will not do ──

  Anyone locks any ERC-20 for any term up to ten years. The lock can be
  *extended*, never shortened — lengthening a promise breaks faith with
  nobody. There is no owner, no pause, no rescue path and no fee. A rescue
  path is an unlock with a nicer name.

  Ten years is a ceiling, not a suggestion, and it exists because the chain
  outlives intentions: a lock that cannot end until 2036 is enforceable; a
  lock with no end is a burn wearing a vault's clothing, and burning has an
  honest address already.

  ── the amount recorded is the amount that arrived ──

  A fee-on-transfer token sends less than it was asked to. The lock records
  the balance difference, not the request — so what comes out is what went
  in, and a token that skims cannot make this contract promise more than it
  holds. Rebasing tokens are not accounted for: what is recorded is a token
  amount, and a token whose balances drift will drift here too. The page
  says so; a vault that pretended otherwise would be lying about somebody
  else's contract.
───────────────────────────────────────────────────────────────────────────*/
contract Locker {
    /// @notice The ceiling: ten years, in the 365-day years a slider means.
    uint64 public constant MAX_TERM = 3650 days;

    struct Lock {
        address token;
        uint64  until;
        bool    taken;
        address owner;
        uint256 amount;
    }

    Lock[] private _locks;
    mapping(address => uint256[]) private _of;
    /// @notice How much of a token this vault currently holds under lock —
    ///         the number a launch page cites when it says "locked".
    mapping(address => uint256) public totalLocked;

    event Locked(uint256 indexed id, address indexed token,
                 address indexed owner, uint256 amount, uint64 until);
    event Claimed(uint256 indexed id, address indexed token, uint256 amount);
    event Extended(uint256 indexed id, uint64 until);

    error NothingArrived();
    error NoTime();
    error TooLong();
    error NotYours();
    error NotYet(uint64 until);
    error AlreadyClaimed();
    error OnlyLonger();
    error TransferFailed();

    /*═══════════════════ locking ═══════════════════*/

    /// @notice Lock `amount` of `token` until `until`. What is recorded is
    ///         what actually arrived, measured, not what was asked for.
    function lock(address token, uint256 amount, uint64 until)
        external returns (uint256 id)
    {
        if (until <= block.timestamp) revert NoTime();
        if (until > block.timestamp + MAX_TERM) revert TooLong();

        uint256 before = _balance(token);
        _pull(token, msg.sender, amount);
        uint256 got = _balance(token) - before;
        if (got == 0) revert NothingArrived();

        id = _locks.length;
        _locks.push(Lock(token, until, false, msg.sender, got));
        _of[msg.sender].push(id);
        totalLocked[token] += got;
        emit Locked(id, token, msg.sender, got, until);
    }

    /// @notice After the clock says so, and only to whoever locked it.
    function claim(uint256 id) external {
        Lock storage l = _locks[id];
        if (l.owner != msg.sender) revert NotYours();
        if (block.timestamp < l.until) revert NotYet(l.until);
        if (l.taken) revert AlreadyClaimed();
        l.taken = true;
        totalLocked[l.token] -= l.amount;
        _push(l.token, msg.sender, l.amount);
        emit Claimed(id, l.token, l.amount);
    }

    /// @notice Push the unlock further out. Never nearer — a promise can be
    ///         lengthened without breaking faith with anyone, and only
    ///         lengthened.
    function extend(uint256 id, uint64 until) external {
        Lock storage l = _locks[id];
        if (l.owner != msg.sender) revert NotYours();
        if (l.taken) revert AlreadyClaimed();
        if (until <= l.until) revert OnlyLonger();
        if (until > block.timestamp + MAX_TERM) revert TooLong();
        l.until = until;
        emit Extended(id, until);
    }

    /*═══════════════════ reading ═══════════════════*/

    function count() external view returns (uint256) { return _locks.length; }

    function lockAt(uint256 id)
        external view
        returns (address token, address owner, uint256 amount, uint64 until, bool taken)
    {
        Lock storage l = _locks[id];
        return (l.token, l.owner, l.amount, l.until, l.taken);
    }

    /// @notice Every lock an address has made, by id. Unpaged, because the
    ///         only person who can grow this list is the one who reads it.
    function locksOf(address who) external view returns (uint256[] memory) {
        return _of[who];
    }

    /*═══════════════════ moving tokens that lie ═══════════════════*/

    /*  Some tokens return nothing from transfer, some return false instead
        of reverting. Treat "reverted", "returned false" and "returned
        garbage" identically: the lock did not happen.                    */

    function _pull(address token, address from, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)",
                                    from, address(this), amount));
        if (!ok || !(ret.length == 0 || abi.decode(ret, (bool)))) revert TransferFailed();
    }

    function _push(address token, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        if (!ok || !(ret.length == 0 || abi.decode(ret, (bool)))) revert TransferFailed();
    }

    function _balance(address token) private view returns (uint256) {
        (bool ok, bytes memory ret) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (!ok || ret.length < 32) revert TransferFailed();
        return abi.decode(ret, (uint256));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC721Min {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC20Bal {
    function balanceOf(address who) external view returns (uint256);
}

/*═══════════════════════════════════════════════════════════════════════════

  IPSEITY ACCOUNT — the vault, with a promise it can keep

  ERC-6551 says the registry is canonical and the implementation is a
  parameter. Almost everyone passes the reference implementation and
  inherits its one structural gap: the holder can empty the account at any
  moment, including between agreeing a price for the token and settling it.
  A buyer paying for a token because of what its vault holds has no promise
  at all — the accounting is never violated, the assets are simply gone.

  So this is the implementation instead. Same registry, same CREATE2
  derivation, same interfaces. One addition: a seal.

  ── the seal ──

  SEALED UNTIL a timestamp. It ratchets — it can be pushed further out by
  the holder and lowered by nobody, including through a transfer — so a
  buyer reads one number and knows the floor under it cannot move before
  then. While it holds, nothing this account holds may leave it.

  ── how "nothing leaves" is enforced ──

  Not by listing the calls that move assets. That list cannot be completed:
  `transfer` and `transferFrom` are on it, but so is any protocol's
  `withdrawTo(address)`, `redeem`, `exit`, `sweep`, or a function nobody
  has written yet. A firewall that enumerates is a firewall with a hole in
  it shaped like whatever it has not heard of.

  So the account MEASURES. Before a sealed call it records its own ether
  balance and its balance of every asset on its manifest; after the call it
  checks that not one of them fell. What the call did is irrelevant — what
  matters is what is left. This is the Dave Held Chambers pattern, whose
  hardening pass reached the same conclusion the hard way.

  Measurement alone is still not enough, for one specific reason: an
  approval costs nothing at the moment it is granted. `approve(attacker,
  everything)` moves no balance, passes any measurement, and is drained in
  the next block. Measurement is blind to it precisely because nothing has
  happened yet.

  So the two defences are layered, each covering the other's blind spot:

    · MEASURED   nothing may be smaller after the call than before it,
                 whatever the call was
    · REFUSED    while sealed, no approval-family word executes at all, and
                 no ether leaves — because those are the moves whose damage
                 lands outside the window measurement can see

  ── what the seal does not do ──

  It does not stop the account acting. A sealed vault can still vote, claim,
  compound, sign, and call anything that leaves it no poorer. That is the
  whole reason for measuring rather than freezing: a vault that cannot act
  is not a vault, it is a safe.

  It also cannot promise about an asset nobody named. Only the manifest is
  measured. An asset that arrives after the seal, in a token contract that
  was never listed, can leave freely — so `manifest()` is public and a
  buyer should read it, not assume it.

═══════════════════════════════════════════════════════════════════════════*/
contract IpseityAccount {
    /*──────────────────── ERC-6551 ────────────────────*/

    /// @dev Bumps on every successful execute, per the standard.
    uint256 public state;

    /*──────────────────── the seal ────────────────────*/

    /// @notice Nothing on the manifest leaves before this. Ratchet-only.
    uint64 public sealedUntil;

    /// @dev A promise nobody can outlive is indistinguishable from a burn.
    uint64 public constant MAX_SEAL = 365 days;

    /// @dev Bounded because every entry is two balance reads on every
    ///      sealed call, and an unbounded list is an unbounded gas cost
    ///      that eventually makes the account unusable.
    uint256 public constant MAX_MANIFEST = 16;

    address[] internal _manifest;
    mapping(address => bool) public onManifest;

    event Sealed(uint64 until);
    event ManifestAdded(address indexed asset);
    event Executed(address indexed to, uint256 value, bytes4 selector, bool sealedNow);

    error NotSigner();
    error OnlyCall();
    error RatchetOnly();
    error SealTooLong();
    error IsSealed();
    error ApprovalWhileSealed();
    error ValueWhileSealed();
    error Shrank(address asset, uint256 before_, uint256 after_);
    error ManifestFull();
    error AlreadyListed();
    error OwnershipCycle();

    receive() external payable {}

    /*──────────────────── who this account belongs to ────────────────────*/

    /// @dev The registry appends salt, chainId, tokenContract and tokenId to
    ///      the proxy's runtime code. The proxy body is 45 bytes, so the
    ///      three values this needs begin at 0x4d.
    function token() public view returns (uint256 chainId, address tokenContract, uint256 tokenId) {
        bytes memory footer = new bytes(0x60);
        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }
        return abi.decode(footer, (uint256, address, uint256));
    }

    function owner() public view returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return address(0);   // not our chain, not our owner
        return IERC721Min(tokenContract).ownerOf(tokenId);
    }

    function isValidSigner(address signer, bytes calldata) external view returns (bytes4) {
        return signer == owner() ? this.isValidSigner.selector : bytes4(0);
    }

    modifier onlySigner() {
        address o = owner();
        if (msg.sender != o) revert NotSigner();
        // an account that owns its own token can authorise itself forever
        if (o == address(this)) revert OwnershipCycle();
        _;
    }

    /*──────────────────── sealing ────────────────────*/

    /// @notice Promise that nothing on the manifest leaves before `until`.
    /// @dev    Ratchet-only, and it survives the sale of the token, because
    ///         it is a promise to whoever reads it rather than to whoever
    ///         made it.
    function seal(uint64 until) external onlySigner {
        if (until <= block.timestamp) revert RatchetOnly();
        if (until <= sealedUntil) revert RatchetOnly();
        if (until > block.timestamp + MAX_SEAL) revert SealTooLong();
        sealedUntil = until;
        emit Sealed(until);
    }

    function isSealed() public view returns (bool) {
        return sealedUntil > block.timestamp;
    }

    /// @notice Put an asset under the seal. Additive only: an asset can be
    ///         promised but never quietly un-promised, or the manifest would
    ///         be a promise that could be emptied instead of the vault.
    function guard(address asset) external onlySigner {
        if (onManifest[asset]) revert AlreadyListed();
        if (_manifest.length >= MAX_MANIFEST) revert ManifestFull();
        onManifest[asset] = true;
        _manifest.push(asset);
        emit ManifestAdded(asset);
    }

    function manifest() external view returns (address[] memory) {
        return _manifest;
    }

    /// @notice Everything a buyer needs before agreeing a price: the date,
    ///         the assets under it, and what the account holds of each right
    ///         now.
    function holdings()
        external view
        returns (uint64 until, address[] memory assets, uint256[] memory balances, uint256 ether_)
    {
        until = sealedUntil;
        assets = _manifest;
        balances = new uint256[](assets.length);
        for (uint256 i; i < assets.length; ++i) balances[i] = _balance(assets[i]);
        ether_ = address(this).balance;
    }

    /*──────────────────── acting ────────────────────*/

    /// @notice ERC-6551 execute. Only CALL; only the holder.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external payable onlySigner returns (bytes memory result)
    {
        if (operation != 0) revert OnlyCall();

        bool locked = isSealed();
        uint256[] memory pre;
        uint256 preEth;

        if (locked) {
            // ether is not on any manifest and cannot be measured after the
            // fact against a payable call, so it is simply refused
            if (value != 0) revert ValueWhileSealed();
            if (msg.value != 0) revert ValueWhileSealed();
            _refuseApprovals(data);
            (pre, preEth) = _snapshot();
        }

        unchecked { state++; }

        bool ok;
        (ok, result) = to.call{value: value}(data);
        if (!ok) {
            // bubble the callee's own revert rather than flattening it
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }

        if (locked) _verify(pre, preEth);

        emit Executed(to, value, data.length >= 4 ? bytes4(data[0:4]) : bytes4(0), locked);
    }

    /*──────────────────── the two defences ────────────────────*/

    /// @dev An approval moves nothing, so measurement is blind to it: the
    ///      loss lands in a later block, outside any window this call can
    ///      see. There is no venue registry here to make exceptions for, so
    ///      there are no exceptions.
    function _refuseApprovals(bytes calldata data) internal pure {
        if (data.length < 4) return;
        bytes4 sel = bytes4(data[0:4]);
        if (
            sel == 0x095ea7b3 ||   // approve(address,uint256)
            sel == 0xa22cb465 ||   // setApprovalForAll(address,bool)
            sel == 0x39509351 ||   // increaseAllowance(address,uint256)
            sel == 0x87b4f6a4 ||   // approveAndCall variants seen in the wild
            sel == 0xd505accf ||   // permit(address,address,uint256,uint256,uint8,bytes32,bytes32)
            sel == 0x8fcbaf0c      // permit (DAI-style)
        ) revert ApprovalWhileSealed();
    }

    function _snapshot() internal view returns (uint256[] memory pre, uint256 preEth) {
        uint256 n = _manifest.length;
        pre = new uint256[](n);
        for (uint256 i; i < n; ++i) pre[i] = _balance(_manifest[i]);
        preEth = address(this).balance;
    }

    /// @dev The whole point: what the call *did* does not matter, only what
    ///      is left. A selector nobody has heard of is caught here.
    function _verify(uint256[] memory pre, uint256 preEth) internal view {
        uint256 n = _manifest.length;
        for (uint256 i; i < n; ++i) {
            uint256 now_ = _balance(_manifest[i]);
            if (now_ < pre[i]) revert Shrank(_manifest[i], pre[i], now_);
        }
        if (address(this).balance < preEth) revert Shrank(address(0), preEth, address(this).balance);
    }

    /// @dev balanceOf(address) is the same word for ERC-20 and ERC-721, so
    ///      one manifest covers both. A contract that does not answer it
    ///      reads as zero, which can only ever tighten the check.
    function _balance(address asset) internal view returns (uint256) {
        (bool ok, bytes memory out) =
            asset.staticcall(abi.encodeWithSelector(IERC20Bal.balanceOf.selector, address(this)));
        if (!ok || out.length < 32) return 0;
        return abi.decode(out, (uint256));
    }

    /*──────────────────── receiving ────────────────────*/

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external pure returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    /*──────────────────── ERC-1271 ────────────────────*/

    /// @notice A signature is valid if the token's holder signed it.
    /// @dev    Refused entirely while sealed: a signature is an off-chain
    ///         authority whose effect lands wherever and whenever the
    ///         counterparty chooses, which is exactly the shape of thing
    ///         measurement cannot see.
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external view returns (bytes4)
    {
        if (isSealed()) return bytes4(0);
        if (signature.length != 65) return bytes4(0);

        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        // reject the malleable upper half of the curve order
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return bytes4(0);
        }
        address signer = ecrecover(hash, v, r, s);
        if (signer != address(0) && signer == owner()) return 0x1626ba7e;
        return bytes4(0);
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7    // ERC-165
            || id == 0x6faff5f1    // IERC6551Account
            || id == 0x51945447    // IERC6551Executable
            || id == 0x150b7a02    // ERC721Receiver
            || id == 0x4e2312e0;   // ERC1155Receiver
    }
}

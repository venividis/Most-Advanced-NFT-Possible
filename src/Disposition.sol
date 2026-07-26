// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC721Min {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/*═══════════════════════════════════════════════════════════════════════════

  THE DISPOSITION — the private half, in the shape ERC-7857 gives it

  Everything else in this collection is public on purpose. The artwork is
  bytes in contract code. The market's curve is a word anyone can read. The
  Grip's holdings are a floor anyone can verify. That is the whole thesis:
  a token that does not ask you to trust a promise.

  An agent breaks the symmetry. If the holder hands a bounded key to
  something that acts for them — a keeper, a bot, a model — then *how that
  thing decides* is worth something, and publishing it in full is how you
  get front-run. The strategy wants to be private. The authority under
  which it runs must stay public, or nobody can price the token.

  ERC-7857 is the standard for exactly that asymmetry: an NFT whose
  metadata is a secret, held off-chain as ciphertext, committed to on-chain
  by hash, and *re-sealed to the buyer's key* when the token sells — with
  an oracle (a TEE or a zero-knowledge proof) attesting that the re-seal
  was honest. It is the first place in this project where 7857 is not a
  stretch. Everywhere else it is the inverse of what this collection is.

  ── what is here, and what is not ──

  Here: the commitment, the pointer, the ownership binding, and the
  staleness derivation. Those are the parts that need no trusted party. A
  buyer can check the ciphertext they were handed against `commitment`
  themselves, with a hash, offline, before paying.

  Not here: the verifier. ERC-7857's re-seal proof requires a TEE
  attestation or a ZK circuit, and this collection ships neither. Rather
  than fake one, `VERIFIER` is an address that may legitimately be zero,
  `attestedBy` reads back zero when nobody has checked anything, and
  `status()` will not call a kernel trustworthy on the strength of a
  promise. An unattested kernel is a kernel a buyer must verify by hand.
  Saying so is the feature.

  ── the staleness derivation ──

  There is no transfer hook, and none is needed. A kernel records the owner
  it was sealed to. Compare that with `ownerOf` at read time:

      sealedTo == ownerOf   →  CURRENT   the holder can open it
      sealedTo != ownerOf   →  STALE     the token moved; this ciphertext
                                         is addressed to someone who no
                                         longer holds it

  So a sale automatically invalidates the disposition, with no cooperation
  from anyone and no gas spent. The buyer knows before they pay that what
  they are buying is a *pointer that must be re-sealed*, and the seller
  cannot dress a stale kernel up as a live one. That is the honest
  two-step version of 7857's atomic re-encrypt-on-transfer: an on-chain
  contract cannot verify a re-encryption without an oracle, but it can
  always refuse to pretend one happened.

  ── what this contract cannot do ──

  It has no function that moves an asset. Not for the holder, not for the
  verifier, not for anybody — the same argument as GripVault, and it is
  asserted against the compiled ABI rather than the prose.

  And it cannot make the seller forget. Re-sealing gives the buyer the
  secret; nothing on any chain takes it back from whoever had it first.
  That is a limitation of ERC-7857 itself and not of this implementation,
  and it is written down in INVARIANTS.md rather than glossed.

═══════════════════════════════════════════════════════════════════════════*/
contract Disposition {
    /// @notice The collection whose tokens these kernels belong to.
    IERC721Min public immutable TOKEN;

    /// @notice The only address that may attest a re-seal. May be zero, and
    ///         is zero in this deployment: there is no oracle here, and a
    ///         zero reads back as "nobody has ever checked this".
    address public immutable VERIFIER;

    struct Kernel {
        bytes32 commitment;   // keccak256 of the ciphertext, checkable offline
        address sealedTo;     // the owner the ciphertext was encrypted for
        uint64  sealedAt;
        address attestedBy;   // the verifier that checked this exact blob; 0 = none
        string  uri;          // where the ciphertext lives
    }

    mapping(uint256 => Kernel) internal _kernel;

    uint8 public constant ABSENT  = 0;
    uint8 public constant CURRENT = 1;
    uint8 public constant STALE   = 2;

    event Published(uint256 indexed id, address indexed sealedTo, bytes32 commitment);
    event Attested(uint256 indexed id, address indexed verifier, bytes32 commitment);
    event Cleared(uint256 indexed id);

    error NotHolder();
    error NotVerifier();
    error NoKernel();
    error CommitmentMismatch();
    error EmptyCommitment();

    constructor(IERC721Min token_, address verifier_) {
        TOKEN = token_;
        VERIFIER = verifier_;
    }

    modifier onlyHolder(uint256 id) {
        if (msg.sender != TOKEN.ownerOf(id)) revert NotHolder();
        _;
    }

    /*──────────────── publishing ────────────────*/

    /// @notice Commit to a ciphertext and say where it lives.
    /// @dev    Sealed to the *current* owner, read from the token contract
    ///         rather than taken from the caller, so the binding is the
    ///         chain's opinion and not the publisher's.
    ///
    ///         Every publish clears `attestedBy`. A new blob has not been
    ///         checked merely because an older one was.
    function publish(uint256 id, bytes32 commitment, string calldata uri)
        external onlyHolder(id)
    {
        if (commitment == bytes32(0)) revert EmptyCommitment();

        address holder = TOKEN.ownerOf(id);
        _kernel[id] = Kernel({
            commitment: commitment,
            sealedTo: holder,
            sealedAt: uint64(block.timestamp),
            attestedBy: address(0),
            uri: uri
        });

        emit Published(id, holder, commitment);
    }

    /// @notice Withdraw the pointer entirely. The token keeps working; it
    ///         simply stops claiming to carry a disposition.
    function clear(uint256 id) external onlyHolder(id) {
        delete _kernel[id];
        emit Cleared(id);
    }

    /*──────────────── attesting ────────────────*/

    /// @notice An oracle records that it checked this exact blob.
    /// @dev    The commitment is passed in and must match, so an attestation
    ///         cannot survive the holder swapping the ciphertext underneath
    ///         it — a race that would otherwise let a stale approval bless
    ///         a document nobody verified.
    ///
    ///         The verifier attests. It does not publish, cannot publish,
    ///         and has no other power here.
    function attest(uint256 id, bytes32 commitment) external {
        if (msg.sender != VERIFIER || VERIFIER == address(0)) revert NotVerifier();

        Kernel storage k = _kernel[id];
        if (k.commitment == bytes32(0)) revert NoKernel();
        if (k.commitment != commitment) revert CommitmentMismatch();

        k.attestedBy = msg.sender;
        emit Attested(id, msg.sender, commitment);
    }

    /*──────────────── reading ────────────────*/

    /// @notice ABSENT, CURRENT or STALE — derived, never stored.
    function status(uint256 id) public view returns (uint8) {
        Kernel storage k = _kernel[id];
        if (k.commitment == bytes32(0)) return ABSENT;

        // a token that no longer exists cannot have a current disposition
        (bool ok, bytes memory out) =
            address(TOKEN).staticcall(abi.encodeWithSelector(IERC721Min.ownerOf.selector, id));
        if (!ok || out.length < 32) return STALE;

        return abi.decode(out, (address)) == k.sealedTo ? CURRENT : STALE;
    }

    /// @notice The whole record, plus the derived status, in one read.
    function kernel(uint256 id)
        external view
        returns (
            bytes32 commitment,
            address sealedTo,
            uint64 sealedAt,
            address attestedBy,
            string memory uri,
            uint8 state
        )
    {
        Kernel storage k = _kernel[id];
        return (k.commitment, k.sealedTo, k.sealedAt, k.attestedBy, k.uri, status(id));
    }

    /// @notice Two independent questions, deliberately not merged into one.
    ///         `isCurrent` says the ciphertext is addressed to whoever holds
    ///         the token. `isAttested` says somebody with a proof system
    ///         checked it. A buyer who conflates them is buying a promise.
    function isCurrent(uint256 id) external view returns (bool) {
        return status(id) == CURRENT;
    }

    function isAttested(uint256 id) external view returns (bool) {
        Kernel storage k = _kernel[id];
        return k.attestedBy != address(0) && k.attestedBy == VERIFIER && status(id) == CURRENT;
    }

    /// @notice Stated in the ABI as well as the prose: this deployment has
    ///         no oracle, and every kernel under it is unattested.
    function hasVerifier() external view returns (bool) {
        return VERIFIER != address(0);
    }
}

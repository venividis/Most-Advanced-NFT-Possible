// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IParleyRead {
    function mayActAs(uint256 token, address who) external view returns (bool);
    function MAX_BODY() external view returns (uint256);
}

interface ILayerZeroEndpointV2 {
    struct MessagingParams {
        uint32 dstEid; bytes32 receiver; bytes message; bytes options; bool payInLzToken;
    }
    struct MessagingFee { uint256 nativeFee; uint256 lzTokenFee; }
    struct MessagingReceipt { bytes32 guid; uint64 nonce; MessagingFee fee; }

    function quote(MessagingParams calldata p, address sender)
        external view returns (MessagingFee memory);
    function send(MessagingParams calldata p, address refundTo)
        external payable returns (MessagingReceipt memory);
    function setDelegate(address delegate) external;
    function eid() external view returns (uint32);
}

/*═══════════════════════════════════════════════════════════════════════════

  THE PORT — the commons, heard on the other chains

  The edition is issued from five chains and nothing crosses between them.
  That is the whole design of the partition and it is not being weakened
  here. What crosses is speech.

  ── local first, and local always ──

  `Parley.speak` is untouched. It is free, it is local, it has no
  dependency on this contract or on any bridge, and it keeps working
  exactly as it does today on a chain where this port was never deployed,
  never funded, or has stopped working. Federation is a SEPARATE payable
  call. A holder who never touches it loses nothing; a chain whose port is
  dark still has a complete commons.

  That ordering is the point. A social layer that needs a message to
  arrive before anyone can talk is a social layer with a single point of
  silence.

  ── what is federated, and what must never be ──

  The commons only — room 0, the one room every token is already in.

  Groups stay local because a group has a steward, and a steward is an
  authority; carrying that across would mean trusting a message to say who
  may speak. Pairs stay local for a better reason: a pair room is derived
  from two token ids, and under the partition those two ids may live on
  different chains, so a federated pair room would be a room that means
  different things in different places. There is no correct way to do it
  and so there is no function for it.

  This port cannot write into Parley at all. It has no privilege there and
  asks for none — Parley checks `mayActAs` against the caller, and this
  contract is not a token. What arrives is emitted here, under this
  contract's own event, tagged with where it came from. The archive on each
  chain therefore stays exactly what it always was: a record of what was
  said by someone standing on that chain. A reader that wants the whole
  conversation reads two logs instead of one, and can always tell which is
  which.

  ── the back-link is rewritten on arrival, and has to be ──

  Parley's walk works because every message carries the block number of the
  previous one, so a client can step backwards with single-block
  `eth_getLogs` and never scan a range. That pointer is meaningless on
  another chain — block 21,000,000 on Ethereum is not block 21,000,000
  anywhere else. So the sender's pointer is dropped at the border and this
  contract writes its own, in the receiving chain's numbering. An echoed
  conversation is walkable on the chain you are standing on, which is the
  only chain whose blocks you can ask about.

  ── the verifier set is frozen in the constructor ──

  LayerZero lets an OApp choose which DVNs must attest to its messages, and
  lets a delegate change that later. A delegate is an admin key. So this
  constructor sets the configuration and then calls `setDelegate(address(0))`,
  and there is no function here that calls `setConfig` or `setDelegate`
  again. After deployment the verifier set is as immutable as the bytecode.

  Two protocol properties are worth stating because they are the reason
  this is admissible at all. An unwired lane fails at QUOTE time — the
  default verifier is a small contract whose entire behaviour is to revert
  with "Please set your OApp's DVNs and/or Executor" — so a lane that was
  never configured refuses loudly instead of accepting a message that would
  never arrive. And delivery is permissionless: the endpoint's receive
  entry point has no access control, so once the DVNs have attested,
  anyone can deliver. The paid executor is a convenience and never a
  dependency, which means no server is required for any of this to work.

═══════════════════════════════════════════════════════════════════════════*/
contract ParleyPort {
    IParleyRead public immutable PARLEY;
    ILayerZeroEndpointV2 public immutable ENDPOINT;
    uint32 public immutable LOCAL_EID;

    /// @dev Room 0. The only room that crosses.
    uint256 public constant COMMONS = 0;
    uint256 public constant MAX_BODY = 1024;

    /*  The peers, fixed at construction. A port that could learn a new peer
        afterwards is a port whose owner can introduce a chain nobody
        agreed to, and every message from it would look exactly like the
        others.                                                          */
    uint32[] internal _peerEids;
    mapping(uint32 => bytes32) public peerOf;

    /*  The receiving chain's own back-link, so an echoed conversation can
        be walked here with the same single-block step the local one uses. */
    uint64 public lastEcho;
    uint64 public echoCount;

    event Echoed(
        uint32  indexed originEid,
        uint256 indexed fromToken,
        uint64  prev,
        uint64  seq,
        uint8   kind,
        bytes   body
    );
    event Sent(uint32 indexed dstEid, uint256 indexed fromToken, bytes32 guid);

    error NotYours();
    error BadBody();
    error NoPeers();
    error NotTheEndpoint();
    error UnknownPeer(uint32 eid);
    error Underpaid(uint256 want);

    constructor(
        IParleyRead parley,
        ILayerZeroEndpointV2 endpoint,
        uint32[] memory peerEids,
        bytes32[] memory peers
    ) {
        PARLEY = parley;
        ENDPOINT = endpoint;
        LOCAL_EID = endpoint.eid();
        if (peerEids.length == 0 || peerEids.length != peers.length) revert NoPeers();
        for (uint256 i; i < peerEids.length; ++i) {
            _peerEids.push(peerEids[i]);
            peerOf[peerEids[i]] = peers[i];
        }
        /*  No admin, from the first block. There is no function in this
            contract that can undo this.                                 */
        endpoint.setDelegate(address(0));
    }

    function peers() external view returns (uint32[] memory) { return _peerEids; }

    /*═══════════════════ speaking outward ═══════════════════*/

    /// @notice What it costs to echo this to every peer, before you commit.
    /// @dev    An unwired lane reverts here rather than at send, which is
    ///         the protocol refusing to guess and is the behaviour worth
    ///         having: it is better to be told the lane is not configured
    ///         than to pay for a message that never lands.
    function quoteEcho(uint256 from, uint8 kind, bytes calldata body, bytes calldata options)
        public view returns (uint256 total)
    {
        bytes memory m = abi.encode(LOCAL_EID, from, kind, body);
        for (uint256 i; i < _peerEids.length; ++i) {
            total += ENDPOINT.quote(
                ILayerZeroEndpointV2.MessagingParams({
                    dstEid: _peerEids[i], receiver: peerOf[_peerEids[i]],
                    message: m, options: options, payInLzToken: false
                }), address(this)).nativeFee;
        }
    }

    /// @notice Say this in the commons of every other chain as well.
    /// @dev    Deliberately not a wrapper around `Parley.speak`. Saying it
    ///         locally is a separate, free transaction that works whether
    ///         or not this contract exists; this only carries a copy
    ///         outward. Keeping them apart is what makes the local commons
    ///         independent of the bridge rather than merely usually
    ///         independent of it.
    function echo(uint256 from, uint8 kind, bytes calldata body, bytes calldata options)
        external payable
    {
        if (!PARLEY.mayActAs(from, msg.sender)) revert NotYours();
        if (body.length == 0 || body.length > MAX_BODY) revert BadBody();

        uint256 want = quoteEcho(from, kind, body, options);
        if (msg.value < want) revert Underpaid(want);

        bytes memory m = abi.encode(LOCAL_EID, from, kind, body);
        uint256 spent;
        for (uint256 i; i < _peerEids.length; ++i) {
            uint32 dst = _peerEids[i];
            uint256 fee = ENDPOINT.quote(
                ILayerZeroEndpointV2.MessagingParams({
                    dstEid: dst, receiver: peerOf[dst], message: m,
                    options: options, payInLzToken: false
                }), address(this)).nativeFee;
            ILayerZeroEndpointV2.MessagingReceipt memory r = ENDPOINT.send{value: fee}(
                ILayerZeroEndpointV2.MessagingParams({
                    dstEid: dst, receiver: peerOf[dst], message: m,
                    options: options, payInLzToken: false
                }), msg.sender);
            spent += fee;
            emit Sent(dst, from, r.guid);
        }
        /*  Change goes back. A port that quietly keeps the difference
            between the quote and the fee is a port with a revenue model
            nobody was told about.                                       */
        if (msg.value > spent) {
            (bool ok, ) = msg.sender.call{value: msg.value - spent}("");
            if (!ok) revert Underpaid(spent);
        }
    }

    /*═══════════════════ hearing inward ═══════════════════*/

    /// @notice Called by the endpoint once the DVNs have attested.
    /// @dev    The only authority checked is that the endpoint made the
    ///         call and that the origin is a peer this port was built with.
    ///         Nothing here can write to Parley, so the worst a broken peer
    ///         can do is emit a message under its own eid — visible as
    ///         foreign, attributable, and impossible to confuse with
    ///         something said locally.
    function lzReceive(
        bytes calldata origin,      // (srcEid, sender, nonce), abi-encoded
        bytes32,                    // guid
        bytes calldata message,
        address,
        bytes calldata
    ) external payable {
        if (msg.sender != address(ENDPOINT)) revert NotTheEndpoint();
        (uint32 srcEid, bytes32 sender, ) = abi.decode(origin, (uint32, bytes32, uint64));
        bytes32 want = peerOf[srcEid];
        if (want == bytes32(0) || want != sender) revert UnknownPeer(srcEid);

        (uint32 originEid, uint256 from, uint8 kind, bytes memory body) =
            abi.decode(message, (uint32, uint256, uint8, bytes));
        if (body.length == 0 || body.length > MAX_BODY) revert BadBody();

        /*  The sender's back-link is dropped here. Its block number refers
            to a chain whose blocks a reader on this one cannot ask about;
            this contract writes its own instead, so the echoed
            conversation walks with the same single-block step as the
            local one.                                                    */
        uint64 prev = lastEcho;
        lastEcho = uint64(block.number);
        unchecked { echoCount += 1; }

        emit Echoed(originEid, from, prev, echoCount, kind, body);
    }

    /// @notice ERC-165, so a client can tell this is a port before calling.
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7;
    }
}

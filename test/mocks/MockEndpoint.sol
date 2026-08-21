// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*  A LayerZero EndpointV2 with the two behaviours the port actually
    depends on, and nothing else.

    It is not a simulation of the protocol. It is a stand-in for the two
    facts that were verified live against the real endpoints and that the
    port's design rests on: a lane that was never configured refuses at
    QUOTE time rather than accepting a message that would never arrive,
    and delivery carries no access control, so once a message is verified
    anybody can push it into the receiver. Both are reproduced here so the
    port can be driven against them.                                     */
contract MockEndpoint {
    struct MessagingParams {
        uint32 dstEid; bytes32 receiver; bytes message; bytes options; bool payInLzToken;
    }
    struct MessagingFee { uint256 nativeFee; uint256 lzTokenFee; }
    struct MessagingReceipt { bytes32 guid; uint64 nonce; MessagingFee fee; }

    uint32 public eid;
    mapping(address => address) public delegates;
    mapping(uint32 => uint256) public feeFor;          // 0 = the lane is not wired
    mapping(uint32 => address) public endpointFor;     // the peer's endpoint, for delivery

    /// @dev The real one reverts through a 934-byte library whose whole
    ///      behaviour is this string.
    error DeadDVN(string reason);

    uint64 public nonce;
    struct Pending { address to; bytes origin; bytes message; }
    Pending[] public outbox;

    constructor(uint32 e) { eid = e; }

    function setLane(uint32 dstEid, uint256 fee, address peerEndpoint) external {
        feeFor[dstEid] = fee;
        endpointFor[dstEid] = peerEndpoint;
    }
    function setDelegate(address d) external { delegates[msg.sender] = d; }

    function quote(MessagingParams calldata p, address) external view returns (MessagingFee memory) {
        if (feeFor[p.dstEid] == 0) revert DeadDVN("Please set your OApp's DVNs and/or Executor");
        return MessagingFee(feeFor[p.dstEid] + p.message.length, 0);
    }

    function send(MessagingParams calldata p, address)
        external payable returns (MessagingReceipt memory r)
    {
        uint256 fee = feeFor[p.dstEid];
        if (fee == 0) revert DeadDVN("Please set your OApp's DVNs and/or Executor");
        fee += p.message.length;
        require(msg.value >= fee, "underpaid");
        MockEndpoint far = MockEndpoint(endpointFor[p.dstEid]);
        far.receive_(address(uint160(uint256(p.receiver))),
                     abi.encode(eid, bytes32(uint256(uint160(msg.sender))), ++nonce),
                     p.message);
        r.guid = keccak256(abi.encode(p.dstEid, nonce));
        r.nonce = nonce;
        r.fee = MessagingFee(fee, 0);
    }

    /// @dev Parked rather than delivered, so a test can drive the two
    ///      halves apart and prove delivery needs no privilege.
    function receive_(address to, bytes calldata origin, bytes calldata message) external {
        outbox.push(Pending(to, origin, message));
    }
    function pending() external view returns (uint256) { return outbox.length; }

    /// @notice Deliver a parked message. No access control, deliberately.
    function deliver(uint256 i) external {
        Pending memory p = outbox[i];
        (bool ok, bytes memory err) = p.to.call(
            abi.encodeWithSignature(
                "lzReceive(bytes,bytes32,bytes,address,bytes)",
                p.origin, bytes32(0), p.message, address(0), bytes("")));
        if (!ok) assembly { revert(add(err, 0x20), mload(err)) }
    }
}

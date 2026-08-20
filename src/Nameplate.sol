// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibNum} from "./lib/LibNum.sol";

interface IEnsRegistry {
    function owner(bytes32 node) external view returns (address);
}

interface INameWrapperLike {
    function ownerOf(uint256 id) external view returns (address);
}

interface IHubNames {
    function ownerOf(uint256 id) external view returns (address);
    function account(uint256 id) external view returns (address);
    function totalSupply() external view returns (uint256);
}

/*───────────────────────────────────────────────────────────────────────────
  Nameplate — an ENS resolver that answers for the collection

  "What would the web3 address be?" gets its final answer here. Point a
  name you own at this resolver and bind it to a token, and the name means
  the token everywhere ENS is read:

    addr(node)                    → the token's own 6551 account, so
                                    sending ETH to the name funds the token
    text(node,"contentcontract")  → the Premises, per ERC-6821 — a web3://
                                    browser resolves the name straight into
                                    this site with no IPFS and no gateway
    text(node,"avatar")           → the token's sigil, as an eip155 NFT
                                    reference every ENS app knows how to draw
    text(node,"url")              → an https gateway link, for browsers that
                                    speak nothing else

  And once a parent name is claimed, every token is addressable with no
  registration at all: `7.yourname.eth` resolves to token 7, by ENSIP-10
  wildcard — the name exists the moment the token does.

  ── who may do what, and the absence of an admin ──

  Binding a name requires owning it in the ENS registry (wrapped names
  included) — this contract re-checks the registry on every bind rather
  than trusting a caller's word. The parent slot for wildcards is claimed
  once, by whoever owns that parent name at the moment of claiming, and
  never moves again: a write-once slot whose authorization is the ENS
  registry itself is not an admin, it is a mailbox with a name on it.
  Nothing else here can be set by anyone.

  On a chain with no ENS registry the constructor takes zero and every
  bind refuses honestly; the resolver still deploys so the address stays
  the same on every chain, which is this collection's habit.
───────────────────────────────────────────────────────────────────────────*/
contract Nameplate {
    using LibNum for uint256;

    IEnsRegistry public immutable ENS;
    IHubNames    public immutable HUB;
    /// @notice The site, which is what a name serves. ERC-6821's answer.
    address      public immutable PREMISES;

    /// @notice namehash of the parent whose numeric subdomains are tokens.
    ///         Zero until claimed; claimed once, by the parent's ENS owner.
    bytes32 public parentNode;

    mapping(bytes32 => uint256) public tokenOf;   // node → tokenId (0 = unbound)

    event Bound(bytes32 indexed node, uint256 indexed token, address indexed by);
    event Unbound(bytes32 indexed node, uint256 indexed token);
    event ParentClaimed(bytes32 indexed node, address indexed by);

    error NoRegistryHere();
    error NotTheNameOwner();
    error NotTheTokenHolder();
    error ParentAlreadyClaimed();
    error UnknownQuery();

    bytes4 private constant ADDR_IFACE        = 0x3b3b57de; // addr(bytes32)
    bytes4 private constant CONTENTHASH_IFACE = 0xbc1c58d1; // contenthash(bytes32)
    bytes4 private constant TEXT_IFACE        = 0x59d1d43c; // text(bytes32,string)
    bytes4 private constant WILDCARD_IFACE    = 0x9061b923; // resolve(bytes,bytes)

    constructor(IEnsRegistry ens, IHubNames hub, address premises) {
        ENS = ens;
        HUB = hub;
        PREMISES = premises;
    }

    /*═══════════════════ binding ═══════════════════*/

    /// @notice Bind a name you own to a token you hold (or whose account
    ///         you are). The ENS app must also point the name's resolver
    ///         here for browsers to see it; this call records which token
    ///         the name means.
    function bind(bytes32 node, uint256 token) external {
        if (!_ownsNode(node, msg.sender)) revert NotTheNameOwner();
        if (msg.sender != HUB.ownerOf(token) && msg.sender != HUB.account(token))
            revert NotTheTokenHolder();
        tokenOf[node] = token;
        emit Bound(node, token, msg.sender);
    }

    function unbind(bytes32 node) external {
        if (!_ownsNode(node, msg.sender)) revert NotTheNameOwner();
        uint256 t = tokenOf[node];
        delete tokenOf[node];
        emit Unbound(node, t);
    }

    /// @notice Claim the wildcard parent, once, by owning it. After this,
    ///         `<id>.parent` resolves to token <id> forever.
    function claimParent(bytes32 node) external {
        if (parentNode != bytes32(0)) revert ParentAlreadyClaimed();
        if (!_ownsNode(node, msg.sender)) revert NotTheNameOwner();
        parentNode = node;
        emit ParentClaimed(node, msg.sender);
    }

    /*  The same three writes, taking the name as DNS wire format instead
        of a namehash — length-prefixed labels, which a client can build
        with string arithmetic alone. The contract does the hashing,
        because this collection's clients carry no keccak on purpose.   */

    function nodeOf(bytes calldata name) external pure returns (bytes32) {
        return _namehash(name, 0);
    }

    function bindByName(bytes calldata name, uint256 token) external {
        bytes32 node = _namehash(name, 0);
        if (!_ownsNode(node, msg.sender)) revert NotTheNameOwner();
        if (msg.sender != HUB.ownerOf(token) && msg.sender != HUB.account(token))
            revert NotTheTokenHolder();
        tokenOf[node] = token;
        emit Bound(node, token, msg.sender);
    }

    function unbindByName(bytes calldata name) external {
        bytes32 node = _namehash(name, 0);
        if (!_ownsNode(node, msg.sender)) revert NotTheNameOwner();
        uint256 t = tokenOf[node];
        delete tokenOf[node];
        emit Unbound(node, t);
    }

    function claimParentByName(bytes calldata name) external {
        bytes32 node = _namehash(name, 0);
        if (parentNode != bytes32(0)) revert ParentAlreadyClaimed();
        if (!_ownsNode(node, msg.sender)) revert NotTheNameOwner();
        parentNode = node;
        emit ParentClaimed(node, msg.sender);
    }

    /// @dev Registry owner, or — when the registry hands the name to a
    ///      wrapper contract — the wrapper's ERC-721 owner of the node.
    function _ownsNode(bytes32 node, address who) private view returns (bool) {
        if (address(ENS) == address(0)) revert NoRegistryHere();
        address o = ENS.owner(node);
        if (o == who) return true;
        if (o.code.length > 0) {
            (bool ok, bytes memory ret) = o.staticcall(
                abi.encodeWithSelector(INameWrapperLike.ownerOf.selector, uint256(node)));
            if (ok && ret.length == 32 && abi.decode(ret, (address)) == who) return true;
        }
        return false;
    }

    /*═══════════════════ resolution ═══════════════════*/

    function addr(bytes32 node) public view returns (address) {
        uint256 t = tokenOf[node];
        return t == 0 ? address(0) : HUB.account(t);
    }

    /// @notice Empty on purpose. This site is not on IPFS; it is the chain.
    ///         The record that matters is text("contentcontract"), which
    ///         ERC-6821 clients read before ever asking for a contenthash.
    function contenthash(bytes32) public pure returns (bytes memory) {
        return "";
    }

    function text(bytes32 node, string calldata key)
        external view returns (string memory)
    {
        return _text(tokenOf[node], key);
    }

    function _text(uint256 t, string memory key)
        private view returns (string memory)
    {
        bytes32 k = keccak256(bytes(key));
        /*  The one record that turns a name into this site. Chain-scoped
            per ERC-6821 (`w3q-default` would send every chain's traffic to
            one deployment; naming the chain sends each name to its own). */
        if (k == keccak256("contentcontract")) {
            return string.concat(
                "eip155:", block.chainid.str(), ":", LibNum.hexAddr(PREMISES));
        }
        if (t == 0) return "";
        if (k == keccak256("avatar")) {
            return string.concat(
                "eip155:", block.chainid.str(),
                "/erc721:", LibNum.hexAddr(address(HUB)), "/", t.str());
        }
        if (k == keccak256("url")) {
            string memory host = _gateway();
            /*  Where no gateway serves this chain there is no https URL to
                give, and inventing one would send every reader to a host
                that does not exist. The web3:// address is the real one
                either way; a native client needs nothing else.         */
            if (bytes(host).length == 0) {
                return string.concat(
                    "web3://", LibNum.hexAddr(PREMISES), ":", block.chainid.str(),
                    "/token/", t.str());
            }
            return string.concat(
                "https://", _bare(PREMISES), host, "/token/", t.str());
        }
        if (k == keccak256("description")) {
            return string.concat(
                "IPSEITY #", t.str(),
                " \xc2\xb7 a self-rendering instrument; its account is ",
                LibNum.hexAddr(HUB.account(t)));
        }
        return "";
    }

    /*═══════════════════ ENSIP-10 wildcards ═══════════════════*/

    /// @notice resolve(dns-encoded name, inner resolver call). Bound names
    ///         answer as themselves; `<id>.parent` answers for token <id>.
    function resolve(bytes calldata name, bytes calldata data)
        external view returns (bytes memory)
    {
        uint256 t = tokenOf[_namehash(name, 0)];
        if (t == 0 && parentNode != bytes32(0)) {
            (uint256 parsed, uint256 next, bool numeric) = _numericLabel(name);
            if (numeric && parsed > 0 && parsed <= HUB.totalSupply()
                && _namehash(name, next) == parentNode) t = parsed;
        }
        bytes4 sel = bytes4(data[:4]);
        if (sel == ADDR_IFACE) {
            return abi.encode(t == 0 ? address(0) : HUB.account(t));
        }
        if (sel == CONTENTHASH_IFACE) return abi.encode(bytes(""));
        if (sel == TEXT_IFACE) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            return abi.encode(_text(t, key));
        }
        revert UnknownQuery();
    }

    /// @notice Which token a DNS-encoded name means, bound or wildcard —
    ///         one call for a gateway to know whose page to serve.
    function tokenForName(bytes calldata name) external view returns (uint256) {
        uint256 t = tokenOf[_namehash(name, 0)];
        if (t != 0) return t;
        if (parentNode != bytes32(0)) {
            (uint256 parsed, uint256 next, bool numeric) = _numericLabel(name);
            if (numeric && parsed > 0 && parsed <= HUB.totalSupply()
                && _namehash(name, next) == parentNode) return parsed;
        }
        return 0;
    }

    /*═══════════════════ helpers ═══════════════════*/

    function _namehash(bytes calldata name, uint256 offset)
        private pure returns (bytes32)
    {
        uint256 len = uint8(name[offset]);
        if (len == 0) return bytes32(0);
        return keccak256(abi.encodePacked(
            _namehash(name, offset + len + 1),
            keccak256(name[offset + 1:offset + 1 + len])));
    }

    function _numericLabel(bytes calldata name)
        private pure returns (uint256 value, uint256 next, bool numeric)
    {
        uint256 len = uint8(name[0]);
        if (len == 0 || len > 18) return (0, 0, false);
        for (uint256 i = 1; i <= len; ++i) {
            uint8 c = uint8(name[i]);
            if (c < 0x30 || c > 0x39) return (0, 0, false);
            value = value * 10 + (c - 0x30);
        }
        return (value, len + 1, true);
    }

    /// @dev The premises address without its 0x, for gateway hostnames.
    function _bare(address a) private pure returns (string memory) {
        bytes memory h = bytes(LibNum.hexAddr(a));
        bytes memory out = new bytes(40);
        for (uint256 i; i < 40; ++i) out[i] = h[i + 2];
        return string(out);
    }

    /*  The w3link host tail for this chain, or empty where no gateway runs.

        Two corrections, both measured against DNS rather than assumed.
        Ethereum returned `.w3link.io`, and `<address>.w3link.io` does not
        resolve at all — the host needs the chain's short name in it, so
        mainnet is `.eth.w3link.io`. And the fallback returned that same
        dead tail for every chain not listed, which meant a deployment on a
        chain no gateway serves published a URL that cannot be opened.

        An unserved chain now returns empty and the caller says so. A
        collection whose whole argument is that it needs no server should
        not be the thing that prints a broken link.                      */
    function _gateway() private view returns (string memory) {
        uint256 c = block.chainid;
        if (c == 1)        return ".eth.w3link.io";
        if (c == 8453)     return ".base.w3link.io";
        if (c == 56)       return ".bnb.w3link.io";
        if (c == 11155111) return ".sep.w3link.io";
        if (c == 84532)    return ".basesep.w3link.io";
        return "";              // no public gateway serves this chain
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == ADDR_IFACE || id == CONTENTHASH_IFACE
            || id == TEXT_IFACE || id == WILDCARD_IFACE;
    }
}

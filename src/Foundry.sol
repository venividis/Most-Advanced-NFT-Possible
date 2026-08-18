// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*═══════════════════════════════════════════════════════════════════════════

  FOUNDRY — coins with nothing up their sleeve

  Every coin this contract pours is the same shape: a fixed supply, minted
  once, entirely to whoever asked. No owner. No mint function. No pause,
  no blacklist, no fee switch, no upgrade path. The customisation is in
  the launch — name, symbol, decimals, supply — not in the token as a
  permission somebody can exercise later.

  The launcher must hold one of the collection's tokens: a coin poured
  here is signed by a token, the way a message in the parley is, and the
  registry remembers which one. That is the whole gate — not curation,
  attribution.

═══════════════════════════════════════════════════════════════════════════*/

interface IHolds {
    function ownerOf(uint256 id) external view returns (address);
    function account(uint256 id) external view returns (address);
}
contract Coin {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public immutable totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error NotEnough();

    constructor(string memory n, string memory s, uint8 d, uint256 supply, address to) {
        name = n;
        symbol = s;
        decimals = d;
        totalSupply = supply;
        balanceOf[to] = supply;
        emit Transfer(address(0), to, supply);
    }

    function transfer(address to, uint256 v) external returns (bool) {
        return _move(msg.sender, to, v);
    }

    function approve(address spender, uint256 v) external returns (bool) {
        allowance[msg.sender][spender] = v;
        emit Approval(msg.sender, spender, v);
        return true;
    }

    function transferFrom(address from, address to, uint256 v) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) {
            if (a < v) revert NotEnough();
            unchecked { allowance[from][msg.sender] = a - v; }
        }
        return _move(from, to, v);
    }

    function _move(address from, address to, uint256 v) private returns (bool) {
        uint256 b = balanceOf[from];
        if (b < v) revert NotEnough();
        unchecked { balanceOf[from] = b - v; balanceOf[to] += v; }
        emit Transfer(from, to, v);
        return true;
    }
}

contract Foundry {
    IHolds public immutable HUB;

    uint256 public constant MAX_NAME = 40;
    uint256 public constant MAX_SYMBOL = 12;

    struct Launch {
        address coin;
        uint256 by;        // the token that poured it
        uint64  at;        // block timestamp
        uint8   decimals;
        uint256 supply;
    }

    Launch[] private _launches;

    event Poured(address indexed coin, uint256 indexed by, string name, string symbol, uint256 supply);

    error NotYours();
    error BadName();
    error BadSymbol();
    error NoSupply();

    constructor(IHolds hub) { HUB = hub; }

    function mayActAs(uint256 token, address who) public view returns (bool) {
        if (who == address(0)) return false;
        try HUB.ownerOf(token) returns (address o) {
            return who == o || who == HUB.account(token);
        } catch { return false; }
    }

    /// @notice Pour a coin. The whole supply lands in the caller's wallet,
    ///         and nothing about the coin can ever be changed by anyone.
    function pour(uint256 by, string calldata name, string calldata symbol,
                  uint8 decimals_, uint256 supply)
        external returns (address coin)
    {
        if (!mayActAs(by, msg.sender)) revert NotYours();
        if (bytes(name).length == 0 || bytes(name).length > MAX_NAME) revert BadName();
        if (bytes(symbol).length == 0 || bytes(symbol).length > MAX_SYMBOL) revert BadSymbol();
        if (supply == 0) revert NoSupply();

        coin = address(new Coin(name, symbol, decimals_, supply, msg.sender));
        _launches.push(Launch(coin, by, uint64(block.timestamp), decimals_, supply));
        emit Poured(coin, by, name, symbol, supply);
    }

    function count() external view returns (uint256) { return _launches.length; }

    function launchAt(uint256 i)
        external view
        returns (address coin, uint256 by, uint64 at, uint8 decimals_, uint256 supply)
    {
        Launch storage l = _launches[i];
        return (l.coin, l.by, l.at, l.decimals, l.supply);
    }

    /// @notice Newest first, a page at a time — the shape the coins tab reads.
    function recent(uint256 from, uint256 n)
        external view returns (address[] memory coins, uint256[] memory by)
    {
        uint256 total = _launches.length;
        if (from >= total) return (coins, by);
        uint256 take = n < total - from ? n : total - from;
        coins = new address[](take);
        by = new uint256[](take);
        for (uint256 i; i < take; ++i) {
            Launch storage l = _launches[total - 1 - from - i];
            coins[i] = l.coin;
            by[i] = l.by;
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GenericToken is ERC20 {
    uint8 private immutable underlyingDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        underlyingDecimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return underlyingDecimals;
    }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }
}

contract GenericTokenFactory {
    function deployToken(string calldata name, string calldata symbol, uint256 salt) external {
        new GenericToken{ salt: bytes32(salt) }(name, symbol, 18);
    }

    function deployTokenWithDecimal(string calldata name, string calldata symbol, uint256 salt, uint8 decimals) external {
        new GenericToken{ salt: bytes32(salt) }(name, symbol, decimals);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockxxxLon {
    address public lon;

    constructor(address _lon) {
        lon = _lon;
    }

    function mintFor(uint256 _amount, bytes calldata _encodeData) external {
        IERC20(lon).transferFrom(msg.sender, address(this), _amount);
    }
}

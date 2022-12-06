// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/interfaces/IMigrateStake.sol";

contract MockMigrateStake is IMigrateStake {
    address public lon;
    mapping(address => uint256) public balances;

    constructor(address _lon) {
        lon = _lon;
    }

    function mintFor(uint256 _amount, bytes calldata _encodeData) external override {
        // example scenario
        IERC20(lon).transferFrom(msg.sender, address(this), _amount);
        address user = abi.decode(_encodeData, (address));
        balances[user] = _amount;
    }
}

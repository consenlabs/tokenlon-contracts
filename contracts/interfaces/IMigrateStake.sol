// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IMigrateStake {
    function mintFor(uint256 _amount, bytes calldata _encodeData) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./TreasuryVester.sol";

contract TreasuryVesterFactory {
    IERC20 public lon;

    event VesterCreated(address indexed vester, address indexed recipient, uint256 vestingAmount);

    constructor(IERC20 _lon) {
        lon = _lon;
    }

    function createVester(
        address recipient,
        uint256 vestingAmount,
        uint256 vestingBegin,
        uint256 vestingCliff,
        uint256 vestingEnd
    ) external returns (address) {
        require(vestingAmount > 0, "vesting amount is zero");

        address vester = address(new TreasuryVester(address(lon), recipient, vestingAmount, vestingBegin, vestingCliff, vestingEnd));

        lon.transferFrom(msg.sender, vester, vestingAmount);

        emit VesterCreated(vester, recipient, vestingAmount);

        return vester;
    }
}

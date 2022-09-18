// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "contracts/test/veLON/Setup.t.sol";
import "contracts-test/mocks/MockERC20.sol";

import "contracts/veReward.sol";

contract TestVeReward is TestVeLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    MockERC20 rewardToken = new MockERC20("vr", "vr", 18);

    function testRewardAdd() public {
        veReward veRwd = new veReward(address(this), veLon, rewardToken);

        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        veRwd.addRewardForNextWeek(10000e18);
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);
        (uint256 reward, bool finished) = veRwd.getPendingRewardSingle(tokenId, 0);
        console.logUint(reward);
    }
}

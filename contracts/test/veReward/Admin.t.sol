// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/veReward/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestAdmin is TestVeReward {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testWithdrawFee() public {
        uint256 amount = 100;
        rewardToken.mint(address(veRwd), amount);
        BalanceSnapshot.Snapshot memory veRwdReward = BalanceSnapshot.take({ owner: address(veRwd), token: address(rewardToken) });
        BalanceSnapshot.Snapshot memory ownerReward = BalanceSnapshot.take({ owner: veRewardOwner, token: address(rewardToken) });

        vm.prank(veRewardOwner);
        veRwd.withdrawFee(amount);

        veRwdReward.assertChange(-int256(amount));
        ownerReward.assertChange(int256(amount));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "test/LONStaking/Setup.t.sol";

contract TestLONStakingRedeem is TestLONStaking {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotRedeemBeforeUnstake() public {
        vm.expectRevert("not yet unstake");
        vm.prank(user);
        lonStaking.redeem(1);
    }

    function testCannotRedeemBeforeCooldown() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        uint256 redeemAmount = lonStaking.balanceOf(user);
        vm.expectRevert("Still in cooldown");
        lonStaking.redeem(redeemAmount);
        vm.stopPrank();
    }

    function testCannotRedeemWithZeroAmount() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        vm.expectRevert("cannot redeem 0 share");
        lonStaking.redeem(0);
        vm.stopPrank();
    }

    function testCannotRedeemMoreThanOwned() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 invalidRedeemAmount = lonStaking.balanceOf(user) + 1;
        vm.expectRevert("ERC20: burn amount exceeds balance");
        lonStaking.redeem(invalidRedeemAmount);
        vm.stopPrank();
    }

    function testCannotRedeemAgain() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 redeemAmount = lonStaking.balanceOf(user);
        lonStaking.redeem(redeemAmount);

        vm.expectRevert("not yet unstake");
        lonStaking.redeem(redeemAmount);
        vm.stopPrank();
    }

    function testRedeemPartial() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 redeemAmount = lonStaking.balanceOf(user).div(2);
        _redeemAndValidate(user, redeemAmount);
    }

    function testRedeemAll() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();

        uint256 redeemAmount = lonStaking.balanceOf(user);
        _redeemAndValidate(user, redeemAmount);

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        assertEq(lonStaking.stakersCooldowns(user), 0, "Cooldown record reset when user redeem all shares");
    }

    function testRedeemWithBuyback() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        _simulateBuyback(100 * 1e18);

        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();

        uint256 redeemAmount = lonStaking.balanceOf(user);
        _redeemAndValidate(user, redeemAmount);

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
    }

    function testRedeemWhenPaused() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);
        lonStaking.pause();

        uint256 redeemAmount = lonStaking.balanceOf(user);
        vm.prank(user);
        lonStaking.redeem(redeemAmount / 2);
    }

    /*********************************
     *         Fuzz Testing          *
     *********************************/

    function testFuzz_RedeemPartial(uint256 stakeAmount, uint256 redeemAmount) public {
        stakeAmount = bound(stakeAmount, 2, lon.cap().sub(lon.totalSupply()));
        redeemAmount = bound(redeemAmount, 1, stakeAmount);

        lon.mint(user, stakeAmount);
        _stake(user, stakeAmount);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        _redeemAndValidate(user, redeemAmount);
    }

    function testFuzz_RedeemPartialOneByOneWithMultipleStake(uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts) public {
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 itemsLeft = stakeAmounts.length - i - 1;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount will all be zero and become invalid.
            // So an additional `2 * itemsLeft` is subtracted from the max value of the current stake amount
            // Also minimal stake amount is 2 because `1 <= redeemAmount < stakeAmount`
            stakeAmounts[i] = bound(stakeAmounts[i], 2, lon.cap().sub(totalLONAmount).sub(2 * itemsLeft));
            redeemAmounts[i] = bound(redeemAmounts[i], 1, stakeAmounts[i]);
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
        }

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            uint256 redeemAmount = redeemAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();

            vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

            _redeemAndValidate(staker, redeemAmount);
        }
    }

    function testFuzz_RedeemPartialOneTimeWithMultipleStake(uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts) public {
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 itemsLeft = stakeAmounts.length - i - 1;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount will all be zero and become invalid.
            // So an additional `2 * itemsLeft` is subtracted from the max value of the current stake amount
            // Also minimal stake amount is 2 because `1 <= redeemAmount < stakeAmount`
            stakeAmounts[i] = bound(stakeAmounts[i], 2, lon.cap().sub(totalLONAmount).sub(2 * itemsLeft));
            redeemAmounts[i] = bound(redeemAmounts[i], 1, stakeAmounts[i]);
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
        }

        // All stake and unstake
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();
        }
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);
        // All redeem
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 redeemAmount = redeemAmounts[i];

            _redeemAndValidate(staker, redeemAmount);
        }
    }

    function testFuzz_RedeemAll(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 2, lon.cap().sub(lon.totalSupply()));

        lon.mint(user, stakeAmount);
        _stake(user, stakeAmount);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 redeemAmount = lonStaking.balanceOf(user);
        _redeemAndValidate(user, redeemAmount);
    }

    function testFuzz_RedeemAllOneByOneWithMultipleStake(uint256[16] memory stakeAmounts) public {
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 itemsLeft = stakeAmounts.length - i - 1;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount will all be zero and become invalid.
            // So an additional `itemsLeft` is subtracted from the max value of the current stake amount
            stakeAmounts[i] = bound(stakeAmounts[i], 1, lon.cap().sub(totalLONAmount).sub(itemsLeft));
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
        }

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();

            vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

            uint256 redeemAmount = lonStaking.balanceOf(staker);
            _redeemAndValidate(staker, redeemAmount);
        }
    }

    function testFuzz_RedeemAllOneTimeWithMultipleStake(uint256[16] memory stakeAmounts) public {
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 itemsLeft = stakeAmounts.length - i - 1;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount will all be zero and become invalid.
            // So an additional `itemsLeft` is subtracted from the max value of the current stake amount
            stakeAmounts[i] = bound(stakeAmounts[i], 1, lon.cap().sub(totalLONAmount).sub(itemsLeft));
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
        }

        // All stake and unstake
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();
        }
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);
        // All redeem
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 redeemAmount = lonStaking.balanceOf(staker);
            _redeemAndValidate(staker, redeemAmount);
        }
    }

    function testFuzz_RedeemMultipleOneByOneWithBuyback(
        uint256[16] memory stakeAmounts,
        uint256[16] memory redeemAmounts,
        uint256[16] memory buybackAmounts
    ) public {
        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(makeAddr("initial_depositor"), 10_000_000e18);
        _stake(makeAddr("initial_depositor"), 10_000_000e18); // stake 10m LON

        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeItemsLeft = stakeAmounts.length - i - 1;
            uint256 buybackItemsLeft = buybackAmounts.length;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount and buyback amount will all be zero and become invalid.
            // So an additional `2 * stakeItemsLeft + buybackItemsLeft` is subtracted from the max value of the current stake amount
            // Also minimal stake amount is 2 because `1 <= redeemAmount < stakeAmount`
            stakeAmounts[i] = bound(stakeAmounts[i], 2, lon.cap().sub(totalLONAmount).sub(2 * stakeItemsLeft + buybackItemsLeft));
            redeemAmounts[i] = bound(redeemAmounts[i], 1, stakeAmounts[i]);
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
        }
        for (uint256 i = 0; i < buybackAmounts.length; i++) {
            uint256 itemsLeft = buybackAmounts.length - i - 1;
            // If buyback amount is set to `lon.cap().sub(totalLONAmount)`, rest of the buyback amount will all be zero and become invalid.
            // So an additional `itemsLeft` is subtracted from the max value of the current buyback amount
            buybackAmounts[i] = bound(buybackAmounts[i], 1, lon.cap().sub(totalLONAmount).sub(itemsLeft));
            totalLONAmount = totalLONAmount.add(buybackAmounts[i]);
        }

        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            uint256 redeemAmount = redeemAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            _simulateBuyback(buybackAmounts[i]);
            // Skip if stake did not get any share due to too small stakeAmount and rounding error
            if (lonStaking.balanceOf(staker) == 0) continue;

            vm.prank(staker);
            lonStaking.unstake();

            vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

            _redeemAndValidate(staker, redeemAmount);
        }
    }

    function testFuzz_RedeemMultipleOneTimeWithBuyback(
        uint256[16] memory stakeAmounts,
        uint256[16] memory redeemAmounts,
        uint256 buybackAmount
    ) public {
        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(makeAddr("initial_depositor"), 10_000_000e18);
        _stake(makeAddr("initial_depositor"), 10_000_000e18); // stake 10m LON

        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 itemsLeft = stakeAmounts.length - i;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount and buyback amount will all be zero and become invalid.
            // So an additional `2 * itemsLeft` is subtracted from the max value of the current stake amount
            // Also minimal stake amount is 2 because `1 <= redeemAmount < stakeAmount`
            stakeAmounts[i] = bound(stakeAmounts[i], 2, lon.cap().sub(totalLONAmount).sub(2 * itemsLeft));
            redeemAmounts[i] = bound(redeemAmounts[i], 1, stakeAmounts[i]);
            totalLONAmount = totalLONAmount.add(stakeAmounts[i]);
        }
        buybackAmount = uint80(bound(buybackAmount, 1, lon.cap().sub(totalLONAmount)));

        // All stake and unstake
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 stakeAmount = stakeAmounts[i];
            lon.mint(staker, stakeAmount);
            _stake(staker, stakeAmount);
            vm.prank(staker);
            lonStaking.unstake();
        }
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);
        _simulateBuyback(buybackAmount);
        // All redeem
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            address staker = address(uint256(fuzzingUserStartAddress) + i);
            uint256 redeemAmount = redeemAmounts[i];

            _redeemAndValidate(staker, redeemAmount);
        }
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _getExpectedLONWithoutPenalty(uint256 redeemShareAmount) internal view returns (uint256) {
        uint256 totalLon = lon.balanceOf(address(lonStaking));
        uint256 totalShares = lonStaking.totalSupply();
        return redeemShareAmount.mul(totalLon).div(totalShares);
    }

    function _redeemAndValidate(address redeemer, uint256 redeemAmount) internal {
        if (redeemAmount > lonStaking.balanceOf(redeemer)) redeemAmount = lonStaking.balanceOf(redeemer);
        bool redeemPartial = lonStaking.balanceOf(redeemer) > redeemAmount;
        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory redeemerXLON = BalanceSnapshot.take(redeemer, address(lonStaking));
        BalanceSnapshot.Snapshot memory redeemerLON = BalanceSnapshot.take(redeemer, address(lon));

        uint256 expectedLONAmount = _getExpectedLONWithoutPenalty(redeemAmount);
        vm.prank(redeemer);
        lonStaking.redeem(redeemAmount);

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        redeemerXLON.assertChange(-int256(redeemAmount));
        redeemerLON.assertChange(int256(expectedLONAmount));
        if (redeemPartial) {
            assertGt(lonStaking.stakersCooldowns(redeemer), 0, "Cooldown record remains until user redeem all shares");
        }
    }
}

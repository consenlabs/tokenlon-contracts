// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";

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
        vm.assume(stakeAmount > 0);
        vm.assume(redeemAmount > 0);
        vm.assume(redeemAmount < stakeAmount);
        vm.assume(stakeAmount <= lon.cap());
        vm.assume(stakeAmount.add(lon.totalSupply()) <= lon.cap());

        lon.mint(user, stakeAmount);
        _stake(user, stakeAmount);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        _redeemAndValidate(user, redeemAmount);
    }

    function testFuzz_RedeemPartialOneByOneWithMultipleStake(uint80[2][16] memory stakeAndRedeemAmounts) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        (uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts) = _determineStakeRedeemAmount(stakeAndRedeemAmounts);
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeAmount = stakeAmounts[i];
            uint256 redeemAmount = redeemAmounts[i];
            vm.assume(stakeAmount > 0);
            vm.assume(redeemAmount > 0);
            vm.assume(stakeAmount > redeemAmount);
            totalLONAmount = totalLONAmount.add(stakeAmount);
            vm.assume(totalLONAmount <= lon.cap());
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

    function testFuzz_RedeemPartialOneTimeWithMultipleStake(uint80[2][16] memory stakeAndRedeemAmounts) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        (uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts) = _determineStakeRedeemAmount(stakeAndRedeemAmounts);
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeAmount = stakeAmounts[i];
            uint256 redeemAmount = redeemAmounts[i];
            vm.assume(stakeAmount > 0);
            vm.assume(redeemAmount > 0);
            vm.assume(stakeAmount > redeemAmount);
            totalLONAmount = totalLONAmount.add(stakeAmount);
            vm.assume(totalLONAmount <= lon.cap());
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
        vm.assume(stakeAmount > 0);
        vm.assume(stakeAmount <= lon.cap());
        vm.assume(stakeAmount.add(lon.totalSupply()) <= lon.cap());

        lon.mint(user, stakeAmount);
        _stake(user, stakeAmount);
        vm.prank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 redeemAmount = lonStaking.balanceOf(user);
        _redeemAndValidate(user, redeemAmount);
    }

    function testFuzz_RedeemAllOneByOneWithMultipleStake(uint80[16] memory stakeAmounts) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeAmount = stakeAmounts[i];
            vm.assume(stakeAmount > 0);
            totalLONAmount = totalLONAmount.add(stakeAmount);
            vm.assume(totalLONAmount <= lon.cap());
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

    function testFuzz_RedeemAllOneTimeWithMultipleStake(uint80[16] memory stakeAmounts) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeAmount = stakeAmounts[i];
            vm.assume(stakeAmount > 0);
            totalLONAmount = totalLONAmount.add(stakeAmount);
            vm.assume(totalLONAmount <= lon.cap());
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

    function testFuzz_RedeemMultipleOneByOneWithBuyback(uint80[2][16] memory stakeAndRedeemAmounts, uint80[16] memory buybackAmounts) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        (uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts) = _determineStakeRedeemAmount(stakeAndRedeemAmounts);
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeAmount = stakeAmounts[i];
            uint256 redeemAmount = redeemAmounts[i];
            vm.assume(stakeAmount > 0);
            vm.assume(redeemAmount > 0);
            vm.assume(stakeAmount > redeemAmount);
            totalLONAmount = totalLONAmount.add(stakeAmount);
            vm.assume(totalLONAmount <= lon.cap());
        }
        for (uint256 i = 0; i < buybackAmounts.length; i++) {
            vm.assume(buybackAmounts[i] > 0);
            totalLONAmount = totalLONAmount.add(buybackAmounts[i]);
            vm.assume(totalLONAmount <= lon.cap());
        }

        // Make initial big enough deposit so LON amount will not increase dramatically relative to xLON amount due to buyback
        // and hence result in later staker getting zero shares
        lon.mint(address(0x5566), 10_000_000e18);
        _stake(address(0x5566), 10_000_000e18); // stake 10m LON

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

    function testFuzz_RedeemMultipleOneTimeWithBuyback(uint80[2][16] memory stakeAndRedeemAmounts, uint80 buybackAmount) public {
        // LON cap lies between 2**87 and 2**88, setting upper bound of stake amount to 2**80 - 1 so stake amount will not exceed cap
        uint256 totalLONAmount = lon.totalSupply();
        (uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts) = _determineStakeRedeemAmount(stakeAndRedeemAmounts);
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeAmount = stakeAmounts[i];
            uint256 redeemAmount = redeemAmounts[i];
            vm.assume(stakeAmount > 0);
            vm.assume(redeemAmount > 0);
            vm.assume(stakeAmount > redeemAmount);
            totalLONAmount = totalLONAmount.add(stakeAmount);
            vm.assume(totalLONAmount <= lon.cap());
        }
        vm.assume(buybackAmount > 0);
        vm.assume(totalLONAmount.add(buybackAmount) <= lon.cap());

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

    function _determineStakeRedeemAmount(uint80[2][16] memory stakeAndRedeemAmounts)
        internal
        pure
        returns (uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts)
    {
        for (uint256 i = 0; i < stakeAndRedeemAmounts.length; i++) {
            if (stakeAndRedeemAmounts[i][0] >= stakeAndRedeemAmounts[i][1]) {
                stakeAmounts[i] = stakeAndRedeemAmounts[i][0];
                redeemAmounts[i] = stakeAndRedeemAmounts[i][1];
            } else {
                stakeAmounts[i] = stakeAndRedeemAmounts[i][1];
                redeemAmounts[i] = stakeAndRedeemAmounts[i][0];
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/test/veLON/Setup.t.sol";
import "contracts/test/mocks/MockMigrateStake.sol";

contract TestVeLONDeposit is TestVeLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;
    using SafeMath for uint256;

    function testEnableAndDisableConversion() public {
        MockMigrateStake migrateStake = new MockMigrateStake(address(lon));
        uint256 penaltyRateBefore = veLon.earlyWithdrawPenaltyRate();

        assertEq(veLon.dstToken(), address(0x0));
        assertEq(veLon.conversion(), false);
        vm.prank(user);
        vm.expectRevert("conversion is not enabled");
        veLon.convert("some thing");

        // enable the conversion
        veLon.enableConversion(address(migrateStake));
        vm.prank(user);
        veLon.convert("some thing");

        assertEq(veLon.dstToken(), address(migrateStake));
        assertEq(veLon.conversion(), true);
        assertEq(veLon.earlyWithdrawPenaltyRate(), 0);

        // disable the conversion
        veLon.disableConversion();

        assertEq(veLon.dstToken(), address(0x0));
        assertEq(veLon.conversion(), false);
        assertEq(veLon.earlyWithdrawPenaltyRate(), penaltyRateBefore);

        vm.prank(user);
        vm.expectRevert("conversion is not enabled");
        veLon.convert("some thing");
    }

    function testConvertVeLontoMigrateStake() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        assertGt(tokenId, 0);
        _convertVeLontoMigrateStakeAndValidate(user, DEFAULT_STAKE_AMOUNT);
    }

    function _convertVeLontoMigrateStakeAndValidate(address staker, uint256 stakeAmount) internal {
        MockMigrateStake migrateStake = new MockMigrateStake(address(lon));
        BalanceSnapshot.Snapshot memory veLonLon = BalanceSnapshot.take(address(veLon), address(lon));
        BalanceSnapshot.Snapshot memory migrateStakeLon = BalanceSnapshot.take(address(migrateStake), address(lon));

        uint256 totalNftSupply = veLon.totalSupply();
        veLon.enableConversion(address(migrateStake));
        vm.prank(staker);
        uint256 convertedAmount = veLon.convert("some thing");

        veLonLon.assertChange(-int256(stakeAmount));
        migrateStakeLon.assertChange(int256(stakeAmount));
        assertEq(veLon.totalSupply() + 1, totalNftSupply);
        assertEq(convertedAmount, stakeAmount);
    }

    function testFuzz_ConvertVeLontoMigrateStake(uint256 lockTime, uint256 warp) public {
        uint256 stakeAmount = DEFAULT_STAKE_AMOUNT;
        vm.assume(lockTime >= 7 days);
        vm.assume(lockTime <= 50 days);
        vm.assume(warp > 0);
        vm.assume(warp <= 50 days);

        lon.mint(user, stakeAmount);

        uint256 tokenId = _stakeAndValidate(user, stakeAmount, lockTime);
        require(tokenId != 0, "No lock created yet");
        vm.warp(block.timestamp + warp);
        _convertVeLontoMigrateStakeAndValidate(user, stakeAmount);
    }
}

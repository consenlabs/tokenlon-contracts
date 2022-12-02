// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts-test/LONStaking/Setup.t.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestLONStakingConversion is TestLONStaking {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testEnableAndDisableConversion() public {
        _stake(user, DEFAULT_VELON_STAKE_AMOUNT);

        assertEq(address(lonStaking.veLon()), address(0x0));
        assertEq(lonStaking.conversion(), false);

        vm.prank(user);
        vm.expectRevert("conversion is not enabled");
        lonStaking.convert(abi.encode(DEFAULT_LOCK_TIME));

        // enable the conversion
        lonStaking.enableConversion(address(veLon));

        assertEq(address(lonStaking.veLon()), address(veLon));
        assertEq(lonStaking.conversion(), true);

        vm.prank(user);
        lonStaking.convert(abi.encode(DEFAULT_LOCK_TIME));

        // disable the conversion
        lonStaking.disableConversion();
        _stake(user, DEFAULT_VELON_STAKE_AMOUNT);

        assertEq(address(lonStaking.veLon()), address(0x0));
        assertEq(lonStaking.conversion(), false);

        vm.prank(user);
        vm.expectRevert("conversion is not enabled");
        lonStaking.convert(abi.encode(DEFAULT_LOCK_TIME));
    }

    function testConvertXLonToVeLon() public {
        // make sure `_calcPower` behave correctly.
        // decliningRate = 10, lock duration = 2 weeks (exactly)
        uint256 ts = (block.timestamp).div(1 weeks).mul(1 weeks);
        vm.warp(ts);
        assertEq(_calcPower(DEFAULT_LOCK_TIME, DEFAULT_VELON_STAKE_AMOUNT, 365 days), 2 * 10 weeks);

        _stake(user, DEFAULT_VELON_STAKE_AMOUNT);
        _convertXLonToVeLonAndValidate(DEFAULT_VELON_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
    }

    function testFuzz_ConvertXLonToVeLon(uint256 convertAmount, uint256 convertDuration) public {
        vm.assume(convertAmount > 0);
        vm.assume(convertAmount <= lon.cap());
        vm.assume(convertAmount.add(lon.totalSupply()) <= lon.cap());
        vm.assume(convertDuration >= 1 weeks);
        vm.assume(convertDuration <= 365 days);

        lon.mint(user, convertAmount);
        _stake(user, convertAmount);
        _convertXLonToVeLonAndValidate(convertAmount, convertDuration);
    }

    function _convertXLonToVeLonAndValidate(uint256 convertAmount, uint256 convertDuration) internal {
        BalanceSnapshot.Snapshot memory veLonLon = BalanceSnapshot.take(address(veLon), address(lon));
        BalanceSnapshot.Snapshot memory lonStakingLon = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLon = BalanceSnapshot.take(user, address(lonStaking));

        uint256 userXLonAmount = lonStaking.balanceOf(user);
        lonStaking.enableConversion(address(veLon));

        vm.prank(user);
        uint256 tokenId = lonStaking.convert(abi.encode(convertDuration));
        uint256 expectedPower = _calcPower(convertDuration, convertAmount, veLon.maxLockDuration());

        veLonLon.assertChange(int256(convertAmount));
        lonStakingLon.assertChange(-int256(convertAmount));
        userXLon.assertChange(-int256(userXLonAmount));

        assertGe(tokenId, 0);
        assertEq(veLon.vBalanceOf(tokenId), expectedPower);
        assertEq(veLon.totalvBalance(), expectedPower);
    }

    function _calcPower(
        uint256 _duration,
        uint256 _amount,
        uint256 _maxLockDuration
    ) internal returns (uint256) {
        uint256 lockEnd = _duration.add(block.timestamp).div(1 weeks).mul(1 weeks);
        uint256 power = _amount.div(_maxLockDuration).mul(lockEnd.sub(block.timestamp));
        return power;
    }
}

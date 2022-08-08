// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/test/veLON/Setup.t.sol";
import "contracts/test/mocks/MockxxxLon.sol";

contract TestVeLONDeposit is TestVeLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;
    using SafeMath for uint256;

    function testEnableAndDisableConversion() public {
        MockxxxLon xxxLon = new MockxxxLon(address(lon));
        uint256 penaltyRateBefore = veLon.earlyWithdrawPenaltyRate();

        assertEq(veLon.dstToken(), address(0x0));
        assertEq(veLon.conversion(), false);

        // enable the conversion
        veLon.enableConversion(address(xxxLon));

        assertEq(veLon.dstToken(), address(xxxLon));
        assertEq(veLon.conversion(), true);
        assertEq(veLon.earlyWithdrawPenaltyRate(), 0);

        // disable the conversion
        veLon.disableConversion();

        assertEq(veLon.dstToken(), address(0x0));
        assertEq(veLon.conversion(), false);
        assertEq(veLon.earlyWithdrawPenaltyRate(), penaltyRateBefore);
    }

    function testConvertVeLontoXXXLon() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        require(tokenId != 0, "No lock created yet");
        _convertVeLontoXXXLonAndValidate(user, DEFAULT_STAKE_AMOUNT);
    }

    function _convertVeLontoXXXLonAndValidate(address staker, uint256 stakeAmount) public {
        MockxxxLon xxxLon = new MockxxxLon(address(lon));
        BalanceSnapshot.Snapshot memory veLonLon = BalanceSnapshot.take(address(veLon), address(lon));
        BalanceSnapshot.Snapshot memory xxxLonLon = BalanceSnapshot.take(address(xxxLon), address(lon));

        uint256 totalNftSupply = veLon.totalSupply();
        veLon.enableConversion(address(xxxLon));
        vm.prank(staker);
        uint256 convertedAmount = veLon.convert("some thing");

        veLonLon.assertChange(-int256(stakeAmount));
        xxxLonLon.assertChange(int256(stakeAmount));
        assertEq(veLon.totalSupply() + 1, totalNftSupply);
        assertEq(convertedAmount, stakeAmount);
    }

    function testFuzz_ConvertVeLontoXXXLon(
        uint256 stakeAmount,
        uint256 lockTime,
        uint256 warp
    ) public {
        vm.assume(lockTime >= 7 days);
        vm.assume(lockTime <= 365 days);
        vm.assume(stakeAmount > 0);
        vm.assume(stakeAmount <= lon.cap());
        vm.assume(stakeAmount.add(lon.totalSupply()) <= lon.cap());
        vm.assume(warp > 0);
        vm.assume(warp <= 365 days);

        lon.mint(user, stakeAmount);

        uint256 tokenId = _stakeAndValidate(user, stakeAmount, lockTime);
        require(tokenId != 0, "No lock created yet");
        vm.warp(block.timestamp + warp);
        _convertVeLontoXXXLonAndValidate(user, stakeAmount);
    }
}

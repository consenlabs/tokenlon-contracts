// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/Lon.sol";
import "contracts/LONStaking.sol";
import "contracts/xLON.sol";
import "test/utils/BalanceSnapshot.sol";

contract TestLONStaking is Test {
    using SafeMath for uint256;

    uint256 constant MIN_STAKE_AMOUNT = 1;
    uint256 constant MIN_REDEEM_AMOUNT = 1;
    uint256 constant MIN_BUYBACK_AMOUNT = 1;
    uint256 constant COOLDOWN_IN_DAYS = 7;
    uint256 constant COOLDOWN_SECONDS = 7 days;
    uint256 constant BPS_RAGE_EXIT_PENALTY = 500;
    uint256 constant BPS_MAX = 10000;

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address other = vm.addr(otherPrivateKey);
    address upgradeAdmin = address(0x133701);
    address spender = address(0x133702);
    address fuzzingUserStartAddress = address(0x133703);

    Lon lon = new Lon(address(this), address(this));
    xLON xLon;
    LONStaking lonStaking;

    uint256 DEFAULT_STAKE_AMOUNT = 1e18;
    uint256 DEADLINE = block.timestamp + 1;

    // effectively a "beforeEach" block
    function setUp() public virtual {
        // Setup
        LONStaking lonStakingImpl = new LONStaking();
        bytes memory initData = abi.encodeWithSelector(
            LONStaking.initialize.selector,
            address(lon), // LON
            address(this), // Owner
            COOLDOWN_IN_DAYS,
            BPS_RAGE_EXIT_PENALTY
        );

        xLon = new xLON(address(lonStakingImpl), upgradeAdmin, initData);
        lonStaking = LONStaking(address(xLon));

        // Deal 100 ETH to user
        deal(user, 100 ether);
        // Mint LON to user
        lon.mint(user, 100 * 1e18);
        // User approve LONStaking
        vm.prank(user);
        lon.approve(address(lonStaking), type(uint256).max);

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(address(this), "TestingContract");
        vm.label(address(lon), "LONContract");
        vm.label(address(xLon), "xLONContract");
        vm.label(address(lonStakingImpl), "LONStakingImplementationContract");
        vm.label(address(lonStaking), "LONStakingContract");
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _getExpectedXLON(uint256 stakeAmount) internal view returns (uint256) {
        uint256 totalLon = lon.balanceOf(address(lonStaking));
        uint256 totalShares = lonStaking.totalSupply();
        if (totalShares == 0 || totalLon == 0) {
            return stakeAmount;
        } else {
            return stakeAmount.mul(totalShares).div(totalLon);
        }
    }

    function _stake(address staker, uint256 stakeAmount) internal {
        vm.startPrank(staker);
        if (lon.allowance(staker, address(lonStaking)) == 0) {
            lon.approve(address(lonStaking), type(uint256).max);
        }
        lonStaking.stake(stakeAmount);
        vm.stopPrank();
    }

    function _simulateBuyback(uint256 amount) internal {
        lon.mint(address(lonStaking), amount);
    }

    function _boundStakeAmounts(
        uint256[16] memory stakeAmounts,
        uint256 minStakeAmount,
        uint256 totalLONAmount
    ) internal returns (uint256[16] memory boundedStakeAmounts, uint256 newTotalLONAmount) {
        newTotalLONAmount = totalLONAmount;
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 numStakeAmountLeft = stakeAmounts.length - i - 1;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount will all be zero and become invalid.
            // So an additional `numStakeAmountLeft * minStakeAmount` is subtracted from the max value of the current stake amount
            boundedStakeAmounts[i] = bound(stakeAmounts[i], minStakeAmount, lon.cap().sub(newTotalLONAmount).sub(numStakeAmountLeft * minStakeAmount));
            newTotalLONAmount = newTotalLONAmount.add(boundedStakeAmounts[i]);
        }
    }

    function _boundStakeAndBuybackAmounts(
        uint256[16] memory stakeAmounts,
        uint256[16] memory buybackAmounts,
        uint256 minStakeAmount,
        uint256 totalLONAmount
    )
        internal
        returns (
            uint256[16] memory boundedStakeAmounts,
            uint256[16] memory boundedBuybackAmounts,
            uint256 newTotalLONAmount
        )
    {
        newTotalLONAmount = totalLONAmount;
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 numStakeAmountLeft = stakeAmounts.length - i - 1;
            uint256 numBuybackAmountLeft = buybackAmounts.length;
            // If stake amount is set to `lon.cap().sub(totalLONAmount)`, rest of the stake amount and buyback amount will all be zero and become invalid.
            // So an additional `numStakeAmountLeft * minStakeAmount + numBuybackAmountLeft * MIN_BUYBACK_AMOUNT` is subtracted from the max value of the current stake amount
            boundedStakeAmounts[i] = bound(
                stakeAmounts[i],
                minStakeAmount,
                lon.cap().sub(newTotalLONAmount).sub(numStakeAmountLeft * minStakeAmount + numBuybackAmountLeft * MIN_BUYBACK_AMOUNT)
            );
            newTotalLONAmount = newTotalLONAmount.add(boundedStakeAmounts[i]);
        }
        for (uint256 i = 0; i < buybackAmounts.length; i++) {
            uint256 numBuybackAmountLeft = buybackAmounts.length - i - 1;
            // If buyback amount is set to `lon.cap().sub(totalLONAmount)`, rest of the buyback amount will all be zero and become invalid.
            // So an additional `numBuybackAmountLeft * MIN_BUYBACK_AMOUNT` is subtracted from the max value of the current buyback amount
            boundedBuybackAmounts[i] = bound(
                buybackAmounts[i],
                MIN_BUYBACK_AMOUNT,
                lon.cap().sub(newTotalLONAmount).sub(numBuybackAmountLeft * MIN_BUYBACK_AMOUNT)
            );
            newTotalLONAmount = newTotalLONAmount.add(boundedBuybackAmounts[i]);
        }
    }

    function _boundRedeemAmounts(uint256[16] memory stakeAmounts, uint256[16] memory redeemAmounts) internal returns (uint256[16] memory boundedRedeemAmounts) {
        for (uint256 i = 0; i < redeemAmounts.length; i++) {
            boundedRedeemAmounts[i] = bound(redeemAmounts[i], MIN_REDEEM_AMOUNT, stakeAmounts[i]);
        }
    }
}

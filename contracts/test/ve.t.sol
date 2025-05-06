// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "contracts/Lon.sol";
import "contracts/ve.sol";
import "contracts/interfaces/ILon.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract VETest is Test {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 userPrivateKey = uint256(1);
    uint256 otherPricateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address other = vm.addr(otherPricateKey);

    Lon lon = new Lon(address(this), address(this));
    ve veLon;

    uint256 DEFAULT_STAKE_AMOUNT = 1e18;
    uint256 MAX_LOCK_TIME = 365 * 86400;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        veLon = new ve(address(lon));

        // Deal 100 ETH to user
        deal(user, 100 ether);
        // Mint LON to user
        lon.mint(user, 100 * 1e18);
        // User approve LONStaking
        vm.prank(user);
        lon.approve(address(veLon), type(uint256).max);

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(address(this), "TestingContract");
        vm.label(address(lon), "LONContract");
        vm.label(address(veLon), "veLONContract");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupVeLON() public {
        assertEq(veLon.owner(), address(this));
        assertEq(address(veLon.token()), address(lon));
        assertEq(veLon.epoch(), 0);
        assertEq(veLon.getMaxtime(), int128(MAX_LOCK_TIME));
        assertEq(veLon.supply(), 0);
        assertEq(veLon.totalNFTSupply(), 0);
    }

    /*********************************
     *         Test: stake           *
     *********************************/

    function _vePowerAdd(uint256 stakeAmount, uint256 lockDuration) internal returns (uint256) {
        uint256 unlockTime = ((block.timestamp + lockDuration) / 1 weeks) * 1 weeks; // Locktime is rounded down to weeks
        uint256 power = (stakeAmount / MAX_LOCK_TIME) * (unlockTime - block.timestamp);
        return power;
    }

    function _stakeAndValidate(
        address staker,
        uint256 stakeAmount,
        uint256 lockDuration
    ) internal returns (uint256) {
        BalanceSnapshot.Snapshot memory stakerLon = BalanceSnapshot.take(staker, address(lon));
        BalanceSnapshot.Snapshot memory veLonLon = BalanceSnapshot.take(address(veLon), address(lon));
        uint256 numberOfNftBefore = veLon.totalNFTSupply();
        uint256 totalVePowerBefore = veLon.totalSupply();
        vm.startPrank(staker);
        if (lon.allowance(staker, address(veLon)) == 0) {
            lon.approve(address(veLon), type(uint256).max);
        }
        uint256 tokenId = veLon.create_lock(stakeAmount, lockDuration);
        stakerLon.assertChange(-int256(stakeAmount));
        veLonLon.assertChange(int256(stakeAmount));
        assertEq(veLon.totalNFTSupply(), numberOfNftBefore + 1);
        uint256 increasedPower = _vePowerAdd(stakeAmount, lockDuration);
        assertEq(veLon.totalSupply(), totalVePowerBefore + increasedPower);
        assertEq(veLon.balanceOfNFT(tokenId), increasedPower);
        vm.stopPrank();

        return tokenId;
    }

    function testStake() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
    }

    function testEarlyWithdrawAfterStake() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);

        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        BalanceSnapshot.Snapshot memory veLonLon = BalanceSnapshot.take(address(veLon), address(lon));
        uint256 numberOfNftBefore = veLon.totalNFTSupply();
        uint256 totalVePowerBefore = veLon.totalSupply();
        uint256 nftPowerBefore = veLon.balanceOfNFT(tokenId);
        uint256 lonSupplyBefore = lon.totalSupply();

        vm.prank(user);
        veLon.emergencyWithdraw(tokenId);

        veLonLon.assertChange(-int256(DEFAULT_STAKE_AMOUNT));
        uint256 penalty = (DEFAULT_STAKE_AMOUNT * veLon.earlyWithdrawPenaltyRate()) / veLon.PENALTY_RATE_PRECISION();
        userLon.assertChange(int256(DEFAULT_STAKE_AMOUNT - penalty));
        assertEq(veLon.totalNFTSupply(), numberOfNftBefore - 1);
        assertEq(veLon.totalSupply(), totalVePowerBefore - nftPowerBefore);
        assertEq(lon.totalSupply(), lonSupplyBefore - penalty);
    }
}

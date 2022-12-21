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
}

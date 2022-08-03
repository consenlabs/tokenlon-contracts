// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "forge-std/Test.sol";
import "contracts/Lon.sol";
import "contracts/veLON.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestVeLON is Test {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;
    using SafeMath for uint256;

    address user = vm.addr(uint256(1));
    address bob = vm.addr(uint256(2));
    address alice = vm.addr(uint256(3));
    address other = vm.addr(uint256(4));

    Lon lon = new Lon(address(this), address(this));
    veLON veLon;

    // set default stake amount to 10 years in order to have integer initial vBalance easily
    uint256 constant DEFAULT_STAKE_AMOUNT = 10 * (365 days);
    uint256 constant DEFAULT_LOCK_TIME = 2 weeks;
    uint256 public constant PENALTY_RATE_PRECISION = 10000;

    // record the balnce of Lon and VeLon in VM
    BalanceSnapshot.Snapshot public stakerLon;
    BalanceSnapshot.Snapshot public lockedLon;

    function setUp() public {
        // Setup
        veLon = new veLON(address(lon));

        // deal eth and mint lon to user, approve lon to veLON
        deal(user, 100 ether);
        lon.mint(user, 100 * 1e18);
        vm.prank(user);
        lon.approve(address(veLon), type(uint256).max);

        // deal eth and mint lon to user, approve lon to veLON
        deal(bob, 100 ether);
        lon.mint(bob, 100 * 1e18);
        vm.prank(bob);
        lon.approve(address(veLon), type(uint256).max);

        // deal eth and mint lon to user, approve lon to veLON
        deal(alice, 100 ether);
        lon.mint(alice, 100 * 1e18);
        vm.prank(alice);
        lon.approve(address(veLon), type(uint256).max);

        // deal eth and mint lon to user, approve lon to veLON
        deal(other, 100 ether);
        lon.mint(other, 100 * 1e18);
        vm.prank(other);
        lon.approve(address(veLon), type(uint256).max);

        uint256 ts = (block.timestamp).div(1 weeks).mul(1 weeks);
        vm.warp(ts);

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(other, "Other");
        vm.label(address(this), "TestingContract");
        vm.label(address(lon), "LONContract");
        vm.label(address(veLon), "veLONContract");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupveLON() public {
        assertEq(veLon.owner(), address(this));
        assertEq(address(veLon.token()), address(lon));
        assertEq(veLon.tokenSupply(), 0);
        assertEq(veLon.maxLockDuration(), 365 days);
        assertEq(veLon.earlyWithdrawPenaltyRate(), 3000);
    }

    /*********************************
     *         Stake utils           *
     *********************************/
    // compute the initial voting power added when staking
    function _initialvBalance(uint256 stakeAmount, uint256 lockDuration) internal returns (uint256) {
        // Unlocktime is rounded down to weeks
        uint256 unlockTime = (block.timestamp.add(lockDuration)).mul(1 weeks).div(1 weeks);

        // Calculate declining rate first in order to get exactly vBalance as veLON has
        uint256 dRate = stakeAmount.div(veLon.maxLockDuration());
        uint256 vBalance = dRate.mul(unlockTime.sub(block.timestamp));
        return vBalance;
    }

    function _stakeAndValidate(
        address staker,
        uint256 stakeAmount,
        uint256 lockDuration
    ) internal returns (uint256) {
        vm.startPrank(staker);
        if (lon.allowance(staker, address(veLon)) == 0) {
            lon.approve(address(veLon), type(uint256).max);
        }
        uint256 tokenId = veLon.createLock(stakeAmount, lockDuration);
        vm.stopPrank();
        return tokenId;
    }
}

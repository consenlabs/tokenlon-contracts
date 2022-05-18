// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/Lon.sol";
import "contracts/LONStaking.sol";
import "contracts/xLON.sol";
import "contracts/interfaces/ILon.sol";
import "contracts-test/mocks/MockERC20.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/BalanceUtil.sol";

contract LONStakingTest is Test, BalanceUtil {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

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

    Lon lon;
    xLON xLon;
    LONStaking lonStaking;

    uint256 DEFAULT_STAKE_AMOUNT = 1e18;
    uint256 DEFAULT_BUYBACK_AMOUNT = 100 * 1e18;
    uint256 DEADLINE = block.timestamp + 1;

    struct StakeWithPermit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonces;
        uint256 deadline;
    }
    StakeWithPermit DEFAULT_STAKEWITHPERMIT;

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonces;
        uint256 deadline;
    }
    Permit DEFAULT_PERMIT;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        lon = new Lon(address(this), address(this));
        LONStaking lonStakingImpl = new LONStaking();
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint256,uint256)",
            address(lon), // LON
            address(this), // Owner
            COOLDOWN_IN_DAYS,
            BPS_RAGE_EXIT_PENALTY
        );

        xLon = new xLON(address(lonStakingImpl), upgradeAdmin, initData);
        lonStaking = LONStaking(address(xLon));

        // Deal 100 ETH to user
        vm.deal(user, 100 ether);
        // Mint LON to user
        lon.mint(user, 100 * 1e18);
        // User approve LONStaking
        vm.prank(user);
        lon.approve(address(lonStaking), type(uint256).max);

        // Default stakeWithPermit
        DEFAULT_STAKEWITHPERMIT = StakeWithPermit(
            user, // owner
            address(lonStaking), // spender
            DEFAULT_STAKE_AMOUNT, // value
            0, // nonce
            DEADLINE // deadline
        );

        // Default permit
        DEFAULT_PERMIT = Permit(
            user, // owner
            spender, // spender
            1e18, // value
            0, // nonce
            DEADLINE // deadline
        );

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(address(this), "TestingContract");
        vm.label(address(lon), "LONContract");
        vm.label(address(xLon), "xLONContract");
        vm.label(address(lonStakingImpl), "LONStakingImplementationContract");
        vm.label(address(lonStaking), "LONStakingContract");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupLONStaking() public {
        assertEq(lonStaking.owner(), address(this));
        assertEq(address(lonStaking.lonToken()), address(lon));
        assertEq(lonStaking.COOLDOWN_IN_DAYS(), COOLDOWN_IN_DAYS);
        assertEq(lonStaking.BPS_RAGE_EXIT_PENALTY(), BPS_RAGE_EXIT_PENALTY);
    }

    /*********************************
     *      Test: upgrade prxoy      *
     *********************************/

    function testCannotUpgradeByNonAdmin() public {
        vm.expectRevert();
        vm.prank(user);
        xLon.upgradeTo(address(lon));
    }

    function testUpgrade() public {
        vm.startPrank(upgradeAdmin);
        xLon.upgradeTo(address(lon));
        address newImpl = xLon.implementation();
        assertEq(newImpl, address(lon));
        vm.stopPrank();
    }

    /*********************************
     *        Test: initialize       *
     *********************************/

    function testCannotReinitialize() public {
        vm.expectRevert("Ownable already initialized");
        lonStaking.initialize(ILon(lon), user, COOLDOWN_IN_DAYS, BPS_RAGE_EXIT_PENALTY);
    }

    /*********************************
     *      Test: pause/unpause      *
     *********************************/

    function testCannotPauseByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        lonStaking.pause();
    }

    function testPause() public {
        lonStaking.pause();
        assertTrue(lonStaking.paused());
    }

    function testCannotUnpauseByNotOwner() public {
        lonStaking.pause();

        vm.expectRevert("not owner");
        vm.prank(user);
        lonStaking.unpause();
    }

    function testUnpause() public {
        lonStaking.pause();
        lonStaking.unpause();
        assertFalse(lonStaking.paused());
    }

    /*********************************
     *      Test: recoverERC20       *
     *********************************/

    function testCannotRecoverERC20ByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        lonStaking.recoverERC20(address(lon), 1e18);
    }

    function testCannotRecoverERC20WithLON() public {
        vm.expectRevert("cannot withdraw lon token");
        lonStaking.recoverERC20(address(lon), 1e18);
    }

    function testRecoverERC20() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        dai.mint(address(lonStaking), 1e18);
        BalanceSnapshot.Snapshot memory lonStakingDai = BalanceSnapshot.take(address(lonStaking), address(dai));
        BalanceSnapshot.Snapshot memory receiverDai = BalanceSnapshot.take(address(this), address(dai));
        lonStaking.recoverERC20(address(dai), 1e18);
        lonStakingDai.assertChange(-int256(1e18));
        receiverDai.assertChange(int256(1e18));
    }

    /************************************************
     *      Test: setCooldownAndRageExitParam       *
     ************************************************/

    function testCannotSetCooldownAndRageExitParamByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        lonStaking.setCooldownAndRageExitParam(COOLDOWN_IN_DAYS, BPS_RAGE_EXIT_PENALTY);
    }

    function testCannotSetCooldownAndRageExitParamWithInvalidParam() public {
        vm.expectRevert("COOLDOWN_IN_DAYS less than 1 day");
        lonStaking.setCooldownAndRageExitParam(0, BPS_RAGE_EXIT_PENALTY);
        vm.expectRevert("BPS_RAGE_EXIT_PENALTY larger than BPS_MAX");
        lonStaking.setCooldownAndRageExitParam(COOLDOWN_IN_DAYS, BPS_MAX + 1);
    }

    function testSetCooldownAndRageExitParam() public {
        lonStaking.setCooldownAndRageExitParam(COOLDOWN_IN_DAYS * 2, BPS_RAGE_EXIT_PENALTY * 2);
        assertEq(lonStaking.COOLDOWN_IN_DAYS(), COOLDOWN_IN_DAYS * 2);
        assertEq(lonStaking.BPS_RAGE_EXIT_PENALTY(), BPS_RAGE_EXIT_PENALTY * 2);
    }

    /*********************************
     *         Test: stake           *
     *********************************/

    function _getExpectedXLON(uint256 stakeAmount) internal returns (uint256) {
        uint256 totalLon = lon.balanceOf(address(lonStaking));
        uint256 totalShares = lonStaking.totalSupply();
        if (totalShares == 0 || totalLon == 0) {
            return stakeAmount;
        } else {
            return stakeAmount.mul(totalShares).div(totalLon);
        }
    }

    function testCannotStakeWithZeroAmount() public {
        vm.expectRevert("cannot stake 0 amount");
        lonStaking.stake(0);
    }

    function testCannotStakeWhenPaused() public {
        lonStaking.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        lonStaking.stake(DEFAULT_STAKE_AMOUNT);
    }

    function testStake() public {
        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        BalanceSnapshot.Snapshot memory lonStakingLon = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        uint256 stakeAmount = DEFAULT_STAKE_AMOUNT;
        uint256 expectedStakeAmount = _getExpectedXLON(stakeAmount);
        vm.prank(user);
        lonStaking.stake(stakeAmount);
        userLon.assertChange(-int256(stakeAmount));
        lonStakingLon.assertChange(int256(stakeAmount));
        userXLON.assertChange(int256(expectedStakeAmount));
    }

    /*********************************
     *     Test: stakeWithPermit     *
     *********************************/

    function testCannotStakeWithPermitWithExpiredPermit() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        stakeWithPermit.deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        vm.expectRevert("permit is expired");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    function testCannotStakeWithPermitWithInvalidUserSig() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(otherPrivateKey, stakeWithPermit);

        vm.expectRevert("invalid signature");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    function testCannotStakeWithPermitWhenPaused() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        lonStaking.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    function testStakeWithPermit() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        BalanceSnapshot.Snapshot memory lonStakingLon = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        uint256 stakeAmount = stakeWithPermit.value;
        uint256 expectedStakeAmount = _getExpectedXLON(stakeAmount);

        uint256 nonceBefore = lon.nonces(user);
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
        uint256 nonceAfter = lon.nonces(user);

        assertEq(nonceAfter, nonceBefore + 1);
        userLon.assertChange(-int256(stakeAmount));
        lonStakingLon.assertChange(int256(stakeAmount));
        userXLON.assertChange(int256(expectedStakeAmount));
    }

    function testCannotStakeWithPermitWithSameSignatureAgain() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);

        vm.expectRevert("invalid signature");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    /*********************************
     *        Test: unstake          *
     *********************************/

    function _stake(address staker, uint256 stakeAmount) internal {
        vm.startPrank(staker);
        if (lon.allowance(staker, address(lonStaking)) == 0) {
            lon.approve(address(lonStaking), type(uint256).max);
        }
        lonStaking.stake(stakeAmount);
        vm.stopPrank();
    }

    function testCannotUnstakeWithZeroAmount() public {
        vm.expectRevert("no share to unstake");
        vm.prank(other);
        lonStaking.unstake();
    }

    function testUnstake() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);

        assertEq(lonStaking.stakersCooldowns(user), 0);
        vm.prank(user);
        lonStaking.unstake();
        assertEq(lonStaking.stakersCooldowns(user), block.timestamp);
    }

    function testUnstakeWhenPaused() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);

        lonStaking.pause();

        assertEq(lonStaking.stakersCooldowns(user), 0);
        vm.prank(user);
        lonStaking.unstake();
        assertEq(lonStaking.stakersCooldowns(user), block.timestamp);
    }

    function testCannotUnstakeAgain() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);

        vm.prank(user);
        lonStaking.unstake();

        vm.expectRevert("already unstake");
        vm.prank(user);
        lonStaking.unstake();
    }

    /*********************************
     *         Test: redeem          *
     *********************************/

    function _getExpectedLONWithoutPenalty(uint256 redeemShareAmount) internal returns (uint256) {
        uint256 totalLon = lon.balanceOf(address(lonStaking));
        uint256 totalShares = lonStaking.totalSupply();
        return redeemShareAmount.mul(totalLon).div(totalShares);
    }

    function simulateBuyback(uint256 amount) internal {
        lon.mint(address(lonStaking), amount);
    }

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

    function testCannotRedeemMoreThanOneHas() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 invalidRedeemAmount = lonStaking.balanceOf(user) + 1;
        vm.expectRevert("ERC20: burn amount exceeds balance");
        lonStaking.redeem(invalidRedeemAmount);
        vm.stopPrank();
    }

    function testRedeemPartial() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        BalanceSnapshot.Snapshot memory userLON = BalanceSnapshot.take(user, address(lon));

        uint256 redeemAmount = lonStaking.balanceOf(user).div(2);
        uint256 expectedLONAmount = _getExpectedLONWithoutPenalty(redeemAmount);
        lonStaking.redeem(redeemAmount);
        vm.stopPrank();

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        userXLON.assertChange(-int256(redeemAmount));
        userLON.assertChange(int256(expectedLONAmount));
        assertGt(lonStaking.stakersCooldowns(user), 0, "Cooldown record remains until user redeem all shares");
    }

    function testRedeemAll() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        BalanceSnapshot.Snapshot memory userLON = BalanceSnapshot.take(user, address(lon));

        uint256 redeemAmount = lonStaking.balanceOf(user);
        uint256 expectedLONAmount = _getExpectedLONWithoutPenalty(redeemAmount);
        lonStaking.redeem(redeemAmount);
        vm.stopPrank();

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        userXLON.assertChange(-int256(redeemAmount));
        userLON.assertChange(int256(expectedLONAmount));
        assertEq(lonStaking.stakersCooldowns(user), 0, "Cooldown record reset when user redeem all shares");
    }

    function testRedeemWithBuyback() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        simulateBuyback(100 * 1e18);

        vm.startPrank(user);
        lonStaking.unstake();

        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        BalanceSnapshot.Snapshot memory userLON = BalanceSnapshot.take(user, address(lon));

        uint256 redeemAmount = lonStaking.balanceOf(user);
        uint256 expectedLONAmount = _getExpectedLONWithoutPenalty(redeemAmount);
        lonStaking.redeem(redeemAmount);
        vm.stopPrank();

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        userXLON.assertChange(-int256(redeemAmount));
        userLON.assertChange(int256(expectedLONAmount));
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

    /*********************************
     *         Test: rageExit        *
     *********************************/

    function testCannotRageExitBeforeUnstake() public {
        vm.expectRevert("not yet unstake");
        vm.prank(user);
        lonStaking.rageExit();
    }

    function testPreviewRageExitNoPenalty() public {
        _stake(user, 100);
        vm.prank(user);
        lonStaking.unstake();

        // rageExit after cooldown ends
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 redeemAmount = lonStaking.balanceOf(user);
        (uint256 expectedLONAmount, uint256 penaltyAmount) = lonStaking.previewRageExit(user);

        assertEq(penaltyAmount, 0);
        assertEq(expectedLONAmount, 100);
    }

    function testRageExitNoPenalty() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        // rageExit after cooldown ends
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        BalanceSnapshot.Snapshot memory userLON = BalanceSnapshot.take(user, address(lon));

        uint256 redeemAmount = lonStaking.balanceOf(user);
        (uint256 expectedLONAmount, ) = lonStaking.previewRageExit(user);
        lonStaking.rageExit();
        vm.stopPrank();

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        userXLON.assertChange(-int256(redeemAmount));
        userLON.assertChange(int256(expectedLONAmount));
    }

    function testPreviewRageExitWithPenalty() public {
        _stake(user, 100);
        vm.prank(user);
        lonStaking.unstake();

        // rageExit after cooldown ends
        vm.warp(block.timestamp + 2 days);

        (uint256 expectedLONAmount, uint256 penaltyAmount) = lonStaking.previewRageExit(user);

        // floor(100 * ((7 - 2 + 1) / 7) * (500 / 10000))
        // ((7 - 2 + 1) / 7): remaining days to cool down end
        // (500 / 10000): BPS_RAGE_EXIT_PENALTY / BPS_MAX
        assertEq(penaltyAmount, 4);
        // 100 - 4
        assertEq(expectedLONAmount, 96);
    }

    function testRageExitWithPenalty() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        vm.startPrank(user);
        lonStaking.unstake();

        // rageExit before cooldown ends
        vm.warp(block.timestamp + 2 days);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        BalanceSnapshot.Snapshot memory userLON = BalanceSnapshot.take(user, address(lon));

        uint256 redeemAmount = lonStaking.balanceOf(user);
        (uint256 expectedLONAmount, ) = lonStaking.previewRageExit(user);
        lonStaking.rageExit();
        vm.stopPrank();

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        userXLON.assertChange(-int256(redeemAmount));
        userLON.assertChange(int256(expectedLONAmount));
    }

    function testRageExitWithBuybackWithPenalty() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);
        simulateBuyback(100 * 1e18);

        vm.startPrank(user);
        lonStaking.unstake();

        // rageExit before cooldown ends
        vm.warp(block.timestamp + COOLDOWN_SECONDS / 5);

        uint256 lonStakingXLONBefore = lonStaking.totalSupply();
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        BalanceSnapshot.Snapshot memory userLON = BalanceSnapshot.take(user, address(lon));

        uint256 redeemAmount = lonStaking.balanceOf(user);
        (uint256 expectedLONAmount, ) = lonStaking.previewRageExit(user);
        lonStaking.rageExit();
        vm.stopPrank();

        uint256 lonStakingXLONAfter = lonStaking.totalSupply();
        assertEq(lonStakingXLONAfter, lonStakingXLONBefore - redeemAmount);
        lonStakingLON.assertChange(-int256(expectedLONAmount));
        userXLON.assertChange(-int256(redeemAmount));
        userLON.assertChange(int256(expectedLONAmount));
    }

    /*********************************
     *         Test: permit          *
     *********************************/

    function testCannotPermitByZeroAddress() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.owner = address(0);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("owner is zero address");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWithExpiredPermit() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("permit expired");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWithInvalidUserSig() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(otherPrivateKey, permit);

        vm.expectRevert("invalid signature");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testPermit() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        uint256 nonceBefore = lonStaking.nonces(user);
        uint256 allowanceBefore = lonStaking.allowance(permit.owner, permit.spender);
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
        uint256 nonceAfter = lonStaking.nonces(user);
        uint256 allowanceAfter = lonStaking.allowance(permit.owner, permit.spender);

        assertEq(nonceAfter, nonceBefore + 1);
        assertEq(allowanceAfter, allowanceBefore + permit.value);
    }

    function testCannotPermitWithSameSignatureAgain() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.expectRevert("invalid signature");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function _getStakeWithPermitHash(StakeWithPermit memory stakeWithPermit) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = lon.PERMIT_TYPEHASH();
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    stakeWithPermit.owner,
                    stakeWithPermit.spender,
                    stakeWithPermit.value,
                    stakeWithPermit.nonces,
                    stakeWithPermit.deadline
                )
            );
    }

    function _getLONEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 DOMAIN_SEPARATOR = lon.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, DOMAIN_SEPARATOR, structHash));
    }

    function _signStakeWithPermit(uint256 privateKey, StakeWithPermit memory stakeWithPermit)
        internal
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        bytes32 stakeWithPermitHash = _getStakeWithPermitHash(stakeWithPermit);
        bytes32 EIP712SignDigest = _getLONEIP712Hash(stakeWithPermitHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return (v, r, s);
    }

    function _getPermitHash(Permit memory permit) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = lonStaking.PERMIT_TYPEHASH();
        return keccak256(abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonces, permit.deadline));
    }

    function _getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 DOMAIN_SEPARATOR = lonStaking.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, DOMAIN_SEPARATOR, structHash));
    }

    function _signPermit(uint256 privateKey, Permit memory permit)
        internal
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        bytes32 permitHash = _getPermitHash(permit);
        bytes32 EIP712SignDigest = _getEIP712Hash(permitHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return (v, r, s);
    }
}

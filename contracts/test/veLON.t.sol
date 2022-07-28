// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "contracts/Lon.sol";
import "contracts/veLON.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract veLONTest is Test {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;
    using SafeMath for uint256;

    uint256 userPrivateKey = uint256(1);
    uint256 otherPricateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address other = vm.addr(otherPricateKey);

    Lon lon = new Lon(address(this), address(this));
    veLON veLon;

    uint256 constant DEFAULT_STAKE_AMOUNT = 1e18;
    uint256 constant MAX_LOCK_TIME = 365 days;
    uint256 public constant PENALTY_RATE_PRECISION = 10000;

    uint256 public earlyWithdrawPenaltyRate = 3000;

    //record the balnce of Lon and VeLon in VM
    BalanceSnapshot.Snapshot stakerLon;
    BalanceSnapshot.Snapshot lockedLon;

    function setUp() public {
        // Setup
        veLon = new veLON(address(lon));

        // Deal 100 ETH to user
        deal(user, 100 ether);
        // Mint LON to user
        lon.mint(user, 100 * 1e18);
        // User approve LONStaking
        vm.prank(user);
        lon.approve(address(veLon), type(uint256).max);

        // Deal 100 ETH to otherUSer
        deal(other, 100 ether);
        // Mint LON to otherUser
        lon.mint(other, 100 * 1e18);
        // User approve LONStaking
        vm.prank(other);
        lon.approve(address(veLon), type(uint256).max);

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
        assertEq(veLon.maxLockDuration(), MAX_LOCK_TIME);
        assertEq(veLon.earlyWithdrawPenaltyRate(), 3000);
    }

    /*********************************
     *         Test: stake           *
     *********************************/
    //compute the power added when staking amount added
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
        stakerLon = BalanceSnapshot.take(staker, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));
        // uint256 numberOfNftBefore = veLon.totalNFTSupply();
        // uint256 totalVePowerBefore = veLon.totalSupply();
        vm.startPrank(staker);
        if (lon.allowance(staker, address(veLon)) == 0) {
            lon.approve(address(veLon), type(uint256).max);
        }
        uint256 tokenId = veLon.createLock(stakeAmount, lockDuration);
        stakerLon.assertChange(-int256(stakeAmount));
        lockedLon.assertChange(int256(stakeAmount));
        // assertEq(veLon.totalNFTSupply(), numberOfNftBefore + 1);
        // // this part is weird
        // uint256 increasedPower = _vePowerAdd(stakeAmount, lockDuration);
        // assertEq(veLon.totalSupply(), totalVePowerBefore + increasedPower);
        // assertEq(veLon.balanceOfNFT(tokenId), increasedPower);
        vm.stopPrank();

        return tokenId;
    }

    /*********************************
     *         Test: deposit         *
     *********************************/
    function testCreateLock() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
    }

    function testFuzzCreateLock(uint256 _amount) public {
        vm.prank(user);
        vm.assume(_amount <= 100 * 1e18);
        vm.assume(_amount > 0);
        veLon.createLock(_amount, MAX_LOCK_TIME);
    }

    function testCannotCreateLockWithZero() public {
        vm.prank(user);
        vm.expectRevert("Zero lock amount");
        veLon.createLock(0, MAX_LOCK_TIME);
    }

    function testDepositFor() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        require(tokenId != 0, "No lock created yet");

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));
        vm.prank(user);
        veLon.depositFor(tokenId, 1);

        //TODO check if locked.amount and locked.end have increased
        stakerLon.assertChange(-(1));
        lockedLon.assertChange(1);

        vm.stopPrank();
    }

    function testDepositForByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.prank(other);
        veLon.depositFor(tokenId, 100);
    }

    function testFuzzDepositFor(uint256 _amount) public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.prank(user);
        vm.assume(_amount <= 50 * 1e18);
        vm.assume(_amount > 0);
        veLon.depositFor(tokenId, _amount);
    }

    function testExtendLock() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);
        uint256 lockEndBefore = veLon.unlockTime(tokenId);

        vm.prank(user);
        veLon.extendLock(tokenId, 2 weeks);
        uint256 lockEndAfter = veLon.unlockTime(tokenId);

        require((lockEndAfter - lockEndBefore) == 1 weeks, "wrong time extended");
    }

    function testCannoExtendLockExpired() public {
        uint256 lockTime = 1 weeks;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, lockTime);

        //pretend 1 week has passed and the lock expired
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(user);
        vm.expectRevert("Lock expired");
        veLon.extendLock(tokenId, lockTime);
    }

    function testMerge() public {
        uint256 _fromTokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);

        uint256 _toTokenId = _stakeAndValidate(other, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.prank(other);
        veLon.approve(address(user), _toTokenId);

        vm.prank(user);
        veLon.merge(_fromTokenId, _toTokenId);

        //check whether fromToken has burned
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(_fromTokenId);
    }

    /*********************************
     *         Test: Withdraw        *
     *********************************/

    function testWithdraw() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        //pretend 1 week has passed and the lock expired
        vm.prank(user);
        vm.warp(block.timestamp + 1 weeks);
        veLon.withdraw(tokenId);
        stakerLon.assertChange(int256(DEFAULT_STAKE_AMOUNT));
        lockedLon.assertChange(int256(-(DEFAULT_STAKE_AMOUNT)));

        //check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(tokenId);
    }

    function testWithdrawEarly() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);

        stakerLon = BalanceSnapshot.take(user, address(lon));
        lockedLon = BalanceSnapshot.take(address(veLon), address(lon));

        //pretend 1 week has passed and the lock not expired
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(user);
        veLon.withdrawEarly(tokenId);
        uint256 balanceChange = DEFAULT_STAKE_AMOUNT.mul(earlyWithdrawPenaltyRate).div(PENALTY_RATE_PRECISION);
        stakerLon.assertChange(int256(DEFAULT_STAKE_AMOUNT.sub(balanceChange)));

        //check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        veLon.ownerOf(tokenId);
    }

    function withdrawByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        vm.prank(user);
        veLon.approve(address(other), tokenId);
        vm.prank(other);
        veLon.withdraw(tokenId);
    }

    /*********************************
     *         Test: Transfer        *
     *********************************/
    function testTransferByOwner() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.startPrank(user);
        veLon.approve(other, tokenId);
        veLon.transferFrom(user, other, tokenId);
        vm.stopPrank();
        assertEq(veLon.ownerOf(tokenId), other);
    }

    function testTransferByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, MAX_LOCK_TIME);
        vm.prank(user);
        veLon.approve(other, tokenId);
        vm.prank(other);
        veLon.transferFrom(user, other, tokenId);
        vm.stopPrank();
        assertEq(veLon.ownerOf(tokenId), other);
    }
}

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

    uint256 userPrivateKey = uint256(1);
    uint256 otherPricateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address other = vm.addr(otherPricateKey);

    Lon lon = new Lon(address(this), address(this));
    veLON veLon;

    uint256 constant DEFAULT_STAKE_AMOUNT = 1e18;
    uint256 constant MAX_LOCK_TIME = 365 days;
    uint256 public constant PENALTY_RATE_PRECISION = 10000;

    // record the balnce of Lon and VeLon in VM
    BalanceSnapshot.Snapshot public stakerLon;
    BalanceSnapshot.Snapshot public lockedLon;

    function setUp() public {
        // Setup
        veLon = new veLON(address(lon));

        // Deal 100 ETH to user
        deal(user, 100 ether);
        // Mint LON to user
        lon.mint(user, 100 * 1e18);
        // User approve veLON
        vm.prank(user);
        lon.approve(address(veLon), type(uint256).max);

        // Deal 100 ETH to other user(second User)
        deal(other, 100 ether);
        // Mint LON to otherUser(second user)
        lon.mint(other, 100 * 1e18);
        // User approve veLON
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
    // compute the power added when staking amount added
    function _vePowerAdd(uint256 stakeAmount, uint256 lockDuration) internal returns (uint256) {
        // Unlocktime is rounded down to weeks
        uint256 unlockTime = ((block.timestamp + lockDuration) / 1 weeks) * 1 weeks;
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

        uint256 tokenMintBefore = veLon.totalSupply();
        uint256 tokenMintAfter;

        vm.startPrank(staker);
        if (lon.allowance(staker, address(veLon)) == 0) {
            lon.approve(address(veLon), type(uint256).max);
        }
        uint256 tokenId = veLon.createLock(stakeAmount, lockDuration);
        stakerLon.assertChange(-int256(stakeAmount));
        lockedLon.assertChange(int256(stakeAmount));

        // check whether ERC721 token has minted
        tokenMintAfter = veLon.totalSupply();
        assertEq((tokenMintBefore + 1), tokenMintAfter);

        // TODO check the voting power for NFT
        vm.stopPrank();

        return tokenId;
    }
}

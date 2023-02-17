// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "contracts/veLON.sol";
import "contracts/veReward.sol";
import "contracts/Lon.sol";
import "contracts/interfaces/IveLON.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/mocks/MockERC20.sol";

contract TestVeReward is Test {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    // FIXME constant 可以不要設定 visibility?
    uint256 constant DEFAULT_STAKE_AMOUNT = 10 * (365 days);
    uint256 constant DEFAULT_LOCK_TIME = 48 weeks;
    uint256 constant DEFAULT_TOTAL_REWARD = 10000e18;
    uint256 public constant DEFAULT_EPOCH_DURATION = 2500000; // RewardMultiplier / DURATION = 4

    address user = makeAddr("user");
    address veLONOnwer = makeAddr("veLONOnwer");
    address veRewardOwner = makeAddr("veRewardOwner");

    Lon lon = new Lon(address(this), address(this));
    veLON veLon = new veLON(veLONOnwer, address(lon));
    MockERC20 rewardToken = new MockERC20("Reward", "RWD", 18);
    veReward veRwd;

    function setUp() public {
        // Setup
        veRwd = new veReward(veRewardOwner, IveLON(veLon), IERC20(rewardToken));

        deal(user, 100 ether);
        lon.mint(user, 100 * 1e18);
        vm.prank(user);
        lon.approve(address(veLon), type(uint256).max);
    }

    function _stakeVE(
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

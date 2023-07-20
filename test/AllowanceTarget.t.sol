// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAllowanceTarget } from "contracts/interfaces/IAllowanceTarget.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { Ownable } from "contracts/abstracts/Ownable.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockDeflationaryERC20 } from "test/mocks/MockDeflationaryERC20.sol";
import { MockNoReturnERC20 } from "test/mocks/MockNoReturnERC20.sol";
import { MockNoRevertERC20 } from "test/mocks/MockNoRevertERC20.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";

contract AllowanceTargetTest is BalanceUtil {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for Snapshot;

    address user = makeAddr("user");
    address recipient = makeAddr("recipient");
    address authorized = makeAddr("authorized");
    address allowanceTargetOwner = makeAddr("allowanceTargetOwner");
    address[] trusted = [authorized];

    AllowanceTarget allowanceTarget;
    MockERC20 mockERC20 = new MockERC20("MockToken", "MTK", 18);
    MockDeflationaryERC20 deflationaryERC20 = new MockDeflationaryERC20();
    MockNoReturnERC20 noReturnERC20 = new MockNoReturnERC20();
    MockNoRevertERC20 noRevertERC20 = new MockNoRevertERC20();
    IERC20[] tokens = [IERC20(mockERC20), IERC20(address(deflationaryERC20)), IERC20(address(noReturnERC20)), IERC20(address(noRevertERC20))];

    // effectively a "beforeEach" block
    function setUp() public {
        // Deploy
        allowanceTarget = new AllowanceTarget(allowanceTargetOwner, trusted);

        // Set user's mock tokens balance and approve
        setTokenBalanceAndApprove(user, address(allowanceTarget), tokens, 100);

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(recipient, "Recipient");
        vm.label(authorized, "Authorized");
        vm.label(address(allowanceTarget), "AllowanceTarget");
        vm.label(address(mockERC20), "mockERC20");
        vm.label(address(deflationaryERC20), "deflationaryERC20");
        vm.label(address(noReturnERC20), "noReturnERC20");
        vm.label(address(noRevertERC20), "noRevertERC20");
    }

    function testCannotSpendFromUserByNotAuthorized() public {
        vm.expectRevert(IAllowanceTarget.NotAuthorized.selector);
        allowanceTarget.spendFromUserTo(user, address(mockERC20), recipient, 100);
    }

    function testCannotSpendFromUserInsufficientBalanceWithNoReturnValueToken() public {
        uint256 userBalance = noReturnERC20.balanceOf(user);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(authorized);
        allowanceTarget.spendFromUserTo(user, address(noReturnERC20), recipient, userBalance + 1);
    }

    function testCannotSpendFromUserInsufficientBalanceWithReturnFalseToken() public {
        uint256 userBalance = noRevertERC20.balanceOf(user);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        vm.prank(authorized);
        allowanceTarget.spendFromUserTo(user, address(noRevertERC20), recipient, userBalance + 1);
    }

    function testCannotPauseIfNotOwner() public {
        vm.expectRevert(Ownable.NotOwner.selector);
        allowanceTarget.pause();
    }

    function testCannotUnpauseIfNotOwner() public {
        vm.prank(allowanceTargetOwner, allowanceTargetOwner);
        allowanceTarget.pause();

        vm.expectRevert(Ownable.NotOwner.selector);
        allowanceTarget.unpause();
    }

    function testCannotSpendIfPaused() public {
        vm.prank(allowanceTargetOwner, allowanceTargetOwner);
        allowanceTarget.pause();

        vm.expectRevert("Pausable: paused");
        allowanceTarget.spendFromUserTo(user, address(mockERC20), recipient, 1234);
    }

    function testSpendFromUserTo() public {
        Snapshot memory fromBalance = BalanceSnapshot.take({ owner: user, token: address(mockERC20) });
        Snapshot memory toBalance = BalanceSnapshot.take({ owner: recipient, token: address(mockERC20) });

        uint256 amount = 100;
        vm.prank(authorized);
        allowanceTarget.spendFromUserTo(user, address(mockERC20), recipient, amount);

        fromBalance.assertChange(-int256(amount));
        toBalance.assertChange(int256(amount));
    }

    function testSpendFromUserToWithNoReturnValueToken() public {
        Snapshot memory fromBalance = BalanceSnapshot.take({ owner: user, token: address(noReturnERC20) });
        Snapshot memory toBalance = BalanceSnapshot.take({ owner: recipient, token: address(noReturnERC20) });

        uint256 amount = 100;
        vm.prank(authorized);
        allowanceTarget.spendFromUserTo(user, address(noReturnERC20), recipient, amount);

        fromBalance.assertChange(-int256(amount));
        toBalance.assertChange(int256(amount));
    }

    function testSpendFromUserToWithDeflationaryToken() public {
        Snapshot memory fromBalance = BalanceSnapshot.take({ owner: user, token: address(deflationaryERC20) });
        Snapshot memory toBalance = BalanceSnapshot.take({ owner: recipient, token: address(deflationaryERC20) });

        uint256 amount = 100;
        vm.prank(authorized);
        allowanceTarget.spendFromUserTo(user, address(deflationaryERC20), recipient, 100);

        uint256 expectedReceive = 99; // MockDeflationaryERC20 will burn 1% during each transfer
        fromBalance.assertChange(-int256(amount));
        toBalance.assertChange(int256(expectedReceive));
    }
}

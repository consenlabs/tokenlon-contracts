// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "@openzeppelin/contracts/utils/Address.sol";
import "contracts/AllowanceTarget.sol";
import "contracts-test/mocks/MockStrategy.sol";
import "contracts-test/mocks/MockERC20.sol";
import "contracts-test/utils/Addresses.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/StrategySharedSetup.sol";

contract AllowanceTargetTest is Test {
    using Address for address;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    address newSpender = address(new MockStrategy());
    address bob = address(0x133701);

    AllowanceTarget allowanceTarget;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        allowanceTarget = new AllowanceTarget(address(this));

        // Label addresses for easier debugging
        vm.label(address(this), "TestingContract");
        vm.label(address(allowanceTarget), "AllowanceTarget");
    }

    /*********************************
     *          test: setup          *
     *********************************/

    function testSetupAllowance() public {
        assertEq(allowanceTarget.spender(), address(this));
    }

    /*********************************
     *  test: setSpenderWithTimelock *
     *********************************/

    function testCantSetSpenderWithTimelockByRandomEOA() public {
        vm.prank(bob);
        vm.expectRevert("AllowanceTarget: not the spender");
        allowanceTarget.setSpenderWithTimelock(newSpender);
    }

    function testCantSetSpenderWithTimelockWithInvalidAddress() public {
        vm.expectRevert("AllowanceTarget: new spender not a contract");
        allowanceTarget.setSpenderWithTimelock(bob);
    }

    function testCantSetSpenderWithTimelockIfInProgress() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        address mySpender = address(new MockStrategy());
        vm.expectRevert("AllowanceTarget: SetSpender in progress");
        allowanceTarget.setSpenderWithTimelock(mySpender);
    }

    function testSetSpenderWithTimelock() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        assertEq(allowanceTarget.newSpender(), newSpender);
        assertEq(allowanceTarget.timelockExpirationTime(), block.timestamp + 1 days);
    }

    /*********************************
     *  test:   completeSetSpender   *
     *********************************/

    function testCantCompleteSetSpenderBeforeSet() public {
        vm.expectRevert("AllowanceTarget: no pending SetSpender");
        allowanceTarget.completeSetSpender();
    }

    function testCantCompleteSetSpenderTooEarly() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        vm.expectRevert("AllowanceTarget: time lock not expired yet");
        allowanceTarget.completeSetSpender();
    }

    function testCompleteSetSpender() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        // fast forward
        vm.warp(allowanceTarget.timelockExpirationTime());
        allowanceTarget.completeSetSpender();
        assertEq(allowanceTarget.spender(), newSpender);
    }

    /*********************************
     *         test: teardown        *
     *********************************/

    function testCantTeardownIfNotSpender() public {
        vm.prank(bob);
        vm.expectRevert("AllowanceTarget: not the spender");
        allowanceTarget.teardown();
    }

    function testTeardown() public {
        // Seems like the test contract itself have issue with receving ether.
        // So set spender to mock contract first.
        allowanceTarget.setSpenderWithTimelock(newSpender);
        // fast forward
        vm.warp(allowanceTarget.timelockExpirationTime());
        allowanceTarget.completeSetSpender();

        BalanceSnapshot.Snapshot memory beneficiary = BalanceSnapshot.take(address(newSpender), Addresses.ETH_ADDRESS);
        uint256 heritage = 10 ether;
        vm.deal(address(allowanceTarget), heritage);
        vm.prank(newSpender);
        allowanceTarget.teardown();
        beneficiary.assertChange(int256(heritage));
    }

    /*********************************
     *         test: executeCall     *
     *********************************/

    function testCantExecuteCallIfNotSpender() public {
        vm.prank(bob);
        vm.expectRevert("AllowanceTarget: not the spender");

        bytes memory data;
        allowanceTarget.executeCall(payable(address(newSpender)), data);
    }

    function testExecuteCall() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);
        BalanceSnapshot.Snapshot memory bobBalance = BalanceSnapshot.take(address(bob), address(token));

        // mint(address to, uint256 value)
        uint256 mintAmount = 1e18;
        allowanceTarget.executeCall(payable(address(token)), abi.encodeWithSelector(MockERC20.mint.selector, address(bob), mintAmount));
        bobBalance.assertChange(int256(mintAmount));
    }
}

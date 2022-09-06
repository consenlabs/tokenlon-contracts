// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/L2Deposit/Setup.t.sol";

contract TestL2DepositSetup is TestL2Deposit {
    function testSetupL2Deposit() public {
        assertEq(l2Deposit.owner(), address(this));
        assertEq(l2Deposit.userProxy(), address(userProxy));
        assertEq(address(l2Deposit.spender()), address(spender));
        assertEq(address(l2Deposit.permStorage()), address(permanentStorage));
        assertEq(address(l2Deposit.arbitrumL1GatewayRouter()), address(arbitrumL1GatewayRouter));
        assertEq(address(l2Deposit.arbitrumL1Inbox()), address(arbitrumL1Inbox));
        assertEq(address(l2Deposit.optimismL1StandardBridge()), address(optimismL1StandardBridge));
    }
}

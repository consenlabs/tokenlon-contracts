// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/forkMainnet/AMMStrategy/Setup.t.sol";

contract TestAMMStrategySetup is TestAMMStrategy {
    function testTokensAllowanceAmountWhenSetup() public {
        assertGt(entryPoint.balance, 0);
        assertGt(owner.balance, 0);
        for (uint256 i = 0; i < tokens.length; i++) {
            assertGt(tokens[i].balanceOf(entryPoint), 0);
        }
    }

    function testAMMStrategySetup() public {
        assertEq(ammStrategy.owner(), owner);
        assertEq(ammStrategy.entryPoint(), entryPoint);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "test/forkMainnet/AMMStrategy/Setup.t.sol";

contract TestAMMStrategySetup is TestAMMStrategy {
    function testTokensAllowanceAmountWhenSetup() public {
        assertGt(entryPoint.balance, 0);
        assertGt(owner.balance, 0);
        for (uint256 i = 0; i < tokens.length; ++i) {
            assertGt(IERC20(assets[i]).balanceOf(entryPoint), 0);
            for (uint256 j = 0; j < amms.length; ++j) {
                uint256 approveAmount = IERC20(assets[i]).allowance(address(ammStrategy), amms[j]);
                assertEq(approveAmount, type(uint256).max);
            }
        }
    }

    function testAMMStrategySetup() public {
        assertEq(ammStrategy.owner(), owner);
        assertEq(ammStrategy.entryPoint(), entryPoint);
    }
}

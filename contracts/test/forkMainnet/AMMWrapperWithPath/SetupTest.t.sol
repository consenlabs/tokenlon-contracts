// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";

contract TestAMMWrapperWithPathSetup is TestAMMWrapperWithPath {
    function testTokensAllowanceAmountWhenSetup() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testAMMWrapperWithPathSetup() public {
        assertEq(ammWrapperWithPath.operator(), address(this));
        assertEq(uint256(ammWrapperWithPath.defaultFeeFactor()), uint256(DEFAULT_FEE_FACTOR));
        assertEq(ammWrapperWithPath.userProxy(), address(userProxy));
        assertEq(address(ammWrapperWithPath.spender()), address(spender));
        assertEq(ammWrapperWithPath.feeCollector(), feeCollector);
        assertEq(userProxy.ammWrapperAddr(), address(ammWrapperWithPath));
        assertEq(permanentStorage.ammWrapperAddr(), address(ammWrapperWithPath));
        assertTrue(spender.isAuthorized(address(ammWrapperWithPath)));
        assertTrue(permanentStorage.isRelayerValid(relayer));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperSetup is TestAMMWrapper {
    function testTokensAllowanceAmountWhenSetup() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testAMMWrapperSetup() public {
        // Check fork mainnet addresses are not zero addresses
        assertTrue(uint160(UNISWAP_V2_ADDRESS) != 0);
        assertTrue(uint160(UNISWAP_V3_ADDRESS) != 0);
        assertTrue(uint160(UNISWAP_V3_QUOTER_ADDRESS) != 0);
        assertTrue(uint160(SUSHISWAP_ADDRESS) != 0);
        assertTrue(uint160(BALANCER_V2_ADDRESS) != 0);
        assertTrue(uint160(CURVE_ANKRETH_POOL_ADDRESS) != 0);
        assertTrue(uint160(WETH_ADDRESS) != 0);
        assertTrue(uint160(DAI_ADDRESS) != 0);
        assertTrue(uint160(USDT_ADDRESS) != 0);
        assertTrue(uint160(ANKRETH_ADDRESS) != 0);

        assertEq(ammWrapper.owner(), owner);
        assertEq(uint256(ammWrapper.defaultFeeFactor()), uint256(DEFAULT_FEE_FACTOR));
        assertEq(ammWrapper.userProxy(), address(userProxy));
        assertEq(address(ammWrapper.spender()), address(spender));
        assertEq(ammWrapper.feeCollector(), feeCollector);
        assertEq(userProxy.ammWrapperAddr(), address(ammWrapper));
        assertEq(permanentStorage.ammWrapperAddr(), address(ammWrapper));
        assertTrue(spender.isAuthorized(address(ammWrapper)));
        assertTrue(permanentStorage.isRelayerValid(relayer));
    }
}

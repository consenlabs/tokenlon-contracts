// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";

contract TestAMMWrapperWithPathSetup is TestAMMWrapperWithPath {
    function testTokensAllowanceAmountWhenSetup() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testAMMWrapperWithPathSetup() public {
        // Check fork mainnet addresses are not zero addresses
        assertTrue(UNISWAP_V2_ADDRESS != address(0));
        assertTrue(UNISWAP_V3_ADDRESS != address(0));
        assertTrue(UNISWAP_V3_QUOTER_ADDRESS != address(0));
        assertTrue(SUSHISWAP_ADDRESS != address(0));
        assertTrue(BALANCER_V2_ADDRESS != address(0));
        assertTrue(CURVE_USDT_POOL_ADDRESS != address(0));
        assertTrue(CURVE_TRICRYPTO2_POOL_ADDRESS != address(0));
        assertTrue(WETH_ADDRESS != address(0));
        assertTrue(DAI_ADDRESS != address(0));
        assertTrue(USDT_ADDRESS != address(0));
        assertTrue(USDC_ADDRESS != address(0));
        assertTrue(WBTC_ADDRESS != address(0));

        assertEq(ammWrapperWithPath.owner(), owner);
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

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/forkMainnet/AMMWrapperWithPath/Setup.t.sol";
import "contracts-test/utils/AMMUtil.sol";
import "contracts/AMMQuoter.sol";

contract TestAMMWrapperWithPathEvent is TestAMMWrapperWithPath {
    event Swapped(AMMWrapperWithPath.TxMetaData, AMMLibEIP712.Order order);

    AMMQuoter ammQuoter;

    // Override the "beforeEach" block
    function setUp() public override {
        TestAMMWrapperWithPath.setUp();

        ammQuoter = new AMMQuoter(IPermanentStorage(permanentStorage), address(weth));
    }

    function testEmitSwappedEvent() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, makerSpecificData, path);
        // Set subsidy factor to 0
        ammWrapperWithPath.setSubsidyFactor(uint256(0));

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
            order.makerAddr,
            order.takerAssetAddr,
            order.makerAssetAddr,
            order.takerAssetAmount,
            path,
            makerSpecificData
        );
        vm.expectEmit(false, false, false, true);
        AMMWrapperWithPath.TxMetaData memory txMetaData = AMMWrapper.TxMetaData(
            "Uniswap V3", // source
            AMMLibEIP712._getOrderHash(order), // transactionHash
            expectedOutAmount, // settleAmount: no fee so settled amount is the same as received amount
            expectedOutAmount, // receivedAmount
            uint16(feeFactor), // Fee factor: 0
            uint16(0) // Subsidy factor: 0
        );
        emit Swapped(txMetaData, order);
        userProxy.toAMM(payload);
    }
}

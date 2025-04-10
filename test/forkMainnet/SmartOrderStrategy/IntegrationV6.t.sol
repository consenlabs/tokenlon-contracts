// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts@v5.0.2/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts@v5.0.2/token/ERC20/utils/SafeERC20.sol";

import { SmartOrderStrategyTest } from "./Setup.t.sol";

import { LimitOrderSwap } from "contracts/LimitOrderSwap.sol";
import { LimitOrderSwap } from "contracts/LimitOrderSwap.sol";
import { RFQ } from "contracts/RFQ.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { LimitOrder } from "contracts/libraries/LimitOrder.sol";
import { RFQOffer } from "contracts/libraries/RFQOffer.sol";
import { RFQTx } from "contracts/libraries/RFQTx.sol";

import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { SigHelper } from "test/utils/SigHelper.sol";

contract IntegrationV6Test is SmartOrderStrategyTest, SigHelper {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for Snapshot;

    bytes4 public constant RFQ_FILL_SELECTOR = 0x6344a774;
    uint256 private constant FLG_ALLOW_CONTRACT_SENDER = 1 << 255;

    address owner = makeAddr("owner");
    uint256 makerPrivateKey = uint256(4679);
    address maker = vm.addr(makerPrivateKey);
    bytes defaultPermit = abi.encodePacked(TokenCollector.Source.Token);
    uint256 defaultSalt = 1234;
    RFQ rfq;
    LimitOrderSwap limitOrderSwap;

    function setUp() public override {
        super.setUp();

        rfq = new RFQ(owner, UNISWAP_PERMIT2_ADDRESS, makeAddr("allowanceTarget"), IWETH(WETH_ADDRESS), payable(owner));
        limitOrderSwap = new LimitOrderSwap(owner, UNISWAP_PERMIT2_ADDRESS, makeAddr("allowanceTarget"), IWETH(WETH_ADDRESS), payable(owner));

        // strategy approves RFQ & LO
        address[] memory spenders = new address[](2);
        spenders[0] = address(rfq);
        spenders[1] = address(limitOrderSwap);
        vm.startPrank(strategyOwner);
        smartOrderStrategy.approveTokens(tokenList, spenders);
        vm.stopPrank();

        // maker approves RFQ & LO
        setTokenBalanceAndApprove(maker, address(rfq), tokens, 100000);
        setTokenBalanceAndApprove(maker, address(limitOrderSwap), tokens, 100000);
    }

    function testV6RFQIntegration() public {
        RFQOffer memory rfqOffer = RFQOffer({
            taker: address(smartOrderStrategy),
            maker: payable(maker),
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: LON_ADDRESS,
            makerTokenAmount: 1000 ether,
            feeFactor: 0,
            flags: FLG_ALLOW_CONTRACT_SENDER,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        uint256 realChangedInGS = rfqOffer.makerTokenAmount - 1; // leaving 1 wei in GS

        RFQTx memory rfqTx = RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: rfqOffer.takerTokenAmount, recipient: payable(address(smartOrderStrategy)) });
        bytes memory makerSig = signRFQOffer(makerPrivateKey, rfqOffer, address(rfq));
        bytes memory rfqData = abi.encodeWithSelector(RFQ_FILL_SELECTOR, rfqTx, makerSig, defaultPermit, defaultPermit);

        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: address(rfq),
            inputToken: rfqOffer.takerToken,
            ratioNumerator: 0, // zero ratio indicate no replacement
            ratioDenominator: 0,
            dataOffset: 0,
            value: 0,
            data: rfqData
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        IERC20(rfqOffer.takerToken).safeTransfer(address(smartOrderStrategy), rfqOffer.takerTokenAmount);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), rfqOffer.takerToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, rfqOffer.makerToken);
        smartOrderStrategy.executeStrategy(rfqOffer.makerToken, opsData);
        vm.stopPrank();
        vm.snapshotGasLastCall("SmartOrderStrategy", "executeStrategy(): testV6RFQIntegration");

        sosInputToken.assertChange(-int256(rfqOffer.takerTokenAmount));
        gsOutputToken.assertChange(int256(realChangedInGS));
    }

    function testV6RFQIntegrationWhenTakerTokenIsETH() public {
        RFQOffer memory rfqOffer = RFQOffer({
            taker: address(smartOrderStrategy),
            maker: payable(maker),
            takerToken: Constant.ETH_ADDRESS,
            takerTokenAmount: 1 ether,
            makerToken: LON_ADDRESS,
            makerTokenAmount: 1000 ether,
            feeFactor: 0,
            flags: FLG_ALLOW_CONTRACT_SENDER,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        uint256 realChangedInGS = rfqOffer.makerTokenAmount - 1; // leaving 1 wei in GS

        RFQTx memory rfqTx = RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: rfqOffer.takerTokenAmount, recipient: payable(address(smartOrderStrategy)) });
        bytes memory makerSig = signRFQOffer(makerPrivateKey, rfqOffer, address(rfq));
        bytes memory rfqData = abi.encodeWithSelector(RFQ_FILL_SELECTOR, rfqTx, makerSig, defaultPermit, defaultPermit);

        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: address(rfq),
            inputToken: rfqOffer.takerToken,
            ratioNumerator: 0, // zero ratio indicate no replacement
            ratioDenominator: 0,
            dataOffset: 0,
            value: rfqOffer.takerTokenAmount,
            data: rfqData
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), rfqOffer.takerToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, rfqOffer.makerToken);
        smartOrderStrategy.executeStrategy{ value: rfqOffer.takerTokenAmount }(rfqOffer.makerToken, opsData);
        vm.stopPrank();
        vm.snapshotGasLastCall("SmartOrderStrategy", "executeStrategy(): testV6RFQIntegrationWhenTakerTokenIsETH");

        sosInputToken.assertChange(0);
        gsOutputToken.assertChange(int256(realChangedInGS));
    }

    function testV6RFQIntegrationWhenMakerTokenIsETH() public {
        RFQOffer memory rfqOffer = RFQOffer({
            taker: address(smartOrderStrategy),
            maker: payable(maker),
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: Constant.ETH_ADDRESS,
            makerTokenAmount: 1 ether,
            feeFactor: 0,
            flags: FLG_ALLOW_CONTRACT_SENDER,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        RFQTx memory rfqTx = RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: rfqOffer.takerTokenAmount, recipient: payable(address(smartOrderStrategy)) });
        bytes memory makerSig = signRFQOffer(makerPrivateKey, rfqOffer, address(rfq));
        bytes memory rfqData = abi.encodeWithSelector(RFQ_FILL_SELECTOR, rfqTx, makerSig, defaultPermit, defaultPermit);

        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: address(rfq),
            inputToken: rfqOffer.takerToken,
            ratioNumerator: 0, // zero ratio indicate no replacement
            ratioDenominator: 0,
            dataOffset: 0,
            value: 0,
            data: rfqData
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        IERC20(rfqOffer.takerToken).safeTransfer(address(smartOrderStrategy), rfqOffer.takerTokenAmount);
        smartOrderStrategy.executeStrategy(rfqOffer.makerToken, opsData);
        vm.stopPrank();
        vm.snapshotGasLastCall("SmartOrderStrategy", "executeStrategy(): testV6RFQIntegrationWhenMakerTokenIsETH");
    }

    function testV6LOIntegration() public {
        LimitOrder memory order = LimitOrder({
            taker: address(0),
            maker: payable(maker),
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 10 ether,
            makerTokenPermit: defaultPermit,
            feeFactor: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        uint256 realChangedInGS = order.makerTokenAmount - 1; // leaving 1 wei in GS

        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));
        ILimitOrderSwap.TakerParams memory takerParams = ILimitOrderSwap.TakerParams({
            takerTokenAmount: order.takerTokenAmount,
            makerTokenAmount: order.makerTokenAmount,
            recipient: address(smartOrderStrategy),
            extraAction: bytes(""),
            takerTokenPermit: defaultPermit
        });
        bytes memory loData = abi.encodeWithSelector(LimitOrderSwap.fillLimitOrderFullOrKill.selector, order, makerSig, takerParams);

        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: address(limitOrderSwap),
            inputToken: order.takerToken,
            ratioNumerator: 0, // zero ratio indicate no replacement
            ratioDenominator: 0,
            dataOffset: 0,
            value: 0,
            data: loData
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        IERC20(order.takerToken).safeTransfer(address(smartOrderStrategy), order.takerTokenAmount);
        Snapshot memory sosInputToken = BalanceSnapshot.take(address(smartOrderStrategy), order.takerToken);
        Snapshot memory gsOutputToken = BalanceSnapshot.take(genericSwap, order.makerToken);
        smartOrderStrategy.executeStrategy(order.makerToken, opsData);
        vm.stopPrank();
        vm.snapshotGasLastCall("SmartOrderStrategy", "executeStrategy(): testV6LOIntegration");

        sosInputToken.assertChange(-int256(order.takerTokenAmount));
        gsOutputToken.assertChange(int256(realChangedInGS));
    }
}

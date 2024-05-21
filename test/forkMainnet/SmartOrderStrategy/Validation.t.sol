// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { SmartOrderStrategyTest } from "./Setup.t.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";

contract ValidationTest is SmartOrderStrategyTest {
    function testCannotExecuteNotFromGenericSwap() public {
        vm.expectRevert(ISmartOrderStrategy.NotFromGS.selector);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, defaultOpsData);
    }

    function testCannotExecuteWithZeroInputAmount() public {
        vm.expectRevert(ISmartOrderStrategy.ZeroInput.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, 0, defaultOpsData);
    }

    function testCannotExecuteWithZeroRatioDenominatorWhenRatioNumeratorIsNonZero() public {
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0].inputToken = USDC_ADDRESS;
        operations[0].ratioNumerator = 1;
        operations[0].ratioDenominator = 0;
        bytes memory opsData = abi.encode(operations);

        vm.expectRevert(ISmartOrderStrategy.ZeroDenominator.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, opsData);
    }

    function testCannotExecuteWithFailDecodedData() public {
        vm.expectRevert();
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, bytes("random data"));
    }

    function testCannotExecuteWithEmptyOperation() public {
        ISmartOrderStrategy.Operation[] memory operations;
        bytes memory emptyOpsData = abi.encode(operations);

        vm.expectRevert(ISmartOrderStrategy.EmptyOps.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, emptyOpsData);
    }

    function testCannotExecuteWithIncorrectMsgValue() public {
        // case : ETH as input but msg.value mismatch
        address inputToken = Constant.ETH_ADDRESS;
        uint256 inputAmount = 1 ether;

        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy{ value: inputAmount + 1 }(inputToken, defaultOutputToken, inputAmount, defaultOpsData);

        // case : ETH as input but msg.value is zero
        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy{ value: 0 }(inputToken, defaultOutputToken, inputAmount, defaultOpsData);

        // case : token as input but msg.value is not zero
        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        vm.prank(genericSwap, genericSwap);
        smartOrderStrategy.executeStrategy{ value: 1 }(defaultInputToken, defaultOutputToken, defaultInputAmount, defaultOpsData);
    }
}

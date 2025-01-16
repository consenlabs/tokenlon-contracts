// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { SmartOrderStrategyTest } from "./Setup.t.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";
import { Constant } from "contracts/libraries/Constant.sol";

contract ValidationTest is SmartOrderStrategyTest {
    function testCannotExecuteNotFromGenericSwap() public {
        vm.expectRevert(ISmartOrderStrategy.NotFromGS.selector);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, defaultOpsData);
    }

    function testCannotExecuteWithZeroInputAmount() public {
        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.ZeroInput.selector);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, 0, defaultOpsData);
        vm.stopPrank();
    }

    function testCannotExecuteWithZeroRatioDenominatorWhenRatioNumeratorIsNonZero() public {
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0].inputToken = USDC_ADDRESS;
        operations[0].ratioNumerator = 1;
        operations[0].ratioDenominator = 0;
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.ZeroDenominator.selector);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, opsData);
        vm.stopPrank();
    }

    function testCannotExecuteWithFailDecodedData() public {
        vm.startPrank(genericSwap);
        vm.expectRevert();
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, bytes("random data"));
        vm.stopPrank();
    }

    function testCannotExecuteWithEmptyOperation() public {
        ISmartOrderStrategy.Operation[] memory operations;
        bytes memory emptyOpsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.EmptyOps.selector);
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, emptyOpsData);
        vm.stopPrank();
    }

    function testCannotExecuteWithIncorrectMsgValue() public {
        // case : ETH as input but msg.value mismatch
        address inputToken = Constant.ETH_ADDRESS;
        uint256 inputAmount = 1 ether;

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        smartOrderStrategy.executeStrategy{ value: inputAmount + 1 }(inputToken, defaultOutputToken, inputAmount, defaultOpsData);
        vm.stopPrank();

        // case : ETH as input but msg.value is zero
        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        smartOrderStrategy.executeStrategy{ value: 0 }(inputToken, defaultOutputToken, inputAmount, defaultOpsData);
        vm.stopPrank();

        // case : token as input but msg.value is not zero
        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.InvalidMsgValue.selector);
        smartOrderStrategy.executeStrategy{ value: 1 }(defaultInputToken, defaultOutputToken, defaultInputAmount, defaultOpsData);
        vm.stopPrank();
    }

    function testCannotExecuteAnOperationWillFail() public {
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: defaultInputToken,
            inputToken: defaultInputToken,
            ratioNumerator: 0,
            ratioDenominator: 0,
            dataOffset: 0,
            value: 0,
            data: abi.encode("invalid data")
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert();
        smartOrderStrategy.executeStrategy(defaultInputToken, defaultOutputToken, defaultInputAmount, opsData);
        vm.stopPrank();
    }
}

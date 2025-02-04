// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { SmartOrderStrategyTest } from "./Setup.t.sol";

import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";

contract ValidationTest is SmartOrderStrategyTest {
    function testCannotExecuteNotFromGenericSwap() public {
        vm.expectRevert(ISmartOrderStrategy.NotFromGS.selector);
        smartOrderStrategy.executeStrategy(defaultOutputToken, defaultOpsData);
    }

    function testCannotExecuteWithZeroRatioDenominatorWhenRatioNumeratorIsNonZero() public {
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0].inputToken = USDC_ADDRESS;
        operations[0].ratioNumerator = 1;
        operations[0].ratioDenominator = 0;
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.ZeroDenominator.selector);
        smartOrderStrategy.executeStrategy(defaultOutputToken, opsData);
        vm.stopPrank();
    }

    function testCannotExecuteWithFailDecodedData() public {
        vm.startPrank(genericSwap);
        vm.expectRevert();
        smartOrderStrategy.executeStrategy(defaultOutputToken, bytes("random data"));
        vm.stopPrank();
    }

    function testCannotExecuteWithEmptyOperation() public {
        ISmartOrderStrategy.Operation[] memory operations;
        bytes memory emptyOpsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.EmptyOps.selector);
        smartOrderStrategy.executeStrategy(defaultOutputToken, emptyOpsData);
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
        smartOrderStrategy.executeStrategy(defaultOutputToken, opsData);
        vm.stopPrank();
    }
}

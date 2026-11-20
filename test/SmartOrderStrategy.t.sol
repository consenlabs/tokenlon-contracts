// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { SmartOrderStrategy } from "contracts/SmartOrderStrategy.sol";
import { ISmartOrderStrategy } from "contracts/interfaces/ISmartOrderStrategy.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockWETH } from "test/mocks/MockWETH.sol";

contract SmartOrderStrategyLocalTest is Test {
    address strategyOwner = makeAddr("strategyOwner");
    address genericSwap = makeAddr("genericSwap");

    SmartOrderStrategy smartOrderStrategy;
    MockWETH mockWeth;
    MockERC20 inputToken;
    MockERC20 outputToken;
    MockDestination mockDest;

    function setUp() public {
        mockWeth = new MockWETH("Wrapped ETH", "WETH", 18);
        inputToken = new MockERC20("Input", "IN", 18);
        outputToken = new MockERC20("Output", "OUT", 18);
        mockDest = new MockDestination();

        smartOrderStrategy = new SmartOrderStrategy(strategyOwner, genericSwap, address(mockWeth));
    }

    function testCannotExecuteNotFromGenericSwap() public {
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        bytes memory opsData = abi.encode(operations);

        vm.expectRevert(ISmartOrderStrategy.NotFromGS.selector);
        smartOrderStrategy.executeStrategy(address(outputToken), opsData);
    }

    function testCannotExecuteWithEmptyOperations() public {
        ISmartOrderStrategy.Operation[] memory operations;
        bytes memory emptyOpsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.EmptyOps.selector);
        smartOrderStrategy.executeStrategy(address(outputToken), emptyOpsData);
        vm.stopPrank();
    }

    function testCannotExecuteWithZeroRatioDenominator() public {
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: address(mockDest),
            inputToken: address(inputToken),
            ratioNumerator: 1,
            ratioDenominator: 0,
            dataOffset: 32,
            value: 0,
            data: abi.encode(uint256(0))
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.ZeroDenominator.selector);
        smartOrderStrategy.executeStrategy(address(outputToken), opsData);
        vm.stopPrank();
    }

    function testCannotExecuteWithInvalidInputRatioNumeratorGreaterThanDenominator() public {
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: address(mockDest),
            inputToken: address(inputToken),
            ratioNumerator: 10001,
            ratioDenominator: 10000,
            dataOffset: 32,
            value: 0,
            data: abi.encode(uint256(0))
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        vm.expectRevert(ISmartOrderStrategy.InvalidInputRatio.selector);
        smartOrderStrategy.executeStrategy(address(outputToken), opsData);
        vm.stopPrank();
    }

    function testExecuteWithValidInputRatio() public {
        // Mint input tokens to strategy
        inputToken.mint(address(smartOrderStrategy), 1000 ether);
        // Mint output tokens to mock destination so it sends output to strategy during call
        outputToken.mint(address(mockDest), 500 ether);
        mockDest.setOutputTokenAndAmount(address(outputToken), 500 ether);

        // ratio 5000 / 10000 = 50% -> 500 ether
        bytes memory callPayload = abi.encode(uint256(0));
        ISmartOrderStrategy.Operation[] memory operations = new ISmartOrderStrategy.Operation[](1);
        operations[0] = ISmartOrderStrategy.Operation({
            dest: address(mockDest),
            inputToken: address(inputToken),
            ratioNumerator: 5000,
            ratioDenominator: 10000,
            dataOffset: 32,
            value: 0,
            data: callPayload
        });
        bytes memory opsData = abi.encode(operations);

        vm.startPrank(genericSwap);
        smartOrderStrategy.executeStrategy(address(outputToken), opsData);
        vm.stopPrank();

        assertEq(mockDest.lastReceivedAmount(), 500 ether);
        // GenericSwap received output tokens (minus 1 wei gas optimization if balance > 1)
        assertEq(outputToken.balanceOf(genericSwap), 500 ether - 1);
    }
}

contract MockDestination {
    address public outputToken;
    uint256 public outputAmount;
    uint256 public lastReceivedAmount;

    function setOutputTokenAndAmount(address _token, uint256 _amount) external {
        outputToken = _token;
        outputAmount = _amount;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        lastReceivedAmount = abi.decode(data, (uint256));
        if (outputToken != address(0) && outputAmount > 0) {
            MockERC20(outputToken).transfer(msg.sender, outputAmount);
        }
        return "";
    }
}

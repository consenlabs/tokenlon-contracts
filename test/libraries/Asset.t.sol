// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { Asset } from "contracts/libraries/Asset.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract AssetTest is Test {
    using Asset for address;

    MockERC20 token;
    AssetHarness assetHarness;

    address payable recipient = payable(makeAddr("recipient"));
    uint256 tokenBalance = 123;
    uint256 ethBalance = 456;

    function setUp() public {
        token = new MockERC20("TOKEN", "TKN", 18);
        assetHarness = new AssetHarness();

        // set balance
        token.mint(address(assetHarness), tokenBalance);
        vm.deal(address(assetHarness), ethBalance);
    }

    function testIsETH() public {
        assertTrue(assetHarness.exposedIsETH(Constant.ETH_ADDRESS));
        vm.snapshotGasLastCall("Asset", "isETH(): testIsETH(ETH_ADDRESS)");
        assertTrue(assetHarness.exposedIsETH(Constant.ZERO_ADDRESS));
        vm.snapshotGasLastCall("Asset", "isETH(): testIsETH2(ZERO_ADDRESS)");
    }

    function testGetBalance() public {
        assertEq(assetHarness.exposedGetBalance(address(token), address(assetHarness)), tokenBalance);
        vm.snapshotGasLastCall("Asset", "getBalance(): testGetBalance");
        assertEq(assetHarness.exposedGetBalance(Constant.ETH_ADDRESS, address(assetHarness)), ethBalance);
        vm.snapshotGasLastCall("Asset", "getBalance(): testGetBalance(ETH_ADDRESS)");
        assertEq(assetHarness.exposedGetBalance(Constant.ZERO_ADDRESS, address(assetHarness)), ethBalance);
        vm.snapshotGasLastCall("Asset", "getBalance(): testGetBalance(ZERO_ADDRESS)");
    }

    function testDoNothingIfTransferWithZeroAmount() public {
        assetHarness.exposedTransferTo(address(token), recipient, 0);
        vm.snapshotGasLastCall("Asset", "transferTo(): testDoNothingIfTransferWithZeroAmount");
    }

    function testDoNothingIfTransferToSelf() public {
        assetHarness.exposedTransferTo(address(token), payable(address(token)), 0);
        vm.snapshotGasLastCall("Asset", "transferTo(): testDoNothingIfTransferToSelf");
    }

    function testCannotTransferETHWithInsufficientBalance() public {
        vm.expectRevert();
        assetHarness.exposedTransferTo(Constant.ETH_ADDRESS, recipient, address(assetHarness).balance + 1);
    }

    function testCannotTransferETHToContractCannotReceiveETH() public {
        vm.expectRevert();
        // mockERC20 cannot receive any ETH
        assetHarness.exposedTransferTo(Constant.ETH_ADDRESS, payable(address(token)), 1);
    }

    function testTransferETH() public {
        uint256 amount = address(assetHarness).balance;
        assetHarness.exposedTransferTo(Constant.ETH_ADDRESS, recipient, amount);
        vm.snapshotGasLastCall("Asset", "transferTo(): testTransferETH");

        assertEq(address(recipient).balance, amount);
        assertEq(address(assetHarness).balance, 0);
    }

    function testTransferToken() public {
        uint256 amount = token.balanceOf(address(assetHarness));
        assetHarness.exposedTransferTo(address(token), recipient, amount);
        vm.snapshotGasLastCall("Asset", "transferTo(): testTransferToken");

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(assetHarness)), 0);
    }
}

contract AssetHarness {
    function exposedIsETH(address addr) external pure returns (bool) {
        return Asset.isETH(addr);
    }

    function exposedGetBalance(address asset, address owner) external view returns (uint256) {
        return Asset.getBalance(asset, owner);
    }

    function exposedTransferTo(address asset, address payable to, uint256 amount) external {
        Asset.transferTo(asset, to, amount);
    }
}

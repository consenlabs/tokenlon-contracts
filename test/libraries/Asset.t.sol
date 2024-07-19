// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { Asset } from "contracts/libraries/Asset.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract AssetTest is Test {
    using Asset for address;

    MockERC20 token;

    address payable recipient = payable(makeAddr("recipient"));
    uint256 tokenBalance = 123;
    uint256 ethBalance = 456;

    function setUp() public {
        token = new MockERC20("TOKEN", "TKN", 18);

        // set balance
        token.mint(address(this), tokenBalance);
        vm.deal(address(this), ethBalance);
    }

    function transferToWrap(address asset, address payable to, uint256 amount) public {
        Asset.transferTo(asset, to, amount);
    }

    function testIsETH() public {
        assertTrue(Asset.isETH(Constant.ETH_ADDRESS));
        assertTrue(Asset.isETH(address(0)));
    }

    function testGetBalance() public {
        assertEq(Asset.getBalance(address(token), address(this)), tokenBalance);
        assertEq(Asset.getBalance(Constant.ETH_ADDRESS, address(this)), ethBalance);
        assertEq(Asset.getBalance(address(0), address(this)), ethBalance);
    }

    function testDoNothingIfTransferWithZeroAmount() public {
        Asset.transferTo(address(token), recipient, 0);
    }

    function testDoNothingIfTransferToSelf() public {
        Asset.transferTo(address(token), payable(address(token)), 0);
    }

    function testTransferETHWithInsufficientBalance() public {
        vm.expectRevert(Asset.InsufficientBalance.selector);
        this.transferToWrap(Constant.ETH_ADDRESS, recipient, address(this).balance + 1);
    }

    function testTransferETHToContractCannotReceiveETH() public {
        vm.expectRevert();
        // mockERC20 cannot receive any ETH
        this.transferToWrap(Constant.ETH_ADDRESS, payable(address(token)), 1);
    }

    function testTransferETH() public {
        uint256 amount = address(this).balance;
        Asset.transferTo(Constant.ETH_ADDRESS, payable(recipient), amount);

        assertEq(address(recipient).balance, amount);
        assertEq(address(this).balance, 0);
    }

    function testTransferToken() public {
        uint256 amount = token.balanceOf(address(this));
        Asset.transferTo(address(token), payable(recipient), amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), 0);
    }
}

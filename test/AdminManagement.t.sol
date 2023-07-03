// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AdminManagement } from "contracts/abstracts/AdminManagement.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";

contract ContractWithAdmin is AdminManagement {
    constructor(address _owner) AdminManagement(_owner) {}
}

contract AdminManagementTest is BalanceUtil {
    address owner = makeAddr("owner");
    address rescueTarget = makeAddr("rescueTarget");
    MockERC20 token1 = new MockERC20("TOKEN1", "TKN1", 18);
    MockERC20 token2 = new MockERC20("TOKEN2", "TKN2", 18);
    address[] tokens = [address(token1), address(token2)];
    address[] spenders = [address(this), owner];
    ContractWithAdmin contractWithAdmin;

    function setUp() public {
        contractWithAdmin = new ContractWithAdmin(owner);
    }

    function testCannotApproveTokensByNotOwner() public {
        vm.expectRevert("not owner");
        contractWithAdmin.approveTokens(tokens, spenders);
    }

    function testApproveTokens() public {
        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                assertEq(IERC20(tokens[i]).allowance(address(contractWithAdmin), spenders[j]), 0);
            }
        }

        vm.prank(owner);
        contractWithAdmin.approveTokens(tokens, spenders);

        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                assertEq(IERC20(tokens[i]).allowance(address(contractWithAdmin), spenders[j]), type(uint256).max);
            }
        }
    }

    function testCannotRescueTokensByNotOwner() public {
        vm.expectRevert("not owner");
        contractWithAdmin.rescueTokens(tokens, rescueTarget);
    }

    function testRescueTokens() public {
        uint256 amount1 = 1234;
        token1.mint(address(contractWithAdmin), amount1);
        uint256 amount2 = 6789;
        token2.mint(address(contractWithAdmin), amount2);

        assertEq(IERC20(tokens[0]).balanceOf(address(contractWithAdmin)), amount1);
        assertEq(IERC20(tokens[0]).balanceOf(rescueTarget), 0);
        assertEq(IERC20(tokens[1]).balanceOf(address(contractWithAdmin)), amount2);
        assertEq(IERC20(tokens[1]).balanceOf(rescueTarget), 0);

        vm.prank(owner);
        contractWithAdmin.rescueTokens(tokens, rescueTarget);

        assertEq(IERC20(tokens[0]).balanceOf(address(contractWithAdmin)), 0);
        assertEq(IERC20(tokens[0]).balanceOf(rescueTarget), amount1);
        assertEq(IERC20(tokens[1]).balanceOf(address(contractWithAdmin)), 0);
        assertEq(IERC20(tokens[1]).balanceOf(rescueTarget), amount2);
    }
}

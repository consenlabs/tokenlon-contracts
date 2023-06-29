// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Base } from "contracts/abstracts/Base.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";

contract ExtendedBase is Base {
    constructor(address _owner) Base(_owner) {}
}

contract BaseTest is BalanceUtil {
    address baseOwner = makeAddr("baseOwner");
    address rescueTarget = makeAddr("rescueTarget");
    MockERC20 token1 = new MockERC20("TOKEN1", "TKN1", 18);
    MockERC20 token2 = new MockERC20("TOKEN2", "TKN2", 18);
    address[] tokens = [address(token1), address(token2)];
    address[] spenders = [address(this), baseOwner];
    ExtendedBase extendedBase;

    function setUp() public {
        extendedBase = new ExtendedBase(baseOwner);
    }

    function testCannotApproveTokensByNotOwner() public {
        vm.expectRevert("not owner");
        extendedBase.approveTokens(tokens, spenders);
    }

    function testApproveTokens() public {
        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                assertEq(IERC20(tokens[i]).allowance(address(extendedBase), spenders[j]), 0);
            }
        }

        vm.prank(baseOwner);
        extendedBase.approveTokens(tokens, spenders);

        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                assertEq(IERC20(tokens[i]).allowance(address(extendedBase), spenders[j]), Constant.MAX_UINT);
            }
        }
    }

    function testCannotRescueTokensByNotOwner() public {
        vm.expectRevert("not owner");
        extendedBase.rescueTokens(tokens, rescueTarget);
    }

    function testRescueTokens() public {
        uint256 amount1 = 1234;
        token1.mint(address(extendedBase), amount1);
        uint256 amount2 = 6789;
        token2.mint(address(extendedBase), amount2);

        assertEq(IERC20(tokens[0]).balanceOf(address(extendedBase)), amount1);
        assertEq(IERC20(tokens[0]).balanceOf(rescueTarget), 0);
        assertEq(IERC20(tokens[1]).balanceOf(address(extendedBase)), amount2);
        assertEq(IERC20(tokens[1]).balanceOf(rescueTarget), 0);

        vm.prank(baseOwner);
        extendedBase.rescueTokens(tokens, rescueTarget);

        assertEq(IERC20(tokens[0]).balanceOf(address(extendedBase)), 0);
        assertEq(IERC20(tokens[0]).balanceOf(rescueTarget), amount1);
        assertEq(IERC20(tokens[1]).balanceOf(address(extendedBase)), 0);
        assertEq(IERC20(tokens[1]).balanceOf(rescueTarget), amount2);
    }
}

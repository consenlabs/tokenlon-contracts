// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { getEIP712Hash } from "test/utils/Sig.sol";
import { IUniswapRouterV2 } from "contracts/interfaces/IUniswapRouterV2.sol";
import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { ICoordinatedTaker } from "contracts/interfaces/ICoordinatedTaker.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";
import { AllowFill, getAllowFillHash } from "contracts/libraries/AllowFill.sol";
import { CoordinatedTaker } from "contracts/CoordinatedTaker.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";
import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract CoordinatedTakerTest is LimitOrderSwapTest {
    using BalanceSnapshot for Snapshot;

    event SetCoordinator(address newCoordinator);

    address conditionalTakerOwner = makeAddr("conditionalTakerOwner");
    address user = makeAddr("user");

    address[] tokenList = [USDC_ADDRESS, USDT_ADDRESS, DAI_ADDRESS, WETH_ADDRESS, WBTC_ADDRESS];
    address[] ammList = [UNISWAP_V2_ADDRESS, SUSHISWAP_ADDRESS, BALANCER_V2_ADDRESS, CURVE_USDT_POOL_ADDRESS];

    uint256 crdPrivateKey = uint256(2);
    address coordinator = vm.addr(crdPrivateKey);
    LimitOrder defaultConOrder;
    AllowFill defaultAllowFill;
    ICoordinatedTaker.CoordinatorParams defaultCRDParams;
    CoordinatedTaker conditionalTaker;

    function setUp() public override {
        super.setUp();
        conditionalTaker = new CoordinatedTaker(
            conditionalTakerOwner,
            UNISWAP_PERMIT2_ADDRESS,
            address(allowanceTarget),
            IWETH(WETH_ADDRESS),
            coordinator,
            ILimitOrderSwap(address(limitOrderSwap))
        );
        // setup conditionalTaker approval
        address[] memory targetList = new address[](1);
        targetList[0] = address(limitOrderSwap);
        vm.prank(conditionalTakerOwner);
        conditionalTaker.approveTokens(tokenList, targetList);

        deal(user, 100 ether);
        setTokenBalanceAndApprove(user, address(conditionalTaker), tokens, 100000);

        defaultConOrder = defaultOrder;
        defaultConOrder.taker = address(conditionalTaker);

        defaultMakerSig = _signLimitOrder(makerPrivateKey, defaultConOrder);

        defaultAllowFill = AllowFill({
            orderHash: getLimitOrderHash(defaultConOrder),
            taker: user,
            fillAmount: defaultConOrder.makerTokenAmount,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        defaultCRDParams = ICoordinatedTaker.CoordinatorParams({
            sig: _signAllowFill(crdPrivateKey, defaultAllowFill),
            expiry: defaultAllowFill.expiry,
            salt: defaultAllowFill.salt
        });
    }

    function testCannotSetCoordinatorByNotOwner() public {
        address newCoordinator = makeAddr("newCoordinator");
        vm.prank(newCoordinator);
        vm.expectRevert("not owner");
        conditionalTaker.setCoordinator(payable(newCoordinator));
    }

    function testCannotSetCoordinatorToZero() public {
        vm.prank(conditionalTakerOwner, conditionalTakerOwner);
        vm.expectRevert(ICoordinatedTaker.ZeroAddress.selector);
        conditionalTaker.setCoordinator(payable(address(0)));
    }

    function testSetCoordinator() public {
        address newCoordinator = makeAddr("newCoordinator");
        vm.prank(conditionalTakerOwner, conditionalTakerOwner);
        conditionalTaker.setCoordinator(payable(newCoordinator));
        emit SetCoordinator(newCoordinator);
        assertEq(conditionalTaker.coordinator(), newCoordinator);
    }

    function testCannotApproveTokensByNotOwner() public {
        vm.expectRevert("not owner");
        conditionalTaker.approveTokens(tokenList, ammList);
    }

    function testApproveTokens() public {
        MockERC20 mockERC20 = new MockERC20("Mock Token", "MKT", 18);
        address[] memory newTokens = new address[](1);
        newTokens[0] = address(mockERC20);

        address target = makeAddr("target");
        address[] memory targetList = new address[](1);
        targetList[0] = target;

        assertEq(mockERC20.allowance(address(conditionalTaker), target), 0);
        vm.prank(conditionalTakerOwner);
        conditionalTaker.approveTokens(newTokens, targetList);
        assertEq(mockERC20.allowance(address(conditionalTaker), target), Constant.MAX_UINT);
    }

    function testCannotWithdrawTokensByNotOwner() public {
        vm.expectRevert("not owner");
        conditionalTaker.withdrawTokens(tokenList, address(this));
    }

    function testWithdrawTokens() public {
        uint256 amount = 5678;
        MockERC20 mockERC20 = new MockERC20("Mock Token", "MKT", 18);
        mockERC20.mint(address(conditionalTaker), amount);

        address[] memory withdrawList = new address[](1);
        withdrawList[0] = address(mockERC20);

        address withdrawTarget = makeAddr("withdrawTarget");
        Snapshot memory recipientBalance = BalanceSnapshot.take(withdrawTarget, address(mockERC20));

        vm.prank(conditionalTakerOwner);
        conditionalTaker.withdrawTokens(withdrawList, withdrawTarget);

        recipientBalance.assertChange(int256(amount));
    }

    function testFillWithPermission() public {
        vm.prank(user, user);
        conditionalTaker.submitLimitOrderFill({
            order: defaultConOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultConOrder.takerTokenAmount,
            makerTokenAmount: defaultConOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });
    }

    function testCannotFillWithExpiredPermission() public {
        vm.warp(defaultAllowFill.expiry + 1);

        vm.expectRevert(ICoordinatedTaker.ExpiredPermission.selector);
        vm.prank(user, user);
        conditionalTaker.submitLimitOrderFill({
            order: defaultConOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultConOrder.takerTokenAmount,
            makerTokenAmount: defaultConOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });
    }

    function testCannotFillWithIncorrectCoordinatorSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomAllowFillSig = _signAllowFill(randomPrivateKey, defaultAllowFill);

        ICoordinatedTaker.CoordinatorParams memory crdParams = defaultCRDParams;
        crdParams.sig = randomAllowFillSig;

        vm.expectRevert(ICoordinatedTaker.InvalidSignature.selector);
        vm.prank(user, user);
        conditionalTaker.submitLimitOrderFill({
            order: defaultConOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultConOrder.takerTokenAmount,
            makerTokenAmount: defaultConOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: crdParams
        });
    }

    function testCannotFillWithReplayedPermission() public {
        vm.prank(user, user);
        conditionalTaker.submitLimitOrderFill({
            order: defaultConOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultConOrder.takerTokenAmount,
            makerTokenAmount: defaultConOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });

        vm.expectRevert(ICoordinatedTaker.ReusedPermission.selector);
        vm.prank(user, user);
        conditionalTaker.submitLimitOrderFill({
            order: defaultConOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultConOrder.takerTokenAmount,
            makerTokenAmount: defaultConOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });
    }

    function testCannotFillWithInvalidMsgValue() public {
        vm.expectRevert(ICoordinatedTaker.InvalidMsgValue.selector);
        vm.prank(user, user);
        conditionalTaker.submitLimitOrderFill{ value: 1 ether }({
            order: defaultConOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultConOrder.takerTokenAmount,
            makerTokenAmount: defaultConOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });
    }

    function _signAllowFill(uint256 _privateKey, AllowFill memory _allowFill) internal view returns (bytes memory sig) {
        bytes32 allowFillHash = getAllowFillHash(_allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(conditionalTaker.EIP712_DOMAIN_SEPARATOR(), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}

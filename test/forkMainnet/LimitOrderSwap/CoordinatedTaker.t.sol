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

    address crdTakerOwner = makeAddr("crdTakerOwner");
    address user = makeAddr("user");

    address[] tokenList = [USDC_ADDRESS, USDT_ADDRESS, DAI_ADDRESS, WETH_ADDRESS, WBTC_ADDRESS];
    address[] ammList = [UNISWAP_V2_ADDRESS, SUSHISWAP_ADDRESS, BALANCER_V2_ADDRESS, CURVE_USDT_POOL_ADDRESS];

    uint256 crdPrivateKey = uint256(2);
    address coordinator = vm.addr(crdPrivateKey);
    LimitOrder defaultCrdOrder;
    AllowFill defaultAllowFill;
    ICoordinatedTaker.CoordinatorParams defaultCRDParams;
    CoordinatedTaker coordinatedTaker;

    function setUp() public override {
        super.setUp();
        coordinatedTaker = new CoordinatedTaker(
            crdTakerOwner,
            UNISWAP_PERMIT2_ADDRESS,
            address(allowanceTarget),
            IWETH(WETH_ADDRESS),
            coordinator,
            ILimitOrderSwap(address(limitOrderSwap))
        );
        // setup coordinatedTaker approval
        address[] memory targetList = new address[](1);
        targetList[0] = address(limitOrderSwap);
        vm.prank(crdTakerOwner);
        coordinatedTaker.approveTokens(tokenList, targetList);

        deal(user, 100 ether);
        setTokenBalanceAndApprove(user, address(coordinatedTaker), tokens, 100000);

        defaultCrdOrder = defaultOrder;
        defaultCrdOrder.taker = address(coordinatedTaker);

        defaultMakerSig = _signLimitOrder(makerPrivateKey, defaultCrdOrder);

        defaultAllowFill = AllowFill({
            orderHash: getLimitOrderHash(defaultCrdOrder),
            taker: user,
            fillAmount: defaultCrdOrder.makerTokenAmount,
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
        coordinatedTaker.setCoordinator(payable(newCoordinator));
    }

    function testCannotSetCoordinatorToZero() public {
        vm.prank(crdTakerOwner, crdTakerOwner);
        vm.expectRevert(ICoordinatedTaker.ZeroAddress.selector);
        coordinatedTaker.setCoordinator(payable(address(0)));
    }

    function testSetCoordinator() public {
        address newCoordinator = makeAddr("newCoordinator");
        vm.prank(crdTakerOwner, crdTakerOwner);
        coordinatedTaker.setCoordinator(payable(newCoordinator));
        emit SetCoordinator(newCoordinator);
        assertEq(coordinatedTaker.coordinator(), newCoordinator);
    }

    function testCannotApproveTokensByNotOwner() public {
        vm.expectRevert("not owner");
        coordinatedTaker.approveTokens(tokenList, ammList);
    }

    function testApproveTokens() public {
        MockERC20 mockERC20 = new MockERC20("Mock Token", "MKT", 18);
        address[] memory newTokens = new address[](1);
        newTokens[0] = address(mockERC20);

        address target = makeAddr("target");
        address[] memory targetList = new address[](1);
        targetList[0] = target;

        assertEq(mockERC20.allowance(address(coordinatedTaker), target), 0);
        vm.prank(crdTakerOwner);
        coordinatedTaker.approveTokens(newTokens, targetList);
        assertEq(mockERC20.allowance(address(coordinatedTaker), target), Constant.MAX_UINT);
    }

    function testFillWithPermission() public {
        Snapshot memory userTakerToken = BalanceSnapshot.take({ owner: user, token: defaultCrdOrder.takerToken });
        Snapshot memory userMakerToken = BalanceSnapshot.take({ owner: user, token: defaultCrdOrder.makerToken });
        Snapshot memory contractTakerToken = BalanceSnapshot.take({ owner: address(coordinatedTaker), token: defaultCrdOrder.takerToken });
        Snapshot memory contractMakerToken = BalanceSnapshot.take({ owner: address(coordinatedTaker), token: defaultCrdOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultCrdOrder.makerToken });

        uint256 fee = (defaultCrdOrder.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(defaultCrdOrder),
            address(coordinatedTaker), // taker
            defaultCrdOrder.maker,
            defaultCrdOrder.takerToken,
            defaultCrdOrder.takerTokenAmount,
            defaultCrdOrder.makerToken,
            defaultCrdOrder.makerTokenAmount - fee,
            fee,
            user // recipient
        );

        vm.prank(user, user);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });

        userTakerToken.assertChange(-int256(defaultCrdOrder.takerTokenAmount));
        userMakerToken.assertChange(int256(defaultCrdOrder.makerTokenAmount - fee));
        contractTakerToken.assertChange(0);
        contractMakerToken.assertChange(0);
        fcMakerToken.assertChange(int256(fee));
    }

    function testFillWithETH() public {
        // read token from constant & defaultOrder to avoid stack too deep error
        Snapshot memory userTakerToken = BalanceSnapshot.take({ owner: user, token: Constant.ETH_ADDRESS });
        Snapshot memory userMakerToken = BalanceSnapshot.take({ owner: user, token: defaultCrdOrder.makerToken });
        Snapshot memory contractTakerToken = BalanceSnapshot.take({ owner: address(coordinatedTaker), token: Constant.ETH_ADDRESS });
        Snapshot memory contractMakerToken = BalanceSnapshot.take({ owner: address(coordinatedTaker), token: defaultCrdOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultCrdOrder.makerToken });

        LimitOrder memory order = defaultCrdOrder;
        order.takerToken = Constant.ETH_ADDRESS;
        order.takerTokenAmount = 1 ether;

        bytes memory makerSig = _signLimitOrder(makerPrivateKey, order);

        AllowFill memory allowFill = AllowFill({
            orderHash: getLimitOrderHash(order),
            taker: user,
            fillAmount: order.makerTokenAmount,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        ICoordinatedTaker.CoordinatorParams memory crdParams = ICoordinatedTaker.CoordinatorParams({
            sig: _signAllowFill(crdPrivateKey, allowFill),
            expiry: allowFill.expiry,
            salt: allowFill.salt
        });

        uint256 fee = (order.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilled(
            getLimitOrderHash(order),
            address(coordinatedTaker), // taker
            order.maker,
            order.takerToken,
            order.takerTokenAmount,
            order.makerToken,
            order.makerTokenAmount - fee,
            fee,
            user // recipient
        );

        vm.prank(user, user);
        coordinatedTaker.submitLimitOrderFill{ value: order.takerTokenAmount }({
            order: order,
            makerSignature: makerSig,
            takerTokenAmount: order.takerTokenAmount,
            makerTokenAmount: order.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: crdParams
        });

        userTakerToken.assertChange(-int256(order.takerTokenAmount));
        userMakerToken.assertChange(int256(order.makerTokenAmount - fee));
        contractTakerToken.assertChange(0);
        contractMakerToken.assertChange(0);
        fcMakerToken.assertChange(int256(fee));
    }

    function testCannotFillWithExpiredPermission() public {
        vm.warp(defaultAllowFill.expiry + 1);

        vm.expectRevert(ICoordinatedTaker.ExpiredPermission.selector);
        vm.prank(user, user);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
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
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: crdParams
        });
    }

    function testCannotFillWithReplayedPermission() public {
        vm.prank(user, user);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });

        vm.expectRevert(ICoordinatedTaker.ReusedPermission.selector);
        vm.prank(user, user);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });
    }

    function testCannotFillWithInvalidMsgValue() public {
        vm.expectRevert(ICoordinatedTaker.InvalidMsgValue.selector);
        vm.prank(user, user);
        coordinatedTaker.submitLimitOrderFill{ value: 1 ether }({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultPermit,
            crdParams: defaultCRDParams
        });
    }

    function _signAllowFill(uint256 _privateKey, AllowFill memory _allowFill) internal view returns (bytes memory sig) {
        bytes32 allowFillHash = getAllowFillHash(_allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(coordinatedTaker.EIP712_DOMAIN_SEPARATOR(), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}

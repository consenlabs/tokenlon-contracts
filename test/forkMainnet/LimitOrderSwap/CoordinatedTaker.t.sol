// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { CoordinatedTaker } from "contracts/CoordinatedTaker.sol";
import { Ownable } from "contracts/abstracts/Ownable.sol";
import { ICoordinatedTaker } from "contracts/interfaces/ICoordinatedTaker.sol";
import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { AllowFill, getAllowFillHash } from "contracts/libraries/AllowFill.sol";
import { Constant } from "contracts/libraries/Constant.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";

import { LimitOrderSwapTest } from "test/forkMainnet/LimitOrderSwap/Setup.t.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract CoordinatedTakerTest is LimitOrderSwapTest {
    using BalanceSnapshot for Snapshot;

    address crdTakerOwner = makeAddr("crdTakerOwner");
    uint256 userPrivateKey = uint256(5);
    address user = vm.addr(userPrivateKey);

    address[] tokenList = [USDC_ADDRESS, USDT_ADDRESS, DAI_ADDRESS, WETH_ADDRESS, WBTC_ADDRESS];
    address[] ammList = [UNISWAP_SWAP_ROUTER_02_ADDRESS, SUSHISWAP_ADDRESS];

    uint256 crdPrivateKey = uint256(2);
    address coordinator = vm.addr(crdPrivateKey);
    bytes defaultUserPermit;
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
        vm.startPrank(crdTakerOwner);
        coordinatedTaker.approveTokens(tokenList, targetList);
        vm.stopPrank();

        deal(user, 100 ether);
        setTokenBalanceAndApprove(user, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);

        defaultCrdOrder = defaultOrder;
        defaultCrdOrder.taker = address(coordinatedTaker);

        defaultMakerSig = signLimitOrder(makerPrivateKey, defaultCrdOrder, address(limitOrderSwap));

        defaultUserPermit = getTokenlonPermit2Data(user, userPrivateKey, defaultCrdOrder.takerToken, address(coordinatedTaker));

        defaultAllowFill = AllowFill({
            orderHash: getLimitOrderHash(defaultCrdOrder),
            taker: user,
            fillAmount: defaultCrdOrder.makerTokenAmount,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        defaultCRDParams = ICoordinatedTaker.CoordinatorParams({
            sig: signAllowFill(crdPrivateKey, defaultAllowFill, address(coordinatedTaker)),
            expiry: defaultAllowFill.expiry,
            salt: defaultAllowFill.salt
        });
    }

    function testCoordinatedTakerInitialState() public {
        coordinatedTaker = new CoordinatedTaker(
            crdTakerOwner,
            UNISWAP_PERMIT2_ADDRESS,
            address(allowanceTarget),
            IWETH(WETH_ADDRESS),
            coordinator,
            ILimitOrderSwap(address(limitOrderSwap))
        );

        assertEq(address(coordinatedTaker.owner()), crdTakerOwner);
        assertEq(coordinatedTaker.permit2(), UNISWAP_PERMIT2_ADDRESS);
        assertEq(coordinatedTaker.allowanceTarget(), address(allowanceTarget));
        assertEq(address(coordinatedTaker.weth()), WETH_ADDRESS);
        assertEq(coordinatedTaker.coordinator(), coordinator);
        assertEq(address(coordinatedTaker.limitOrderSwap()), address(limitOrderSwap));
    }

    function testCannotSetCoordinatorByNotOwner() public {
        address newCoordinator = makeAddr("newCoordinator");

        vm.startPrank(newCoordinator);
        vm.expectRevert(Ownable.NotOwner.selector);
        coordinatedTaker.setCoordinator(newCoordinator);
        vm.stopPrank();
    }

    function testCannotSetCoordinatorToZero() public {
        vm.startPrank(crdTakerOwner);
        vm.expectRevert(ICoordinatedTaker.ZeroAddress.selector);
        coordinatedTaker.setCoordinator(Constant.ZERO_ADDRESS);
        vm.stopPrank();
    }

    function testSetCoordinator() public {
        address newCoordinator = makeAddr("newCoordinator");

        vm.expectEmit(false, false, false, true);
        emit ICoordinatedTaker.SetCoordinator(newCoordinator);

        vm.startPrank(crdTakerOwner);
        coordinatedTaker.setCoordinator(newCoordinator);
        vm.stopPrank();
        vm.snapshotGasLastCall("CoordinatedTaker", "setCoordinator(): testSetCoordinator");

        assertEq(coordinatedTaker.coordinator(), newCoordinator);
    }

    function testCannotApproveTokensByNotOwner() public {
        vm.expectRevert(Ownable.NotOwner.selector);
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

        vm.startPrank(crdTakerOwner);
        coordinatedTaker.approveTokens(newTokens, targetList);
        vm.stopPrank();
        vm.snapshotGasLastCall("CoordinatedTaker", "approveTokens(): testApproveTokens");

        assertEq(mockERC20.allowance(address(coordinatedTaker), target), type(uint256).max);
    }

    function testFillWithPermission() public {
        Snapshot memory userTakerToken = BalanceSnapshot.take({ owner: user, token: defaultCrdOrder.takerToken });
        Snapshot memory userMakerToken = BalanceSnapshot.take({ owner: user, token: defaultCrdOrder.makerToken });
        Snapshot memory contractTakerToken = BalanceSnapshot.take({ owner: address(coordinatedTaker), token: defaultCrdOrder.takerToken });
        Snapshot memory contractMakerToken = BalanceSnapshot.take({ owner: address(coordinatedTaker), token: defaultCrdOrder.makerToken });
        Snapshot memory fcMakerToken = BalanceSnapshot.take({ owner: feeCollector, token: defaultCrdOrder.makerToken });

        uint256 fee = (defaultCrdOrder.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit ICoordinatedTaker.CoordinatorFill(
            user,
            getLimitOrderHash(defaultCrdOrder),
            getEIP712Hash(coordinatedTaker.EIP712_DOMAIN_SEPARATOR(), getAllowFillHash(defaultAllowFill))
        );

        vm.expectEmit(true, true, true, true);
        emit ILimitOrderSwap.LimitOrderFilled(
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

        vm.startPrank(user);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultUserPermit,
            crdParams: defaultCRDParams
        });
        vm.stopPrank();
        vm.snapshotGasLastCall("CoordinatedTaker", "submitLimitOrderFill(): testFillWithPermission");

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

        bytes memory makerSig = signLimitOrder(makerPrivateKey, order, address(limitOrderSwap));

        AllowFill memory allowFill = AllowFill({
            orderHash: getLimitOrderHash(order),
            taker: user,
            fillAmount: order.makerTokenAmount,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        ICoordinatedTaker.CoordinatorParams memory crdParams = ICoordinatedTaker.CoordinatorParams({
            sig: signAllowFill(crdPrivateKey, allowFill, address(coordinatedTaker)),
            expiry: allowFill.expiry,
            salt: allowFill.salt
        });

        uint256 fee = (order.makerTokenAmount * defaultFeeFactor) / Constant.BPS_MAX;

        vm.expectEmit(true, true, true, true);
        emit ICoordinatedTaker.CoordinatorFill(
            user,
            getLimitOrderHash(order),
            getEIP712Hash(coordinatedTaker.EIP712_DOMAIN_SEPARATOR(), getAllowFillHash(allowFill))
        );

        vm.expectEmit(true, true, true, true);
        emit ILimitOrderSwap.LimitOrderFilled(
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

        vm.startPrank(user);
        coordinatedTaker.submitLimitOrderFill{ value: order.takerTokenAmount }({
            order: order,
            makerSignature: makerSig,
            takerTokenAmount: order.takerTokenAmount,
            makerTokenAmount: order.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultUserPermit,
            crdParams: crdParams
        });
        vm.stopPrank();
        vm.snapshotGasLastCall("CoordinatedTaker", "submitLimitOrderFill(): testFillWithETH");

        userTakerToken.assertChange(-int256(order.takerTokenAmount));
        userMakerToken.assertChange(int256(order.makerTokenAmount - fee));
        contractTakerToken.assertChange(0);
        contractMakerToken.assertChange(0);
        fcMakerToken.assertChange(int256(fee));
    }

    function testCannotFillWithExpiredPermission() public {
        vm.warp(defaultAllowFill.expiry + 1);

        vm.startPrank(user);
        vm.expectRevert(ICoordinatedTaker.ExpiredPermission.selector);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultUserPermit,
            crdParams: defaultCRDParams
        });
        vm.stopPrank();
    }

    function testCannotFillWithIncorrectCoordinatorSig() public {
        uint256 randomPrivateKey = 5677;
        bytes memory randomAllowFillSig = signAllowFill(randomPrivateKey, defaultAllowFill, address(coordinatedTaker));

        ICoordinatedTaker.CoordinatorParams memory crdParams = defaultCRDParams;
        crdParams.sig = randomAllowFillSig;

        vm.startPrank(user);
        vm.expectRevert(ICoordinatedTaker.InvalidSignature.selector);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultUserPermit,
            crdParams: crdParams
        });
        vm.stopPrank();
    }

    function testCannotFillWithReplayedPermission() public {
        vm.startPrank(user);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultUserPermit,
            crdParams: defaultCRDParams
        });
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ICoordinatedTaker.ReusedPermission.selector);
        coordinatedTaker.submitLimitOrderFill({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: allowanceTransferPermit, // should transfer from permit2 allowance directly
            crdParams: defaultCRDParams
        });
        vm.stopPrank();
    }

    function testCannotFillWithInvalidMsgValue() public {
        vm.startPrank(user);
        vm.expectRevert(ICoordinatedTaker.InvalidMsgValue.selector);
        coordinatedTaker.submitLimitOrderFill{ value: 1 ether }({
            order: defaultCrdOrder,
            makerSignature: defaultMakerSig,
            takerTokenAmount: defaultCrdOrder.takerTokenAmount,
            makerTokenAmount: defaultCrdOrder.makerTokenAmount,
            extraAction: bytes(""),
            userTokenPermit: defaultUserPermit,
            crdParams: defaultCRDParams
        });
        vm.stopPrank();
    }
}

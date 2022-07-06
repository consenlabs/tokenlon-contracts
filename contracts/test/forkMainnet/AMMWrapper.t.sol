// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts/AMMWrapper.sol";
import "contracts/AMMQuoter.sol";
import "contracts/interfaces/IPermanentStorage.sol";
import "contracts/interfaces/ISpender.sol";
import "contracts/utils/AMMLibEIP712.sol";
import "contracts/utils/SignatureValidator.sol";
import "contracts-test/mocks/MockERC20.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/StrategySharedSetup.sol";

contract AMMWrapperTest is StrategySharedSetup {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 constant BPS_MAX = 10000;
    event Swapped(
        string source,
        bytes32 indexed transactionHash,
        address indexed userAddr,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint256 receivedAmount,
        uint16 feeFactor,
        uint16 subsidyFactor
    );

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address relayer = address(0x133702);
    address[] wallet = [user, relayer];

    AMMWrapper ammWrapper;
    AMMQuoter ammQuoter;
    IERC20 weth = IERC20(WETH_ADDRESS);
    IERC20 usdt = IERC20(USDT_ADDRESS);
    IERC20 dai = IERC20(DAI_ADDRESS);
    IERC20[] tokens = [weth, usdt, dai];

    uint256 SUBSIDY_FACTOR = 3;
    uint256 DEADLINE = block.timestamp + 1;
    AMMLibEIP712.Order DEFAULT_ORDER;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        setUpSystemContracts();
        ammQuoter = new AMMQuoter(IPermanentStorage(permanentStorage), address(weth));
        address[] memory relayerListAddress = new address[](1);
        relayerListAddress[0] = relayer;
        bool[] memory relayerListBool = new bool[](1);
        relayerListBool[0] = true;
        permanentStorage.setRelayersValid(relayerListAddress, relayerListBool);

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        setEOABalanceAndApprove(user, tokens, 100);

        // Default order
        DEFAULT_ORDER = AMMLibEIP712.Order(
            UNISWAP_V2_ADDRESS, // makerAddr
            address(dai), // takerAssetAddr
            address(usdt), // makerAssetAddr
            100 * 1e18, // takerAssetAmount
            90 * 1e6, // makerAssetAmount
            user, // userAddr
            payable(user), // receiverAddr
            uint256(1234), // salt
            DEADLINE // deadline
        );

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(relayer, "Relayer");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammWrapper), "AMMWrapperContract");
        vm.label(address(weth), "WETH");
        vm.label(address(usdt), "USDT");
        vm.label(address(dai), "DAI");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        ammWrapper = new AMMWrapper(
            address(this), // This contract would be the operator
            SUBSIDY_FACTOR,
            address(userProxy),
            ISpender(address(spender)),
            permanentStorage,
            IWETH(address(weth)),
            UNISWAP_V2_ADDRESS,
            SUSHISWAP_ADDRESS
        );
        // Setup
        userProxy.upgradeAMMWrapper(address(ammWrapper), true);
        permanentStorage.upgradeAMMWrapper(address(ammWrapper));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(ammWrapper), true);
        return address(ammWrapper);
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupTokens() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertGt(tokens[i].totalSupply(), uint256(0));
        }
    }

    function testSetupAllowance() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testSetupAMMWrapper() public {
        assertEq(ammWrapper.operator(), address(this));
        assertEq(ammWrapper.subsidyFactor(), SUBSIDY_FACTOR);
        assertEq(ammWrapper.userProxy(), address(userProxy));
        assertEq(address(ammWrapper.spender()), address(spender));
        assertEq(userProxy.ammWrapperAddr(), address(ammWrapper));
        assertEq(permanentStorage.ammWrapperAddr(), address(ammWrapper));
        assertTrue(spender.isAuthorized(address(ammWrapper)));
        assertTrue(permanentStorage.isRelayerValid(relayer));
    }

    /*********************************
     *     Test: upgradeSpender      *
     *********************************/

    function testCannotUpgradeSpenderByNotOperator() public {
        vm.expectRevert("AMMWrapper: not the operator");
        vm.prank(user);
        ammWrapper.upgradeSpender(user);
    }

    function testCannotUpgradeSpenderToZeroAddress() public {
        vm.expectRevert("AMMWrapper: spender can not be zero address");
        ammWrapper.upgradeSpender(address(0));
    }

    function testUpgradeSpender() public {
        ammWrapper.upgradeSpender(user);
        assertEq(address(ammWrapper.spender()), user);
    }

    /*********************************
     *   Test: set/close allowance   *
     *********************************/

    function testCannotSetAllowanceCloseAllowanceByNotOperator() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.startPrank(user);
        vm.expectRevert("AMMWrapper: not the operator");
        ammWrapper.setAllowance(allowanceTokenList, address(this));
        vm.expectRevert("AMMWrapper: not the operator");
        ammWrapper.closeAllowance(allowanceTokenList, address(this));
        vm.stopPrank();
    }

    function testSetAllowanceCloseAllowance() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        assertEq(usdt.allowance(address(ammWrapper), address(this)), uint256(0));

        ammWrapper.setAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(ammWrapper), address(this)), type(uint256).max);

        ammWrapper.closeAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(ammWrapper), address(this)), uint256(0));
    }

    /*********************************
     *       Test: depositETH        *
     *********************************/

    function testCannotDepositETHByNotOperator() public {
        vm.expectRevert("AMMWrapper: not the operator");
        vm.prank(user);
        ammWrapper.depositETH();
    }

    function testDepositETH() public {
        deal(address(ammWrapper), 1 ether);
        assertEq(address(ammWrapper).balance, 1 ether);
        ammWrapper.depositETH();
        assertEq(address(ammWrapper).balance, uint256(0));
        assertEq(weth.balanceOf(address(ammWrapper)), 1 ether);
    }

    /*********************************
     *          Test: trade          *
     *********************************/

    function testCannotTradeWithInvalidSig() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(otherPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("AMMWrapper: invalid user signature");
        userProxy.toAMM(payload);
    }

    function testTradeUniswapV2() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.takerAssetAddr = ETH_ADDRESS;
        order.takerAssetAmount = 0.1 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        vm.prank(user);
        userProxy.toAMM{ value: order.takerAssetAmount }(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testTradeUniswapV2WithOldEIP712Method() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.takerAssetAddr = ETH_ADDRESS;
        order.takerAssetAmount = 0.1 ether;
        bytes memory sig = _signTradeWithOldEIP712Method(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        vm.prank(user);
        userProxy.toAMM{ value: order.takerAssetAmount }(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testTradeCurve() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = CURVE_USDT_POOL_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testTradeSushiswap() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = SUSHISWAP_ADDRESS;
        order.makerAssetAddr = ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testCannotTradeWithSamePayloadAgain() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        userProxy.toAMM(payload);

        vm.expectRevert("PermanentStorage: transaction seen before");
        userProxy.toAMM(payload);
    }

    /*********************************
     *       Test: emit event        *
     *********************************/

    function testEmitSwappedEvent() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);
        // Set subsidy factor to 0
        ammWrapper.setSubsidyFactor(0);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        vm.expectEmit(true, true, false, true);
        emit Swapped(
            "Uniswap V2",
            AMMLibEIP712._getOrderHash(order),
            order.userAddr,
            order.takerAssetAddr,
            order.takerAssetAmount,
            order.makerAddr,
            order.makerAssetAddr,
            order.makerAssetAmount,
            order.receiverAddr,
            expectedOutAmount, // No fee so settled amount is the same as received amount
            expectedOutAmount,
            uint16(feeFactor), // Fee factor: 0
            uint16(0) // Subsidy factor: 0
        );
        userProxy.toAMM(payload);
    }

    /*****************************************************
     *              Test: collect fee (1)                *
     *    Received same amount as expected min amount    *
     *****************************************************/

    function testCollectFeeReceivedSameAsMinOut() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        order.makerAssetAmount = expectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChange(int256(0));
    }

    /*****************************************************
     *              Test: collect fee (2)                *
     *      Received more than expected min amount       *
     *****************************************************/

    function testCollectFeeReceivedMoreThanMinOut() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Reduce `expectedOutAmount` so received amount is more than `expectedOutAmount` and
        // the amount difference is enough for us to collect fee
        uint256 reducedExpectedOutAmount = (expectedOutAmount * (BPS_MAX - 2 * feeFactor)) / BPS_MAX;
        order.makerAssetAmount = reducedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChangeGt(int256(0));
    }

    /*********************************************************
     *                Test: collect fee (3)                  *
     * Received more than expected min amount but not enough *
     *********************************************************/

    function testCollectFeeReceivedMoreThanMinOutButNotEnough() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Reduce `expectedOutAmount` so received amount is more than `expectedOutAmount` but
        // the amount difference is not enough for us to collect fee
        uint256 reducedExpectedOutAmount = (expectedOutAmount * (BPS_MAX - feeFactor + 1)) / BPS_MAX;
        order.makerAssetAmount = reducedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChangeGt(int256(0));
    }

    /**********************************
     *         Test: subsidize        *
     **********************************/

    function testCannotSubsidizeIfSwapFailed() public {
        // Set subsidy factor to 0
        ammWrapper.setSubsidyFactor(0);

        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount` but
        // since subsidy factor is zero, `expectedOutAmount` would be the minimum receive amount requested to AMM
        // and result in failed swap.
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 1)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }

    function testCannotSubsidizeWithoutEnoughBalance() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`.
        // The amount difference should be in the subsidy range since `expectedOutAmount`
        // is increased by 1 BPS but subsidy factor is 3 BPS
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 1)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("AMMWrapper: not enough savings to subsidize");
        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);
    }

    function testCannotSubsidizeExceedMaxSubsidyAmount() public {
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 2)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);

        // Set fee factor to 0
        uint256 feeFactor = 0;
        vm.expectRevert("AMMWrapper: amount difference larger than subsidy amount");
        vm.prank(relayer, relayer);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);
        userProxy.toAMM(payload);

        // Set fee factor to 1
        feeFactor = 1;
        vm.expectRevert("AMMWrapper: amount difference larger than subsidy amount");
        vm.prank(relayer, relayer);
        payload = _genTradePayload(order, feeFactor, sig);
        userProxy.toAMM(payload);
    }

    function testCannotSubsidizeByNotRelayer() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 2)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        userProxy.toAMM(payload);
    }

    function testSubsidize() public {
        uint256 feeFactor = 5;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        uint256 expectedOutAmount = ammQuoter.getMakerOutAmount(order.makerAddr, order.takerAssetAddr, order.makerAssetAddr, order.takerAssetAmount);
        // Increase `expectedOutAmount` so received amount is less than `expectedOutAmount`
        uint256 increasedExpectedOutAmount = (expectedOutAmount * (BPS_MAX + 2)) / BPS_MAX;
        order.makerAssetAmount = increasedExpectedOutAmount;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig);

        // Supply AMMWrapper with maker token so it can subsidize
        vm.prank(user);
        IERC20(order.makerAssetAddr).safeTransfer(address(ammWrapper), order.makerAssetAmount);
        BalanceSnapshot.Snapshot memory ammWrapperMakerAsset = BalanceSnapshot.take(address(ammWrapper), order.makerAssetAddr);

        vm.prank(relayer, relayer);
        userProxy.toAMM(payload);

        ammWrapperMakerAsset.assertChangeGt(-int256(0));
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function _getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 EIP712_DOMAIN_SEPARATOR = ammWrapper.EIP712_DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, EIP712_DOMAIN_SEPARATOR, structHash));
    }

    function _signTrade(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = _getEIP712Hash(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _signTradeWithOldEIP712Method(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = _getEIP712Hash(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }

    function _genTradePayload(
        AMMLibEIP712.Order memory order,
        uint256 feeFactor,
        bytes memory sig
    ) internal view returns (bytes memory payload) {
        return
            abi.encodeWithSignature(
                "trade(address,address,address,uint256,uint256,uint256,address,address,uint256,uint256,bytes)",
                order.makerAddr,
                order.takerAssetAddr,
                order.makerAssetAddr,
                order.takerAssetAmount,
                order.makerAssetAmount,
                feeFactor,
                order.userAddr,
                order.receiverAddr,
                order.salt,
                order.deadline,
                sig
            );
    }
}

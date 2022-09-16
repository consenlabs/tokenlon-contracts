// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "contracts/PermanentStorage.sol";
import "contracts-test/mocks/MockStrategy.sol";

contract PermanentStorageTest is Test {
    event TransferOwnership(address newOperator);
    event SetPermission(bytes32 storageId, address role, bool enabled);
    event UpgradeAMMWrapper(address newAMMWrapper);
    event UpgradeRFQ(address newRFQ);
    event UpgradeLimitOrder(address newLimitOrder);
    event UpgradeWETH(address newWETH);
    event SetCurvePoolInfo(address makerAddr, address[] underlyingCoins, address[] coins, bool supportGetD);
    event SetRelayerValid(address relayer, bool valid);

    address user = address(0x133701);
    address relayer = address(0x133702);

    PermanentStorage permanentStorage;
    address strategy;

    bytes32 DEFAULT_TRANSACION_HASH = bytes32(uint256(1234));
    bytes32 DEFAULT_ALLOWFILL_HASH = bytes32(uint256(5566));
    address[] DEFAULT_RELAYERS = [relayer];
    bool[] DEFAULT_RELAYER_VALIDS = [true];

    address DEFAULT_CURVE_POOL_ADDRESS = address(0xcafe);
    address[] DEFAULT_CURVE_POOL_UNDERLYING_COINS = [address(0x123), address(0x456)];
    address[] DEFAULT_CURVE_POOL_COINS = [address(0x789), address(0xabc)];
    bool constant DEFAULT_CURVE_SUPPORT_GET_DX = true;

    // effectively a "beforeEach" block
    function setUp() public {
        // Deploy
        permanentStorage = new PermanentStorage();
        strategy = address(new MockStrategy());
        // Set this contract as operator
        permanentStorage.initialize(address(this));

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(relayer, "Relayer");
        vm.label(address(this), "TestingContract");
        vm.label(address(permanentStorage), "PermanentStorageContract");
        vm.label(address(strategy), "StrategyContract");
    }

    /*********************************
     *    Test: transferOwnership    *
     *********************************/

    function testCannotTransferOwnershipToZeroAddress() public {
        vm.expectRevert("PermanentStorage: operator can not be zero address");
        permanentStorage.transferOwnership(address(0));
    }

    function testCannotTransferOwnershipByNotOperator() public {
        vm.expectRevert("PermanentStorage: not the operator");
        vm.prank(user);
        permanentStorage.transferOwnership(user);
    }

    /*********************************
     *        Test: initialize       *
     *********************************/
    function testCannotInitializeToZeroAddress() public {
        PermanentStorage ps = new PermanentStorage();
        vm.expectRevert("PermanentStorage: operator can not be zero address");
        ps.initialize(address(0));
    }

    function testCannotInitializeAgain() public {
        PermanentStorage ps = new PermanentStorage();
        ps.initialize(address(this));
        assertEq(ps.version(), "5.4.0");
        assertEq(ps.operator(), address(this));

        vm.expectRevert("PermanentStorage: not upgrading from empty");
        ps.initialize(address(this));
    }

    /***********************************
     *      Test: upgrade strategy     *
     ***********************************/

    function testCannotUpgradeAMMWrapperByNotOperator() public {
        vm.expectRevert("PermanentStorage: not the operator");
        vm.prank(user);
        permanentStorage.upgradeAMMWrapper(strategy);
    }

    function testUpgradeAMMWrapper() public {
        assertEq(permanentStorage.ammWrapperAddr(), address(0));
        vm.expectEmit(true, true, true, true);
        emit UpgradeAMMWrapper(strategy);
        permanentStorage.upgradeAMMWrapper(strategy);
        assertEq(permanentStorage.ammWrapperAddr(), strategy);
    }

    function testCannotUpgradeRFQByNotOperator() public {
        vm.expectRevert("PermanentStorage: not the operator");
        vm.prank(user);
        permanentStorage.upgradeRFQ(strategy);
    }

    function testUpgradeRFQ() public {
        assertEq(permanentStorage.rfqAddr(), address(0));
        vm.expectEmit(true, true, true, true);
        emit UpgradeRFQ(strategy);
        permanentStorage.upgradeRFQ(strategy);
        assertEq(permanentStorage.rfqAddr(), strategy);
    }

    function testCannotUpgradeLimitOrderByNotOperator() public {
        vm.expectRevert("PermanentStorage: not the operator");
        vm.prank(user);
        permanentStorage.upgradeLimitOrder(strategy);
    }

    function testUpgradeLimitOrder() public {
        assertEq(permanentStorage.limitOrderAddr(), address(0));
        vm.expectEmit(true, true, true, true);
        emit UpgradeLimitOrder(strategy);
        permanentStorage.upgradeLimitOrder(strategy);
        assertEq(permanentStorage.limitOrderAddr(), strategy);
    }

    function testCannotUpgradeWETHByNotOperator() public {
        vm.expectRevert("PermanentStorage: not the operator");
        vm.prank(user);
        permanentStorage.upgradeWETH(strategy);
    }

    function testUpgradeWETH() public {
        assertEq(permanentStorage.wethAddr(), address(0));
        vm.expectEmit(true, true, true, true);
        emit UpgradeWETH(strategy);
        permanentStorage.upgradeWETH(strategy);
        assertEq(permanentStorage.wethAddr(), strategy);
    }

    /*********************************
     *      Test: setPermission      *
     *********************************/

    function testCannotSetPermissionByNotOperator() public {
        bytes32 storageId = permanentStorage.transactionSeenStorageId();
        vm.expectRevert("PermanentStorage: not the operator");
        vm.prank(user);
        permanentStorage.setPermission(storageId, user, true);
    }

    function testCannotSetPermissionWithInvalidRole() public {
        bytes32 storageId = permanentStorage.transactionSeenStorageId();
        vm.expectRevert("PermanentStorage: not a valid role");
        permanentStorage.setPermission(storageId, user, true);
    }

    function testSetPermission() public {
        bytes32 storageId = permanentStorage.transactionSeenStorageId();
        permanentStorage.upgradeAMMWrapper(strategy);

        assertFalse(permanentStorage.hasPermission(storageId, strategy));

        vm.expectEmit(true, true, true, true);
        emit SetPermission(storageId, strategy, true);

        permanentStorage.setPermission(storageId, strategy, true);
        assertTrue(permanentStorage.hasPermission(storageId, strategy));

        vm.expectEmit(true, true, true, true);
        emit SetPermission(storageId, strategy, false);

        permanentStorage.setPermission(storageId, strategy, false);
        assertFalse(permanentStorage.hasPermission(storageId, strategy));
    }

    /***************************************************
     *            Test: set TransactionSeen            *
     ***************************************************/

    function testCannotSetAMMTransactionSeenWithoutPermission() public {
        vm.expectRevert("PermanentStorage: has no permission");
        vm.prank(user);
        permanentStorage.setAMMTransactionSeen(DEFAULT_TRANSACION_HASH);
    }

    function testSetAMMTransactionSeen() public {
        permanentStorage.upgradeAMMWrapper(strategy);
        bytes32 storageId = permanentStorage.transactionSeenStorageId();
        permanentStorage.setPermission(storageId, strategy, true);

        vm.startPrank(strategy);
        assertFalse(permanentStorage.isAMMTransactionSeen(DEFAULT_TRANSACION_HASH));
        permanentStorage.setAMMTransactionSeen(DEFAULT_TRANSACION_HASH);
        assertTrue(permanentStorage.isAMMTransactionSeen(DEFAULT_TRANSACION_HASH));

        vm.expectRevert("PermanentStorage: transaction seen before");
        permanentStorage.setAMMTransactionSeen(DEFAULT_TRANSACION_HASH);
        vm.stopPrank();
    }

    function testCannotSetRFQTransactionSeenWithoutPermission() public {
        vm.expectRevert("PermanentStorage: has no permission");
        vm.prank(user);
        permanentStorage.setRFQTransactionSeen(DEFAULT_TRANSACION_HASH);
    }

    function testSetRFQTransactionSeen() public {
        permanentStorage.upgradeRFQ(strategy);
        bytes32 storageId = permanentStorage.transactionSeenStorageId();
        permanentStorage.setPermission(storageId, strategy, true);

        vm.startPrank(strategy);
        assertFalse(permanentStorage.isRFQTransactionSeen(DEFAULT_TRANSACION_HASH));
        permanentStorage.setRFQTransactionSeen(DEFAULT_TRANSACION_HASH);
        assertTrue(permanentStorage.isRFQTransactionSeen(DEFAULT_TRANSACION_HASH));

        vm.expectRevert("PermanentStorage: transaction seen before");
        permanentStorage.setRFQTransactionSeen(DEFAULT_TRANSACION_HASH);
        vm.stopPrank();
    }

    function testCannotSetLimitOrderTransactionSeenWithoutPermission() public {
        vm.expectRevert("PermanentStorage: has no permission");
        vm.prank(user);
        permanentStorage.setLimitOrderTransactionSeen(DEFAULT_TRANSACION_HASH);
    }

    function testSetLimitOrderTransactionSeen() public {
        permanentStorage.upgradeLimitOrder(strategy);
        bytes32 storageId = permanentStorage.transactionSeenStorageId();
        permanentStorage.setPermission(storageId, strategy, true);

        vm.startPrank(strategy);
        assertFalse(permanentStorage.isLimitOrderTransactionSeen(DEFAULT_TRANSACION_HASH));
        permanentStorage.setLimitOrderTransactionSeen(DEFAULT_TRANSACION_HASH);
        assertTrue(permanentStorage.isLimitOrderTransactionSeen(DEFAULT_TRANSACION_HASH));

        vm.expectRevert("PermanentStorage: transaction seen before");
        permanentStorage.setLimitOrderTransactionSeen(DEFAULT_TRANSACION_HASH);
        vm.stopPrank();
    }

    /***************************************************
     *            Test: set AllowFillSeen            *
     ***************************************************/

    function testCannotSetAllowFillSeenWithoutPermission() public {
        vm.expectRevert("PermanentStorage: has no permission");
        vm.prank(user);
        permanentStorage.setLimitOrderAllowFillSeen(DEFAULT_ALLOWFILL_HASH);
    }

    function testSetAllowFillSeen() public {
        permanentStorage.upgradeLimitOrder(strategy);
        bytes32 storageId = permanentStorage.allowFillSeenStorageId();
        permanentStorage.setPermission(storageId, strategy, true);

        vm.startPrank(strategy);
        assertFalse(permanentStorage.isLimitOrderAllowFillSeen(DEFAULT_ALLOWFILL_HASH));
        permanentStorage.setLimitOrderAllowFillSeen(DEFAULT_ALLOWFILL_HASH);
        assertTrue(permanentStorage.isLimitOrderAllowFillSeen(DEFAULT_ALLOWFILL_HASH));

        vm.expectRevert("PermanentStorage: allow fill seen before");
        permanentStorage.setLimitOrderAllowFillSeen(DEFAULT_ALLOWFILL_HASH);
        vm.stopPrank();
    }

    /********************************************
     *          Test: setRelayersValid          *
     ********************************************/

    function testCannotSetRelayersValidWithoutPermission() public {
        vm.expectRevert("PermanentStorage: has no permission");
        vm.prank(user);
        permanentStorage.setRelayersValid(DEFAULT_RELAYERS, DEFAULT_RELAYER_VALIDS);
    }

    function testCannotSetRelayersValidWithInvalidInputs() public {
        bytes32 storageId = permanentStorage.relayerValidStorageId();
        permanentStorage.setPermission(storageId, address(this), true);

        bool[] memory extraRelayerValids = new bool[](2);
        extraRelayerValids[0] = true;
        extraRelayerValids[1] = false;
        vm.expectRevert("PermanentStorage: inputs length mismatch");
        permanentStorage.setRelayersValid(DEFAULT_RELAYERS, extraRelayerValids);
    }

    function testSetRelayersValid() public {
        bytes32 storageId = permanentStorage.relayerValidStorageId();
        permanentStorage.setPermission(storageId, address(this), true);

        for (uint256 i = 0; i < DEFAULT_RELAYERS.length; i++) {
            address _relayer = DEFAULT_RELAYERS[i];
            bool valid = DEFAULT_RELAYER_VALIDS[i];
            assertFalse(permanentStorage.isRelayerValid(_relayer));
            vm.expectEmit(true, true, true, true);
            emit SetRelayerValid(_relayer, valid);
        }
        permanentStorage.setRelayersValid(DEFAULT_RELAYERS, DEFAULT_RELAYER_VALIDS);

        for (uint256 i = 0; i < DEFAULT_RELAYERS.length; i++) {
            address _relayer = DEFAULT_RELAYERS[i];
            assertTrue(permanentStorage.isRelayerValid(_relayer));
        }
    }

    /********************************************
     *          Test: setCurvePoolInfo          *
     ********************************************/

    function testCannotSetCurvePoolInfoWithoutPermission() public {
        vm.expectRevert("PermanentStorage: has no permission");
        vm.prank(user);
        permanentStorage.setCurvePoolInfo(
            DEFAULT_CURVE_POOL_ADDRESS,
            DEFAULT_CURVE_POOL_UNDERLYING_COINS,
            DEFAULT_CURVE_POOL_COINS,
            DEFAULT_CURVE_SUPPORT_GET_DX
        );
    }

    function testCannotGetCurvePoolInfoIfNotSet() public {
        address underlyingCoinA = DEFAULT_CURVE_POOL_UNDERLYING_COINS[0];
        address underlyingCoinB = DEFAULT_CURVE_POOL_UNDERLYING_COINS[1];
        vm.expectRevert("PermanentStorage: invalid pair");
        permanentStorage.getCurvePoolInfo(DEFAULT_CURVE_POOL_ADDRESS, underlyingCoinA, underlyingCoinB);

        address coinA = DEFAULT_CURVE_POOL_COINS[0];
        address coinB = DEFAULT_CURVE_POOL_COINS[1];
        vm.expectRevert("PermanentStorage: invalid pair");
        permanentStorage.getCurvePoolInfo(DEFAULT_CURVE_POOL_ADDRESS, coinA, coinB);
    }

    function testSetCurvePoolInfo() public {
        bytes32 storageId = permanentStorage.curveTokenIndexStorageId();
        permanentStorage.setPermission(storageId, address(this), true);

        vm.expectEmit(true, true, true, true);
        emit SetCurvePoolInfo(DEFAULT_CURVE_POOL_ADDRESS, DEFAULT_CURVE_POOL_UNDERLYING_COINS, DEFAULT_CURVE_POOL_COINS, DEFAULT_CURVE_SUPPORT_GET_DX);
        permanentStorage.setCurvePoolInfo(
            DEFAULT_CURVE_POOL_ADDRESS,
            DEFAULT_CURVE_POOL_UNDERLYING_COINS,
            DEFAULT_CURVE_POOL_COINS,
            DEFAULT_CURVE_SUPPORT_GET_DX
        );

        // Check underlying coin info
        for (uint256 i = 0; i < DEFAULT_CURVE_POOL_UNDERLYING_COINS.length; i++) {
            address underlyingCoinA = DEFAULT_CURVE_POOL_UNDERLYING_COINS[i];
            for (uint256 j = i; j < DEFAULT_CURVE_POOL_UNDERLYING_COINS.length; j++) {
                address underlyingCoinB = DEFAULT_CURVE_POOL_UNDERLYING_COINS[j];
                (int128 takerAssetIndex, int128 makerAssetIndex, uint16 swapMethod, bool supportGetDx) = permanentStorage.getCurvePoolInfo(
                    DEFAULT_CURVE_POOL_ADDRESS,
                    underlyingCoinA,
                    underlyingCoinB
                );
                assertGt(takerAssetIndex, 0);
                assertGt(makerAssetIndex, 0);
                assertEq(uint256(swapMethod), 2);
                assertEq(supportGetDx, DEFAULT_CURVE_SUPPORT_GET_DX);
            }
        }

        // Check coin info
        for (uint256 i = 0; i < DEFAULT_CURVE_POOL_COINS.length; i++) {
            address coinA = DEFAULT_CURVE_POOL_COINS[i];
            for (uint256 j = i; j < DEFAULT_CURVE_POOL_COINS.length; j++) {
                address coinB = DEFAULT_CURVE_POOL_COINS[j];
                (int128 takerAssetIndex, int128 makerAssetIndex, uint16 swapMethod, bool supportGetDx) = permanentStorage.getCurvePoolInfo(
                    DEFAULT_CURVE_POOL_ADDRESS,
                    coinA,
                    coinB
                );
                assertGt(takerAssetIndex, 0);
                assertGt(makerAssetIndex, 0);
                assertEq(uint256(swapMethod), 1);
                assertEq(supportGetDx, DEFAULT_CURVE_SUPPORT_GET_DX);
            }
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "contracts/UserProxy.sol";
import "contracts-test/mocks/MockStrategy.sol";

contract UserProxyTest is Test {
    event TearDownAllowanceTarget(uint256 tearDownTimeStamp);

    address user = address(0x133701);
    address relayer = address(0x133702);

    UserProxy userProxy;
    MockStrategy strategy;

    // effectively a "beforeEach" block
    function setUp() public {
        // Deploy
        userProxy = new UserProxy();
        strategy = new MockStrategy();
        // Set this contract as operator
        userProxy.initialize(address(this));

        // Deal 100 ETH to each account
        deal(user, 100 ether);
        deal(relayer, 100 ether);

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(relayer, "Relayer");
        vm.label(address(this), "TestingContract");
        vm.label(address(userProxy), "UserProxyContract");
        vm.label(address(strategy), "StrategyContract");
    }

    /*********************************
     *    Test: transferOwnership    *
     *********************************/

    function testCannotTransferOwnershipToZeroAddress() public {
        vm.expectRevert("UserProxy: operator can not be zero address");
        userProxy.transferOwnership(address(0));
    }

    function testCannotTransferOwnershipByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.transferOwnership(user);
    }

    /*********************************
     *        Test: initialize       *
     *********************************/

    function testCannotInitializeToZeroAddress() public {
        UserProxy up = new UserProxy();
        vm.expectRevert("UserProxy: operator can not be zero address");
        up.initialize(address(0));
    }

    function testCannotInitializeAgain() public {
        UserProxy up = new UserProxy();
        up.initialize(address(this));
        assertEq(up.version(), "5.3.0");
        assertEq(up.operator(), address(this));

        vm.expectRevert("UserProxy: not upgrading from empty");
        up.initialize(address(this));
    }

    /***************************************************
     *                Test: set AMM               *
     ***************************************************/

    function testCannotSetAMMStatusByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.setAMMStatus(true);
    }

    function testCannotUpgradeAMMWrappersByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.upgradeAMMWrapper(address(strategy), true);
    }

    function testSetAMMStatus() public {
        assertFalse(userProxy.isAMMEnabled());

        userProxy.setAMMStatus(true);

        assertTrue(userProxy.isAMMEnabled());
    }

    function testUpgradeAMMWrappers() public {
        assertFalse(userProxy.isAMMEnabled());
        assertEq(userProxy.ammWrapperAddr(), address(0));

        userProxy.upgradeAMMWrapper(address(strategy), true);

        assertTrue(userProxy.isAMMEnabled());
        assertEq(userProxy.ammWrapperAddr(), address(strategy));
    }

    /***************************************************
     *                Test: set RFQ               *
     ***************************************************/

    function testCannotSetRFQStatusByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.setRFQStatus(true);
    }

    function testCannotUpgradeRFQByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.upgradeRFQ(address(strategy), true);
    }

    function testSetRFQStatus() public {
        assertFalse(userProxy.isRFQEnabled());

        userProxy.setRFQStatus(true);

        assertTrue(userProxy.isRFQEnabled());
    }

    function testUpgradeRFQ() public {
        assertFalse(userProxy.isRFQEnabled());
        assertEq(userProxy.rfqAddr(), address(0));

        userProxy.upgradeRFQ(address(strategy), true);

        assertTrue(userProxy.isRFQEnabled());
        assertEq(userProxy.rfqAddr(), address(strategy));
    }

    /***************************************************
     *              Test: set LimitOrder               *
     ***************************************************/

    function testCannotSetLimitOrderStatusByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.setLimitOrderStatus(true);
    }

    function testCannotUpgradeLimitOrderByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.upgradeLimitOrder(address(strategy), true);
    }

    function testSetLimitOrderStatus() public {
        assertFalse(userProxy.isLimitOrderEnabled());

        userProxy.setLimitOrderStatus(true);

        assertTrue(userProxy.isLimitOrderEnabled());
    }

    function testUpgradeLimitOrder() public {
        assertFalse(userProxy.isLimitOrderEnabled());
        assertEq(userProxy.limitOrderAddr(), address(0));

        userProxy.upgradeLimitOrder(address(strategy), true);

        assertTrue(userProxy.isLimitOrderEnabled());
        assertEq(userProxy.limitOrderAddr(), address(strategy));
    }

    /***************************************************
     *               Test: set L2Deposit               *
     ***************************************************/

    function testCannotSetL2DepositStatusByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.setL2DepositStatus(true);
    }

    function testCannotUpgradeL2DepositByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.upgradeL2Deposit(address(strategy), true);
    }

    function testSetL2DepositStatus() public {
        assertFalse(userProxy.isL2DepositEnabled());

        userProxy.setL2DepositStatus(true);

        assertTrue(userProxy.isL2DepositEnabled());
    }

    function testUpgradeL2Deposit() public {
        assertFalse(userProxy.isL2DepositEnabled());
        assertEq(userProxy.l2DepositAddr(), address(0));

        userProxy.upgradeL2Deposit(address(strategy), true);

        assertTrue(userProxy.isL2DepositEnabled());
        assertEq(userProxy.l2DepositAddr(), address(strategy));
    }

    /***************************************************
     *                 Test: call AMM                  *
     ***************************************************/

    function testCannotToAMMWhenDisabled() public {
        userProxy.setAMMStatus(false);
        vm.expectRevert("UserProxy: AMM is disabled");
        userProxy.toAMM(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToAMMWithWrongFunction() public {
        userProxy.upgradeAMMWrapper(address(strategy), true);
        vm.expectRevert();
        userProxy.toAMM("0x");

        vm.expectRevert();
        userProxy.toAMM(abi.encode(userProxy.setAMMStatus.selector));
    }

    function testToAMM() public {
        userProxy.upgradeAMMWrapper(address(strategy), true);
        userProxy.toAMM(abi.encode(MockStrategy.execute.selector));
    }

    /***************************************************
     *                 Test: call RFQ                  *
     ***************************************************/

    function testCannotToRFQWhenDisabled() public {
        userProxy.setRFQStatus(false);
        vm.expectRevert("UserProxy: RFQ is disabled");
        userProxy.toRFQ(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToRFQByNotEOA() public {
        userProxy.setRFQStatus(true);
        vm.expectRevert("UserProxy: only EOA");
        userProxy.toRFQ(abi.encode(MockStrategy.execute.selector));
    }

    function testToRFQ() public {
        userProxy.upgradeRFQ(address(strategy), true);
        vm.prank(relayer, relayer);
        userProxy.toRFQ(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToRFQWithWrongFunction() public {
        userProxy.upgradeRFQ(address(strategy), true);
        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toRFQ("0x");

        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toRFQ(abi.encode(userProxy.setAMMStatus.selector));
    }

    /***************************************************
     *              Test: call LimitOrder               *
     ***************************************************/

    function testCannotToLimitOrderWhenDisabled() public {
        userProxy.setLimitOrderStatus(false);
        vm.expectRevert("UserProxy: Limit Order is disabled");
        userProxy.toLimitOrder(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToLimitOrderByNotEOA() public {
        userProxy.setLimitOrderStatus(true);
        vm.expectRevert("UserProxy: only EOA");
        userProxy.toLimitOrder(abi.encode(MockStrategy.execute.selector));
    }

    function testToLimitOrder() public {
        userProxy.upgradeLimitOrder(address(strategy), true);
        vm.prank(relayer, relayer);
        userProxy.toLimitOrder(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToLimitOrdertWithWrongFunction() public {
        userProxy.upgradeLimitOrder(address(strategy), true);
        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toLimitOrder("0x");

        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toLimitOrder(abi.encode(userProxy.setAMMStatus.selector));
    }

    /***************************************************
     *              Test: call L2Deposit               *
     ***************************************************/

    function testCannotToL2DepositWhenDisabled() public {
        userProxy.setL2DepositStatus(false);
        vm.expectRevert("UserProxy: L2 Deposit is disabled");
        userProxy.toL2Deposit(abi.encode(MockStrategy.execute.selector));
    }

    function testToL2Deposit() public {
        userProxy.upgradeL2Deposit(address(strategy), true);
        userProxy.toL2Deposit(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToL2DepositWithWrongFunction() public {
        userProxy.upgradeL2Deposit(address(strategy), true);
        vm.expectRevert();
        userProxy.toL2Deposit("0x");

        vm.expectRevert();
        userProxy.toL2Deposit(abi.encode(userProxy.setAMMStatus.selector));
    }

    /***************************************************
     *                Test: multicall                  *
     ***************************************************/

    function testMulticallAMMandRFQ() public {
        userProxy.upgradeAMMWrapper(address(strategy), true);
        userProxy.upgradeRFQ(address(strategy), false);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(UserProxy.toAMM.selector, MockStrategy.execute.selector);
        data[1] = abi.encodeWithSelector(UserProxy.toRFQ.selector, MockStrategy.execute.selector);
        vm.prank(relayer, relayer);
        // should succeed even RFQ is disabled
        userProxy.multicall(data, false);
    }

    function testMulticallRevertOnFail() public {
        userProxy.upgradeAMMWrapper(address(strategy), true);
        userProxy.upgradeRFQ(address(strategy), false);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(UserProxy.toAMM.selector, MockStrategy.execute.selector);
        data[1] = abi.encodeWithSelector(UserProxy.toRFQ.selector, MockStrategy.execute.selector);
        vm.prank(relayer, relayer);
        vm.expectRevert("Delegatecall failed");
        userProxy.multicall(data, true);
    }
}

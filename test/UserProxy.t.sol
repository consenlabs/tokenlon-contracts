// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "contracts/UserProxy.sol";
import "test/mocks/MockStrategy.sol";

contract UserProxyTest is Test {
    event TearDownAllowanceTarget(uint256 tearDownTimeStamp);
    event MulticallFailure(uint256 index, string reason);

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

    function testCannotNominateOpeatorToZeroAddress() public {
        vm.expectRevert("UserProxy: operator can not be zero address");
        userProxy.nominateNewOperator(address(0));
    }

    function testCannotNominateOpeatorByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.nominateNewOperator(user);
    }

    function testCannotAccpetOwnershipByNotNominated() public {
        address newOperator = makeAddr("newOperator");
        userProxy.nominateNewOperator(newOperator);

        vm.expectRevert("UserProxy: not nominated");
        userProxy.acceptOwnership();
    }

    function testTransferOwnership() public {
        address newOperator = makeAddr("newOperator");
        userProxy.nominateNewOperator(newOperator);

        vm.prank(newOperator);
        userProxy.acceptOwnership();
        assertEq(userProxy.operator(), newOperator);
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
     *                Test: set PMM               *
     ***************************************************/

    function testCannotSetPMMStatusByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.setPMMStatus(true);
    }

    function testCannotUpgradePMMByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.upgradePMM(address(strategy), true);
    }

    function testSetPMMStatus() public {
        assertFalse(userProxy.isPMMEnabled());

        userProxy.setPMMStatus(true);

        assertTrue(userProxy.isPMMEnabled());
    }

    function testUpgradePMM() public {
        assertFalse(userProxy.isPMMEnabled());
        assertEq(userProxy.pmmAddr(), address(0));

        userProxy.upgradePMM(address(strategy), true);

        assertTrue(userProxy.isPMMEnabled());
        assertEq(userProxy.pmmAddr(), address(strategy));
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
     *                Test: set RFQv2               *
     ***************************************************/

    function testCannotSetRFQv2StatusByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.setRFQv2Status(true);
    }

    function testCannotUpgradeRFQv2ByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.upgradeRFQv2(address(strategy), true);
    }

    function testSetRFQv2Status() public {
        assertFalse(userProxy.isRFQv2Enabled());

        userProxy.setRFQv2Status(true);

        assertTrue(userProxy.isRFQv2Enabled());
    }

    function testUpgradeRFQv2() public {
        assertFalse(userProxy.isRFQv2Enabled());
        assertEq(userProxy.rfqv2Addr(), address(0));

        userProxy.upgradeRFQv2(address(strategy), true);

        assertTrue(userProxy.isRFQv2Enabled());
        assertEq(userProxy.rfqv2Addr(), address(strategy));
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
     *                 Test: call PMM                  *
     ***************************************************/

    function testCannotToPMMWhenDisabled() public {
        userProxy.setPMMStatus(false);
        vm.expectRevert("UserProxy: PMM is disabled");
        userProxy.toPMM(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToPMMByNotEOA() public {
        userProxy.setPMMStatus(true);
        vm.expectRevert("UserProxy: only EOA");
        userProxy.toPMM(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToPMMWithWrongFunction() public {
        userProxy.upgradePMM(address(strategy), true);
        vm.expectRevert();
        userProxy.toPMM("0x");

        vm.expectRevert();
        userProxy.toPMM(abi.encode(userProxy.setAMMStatus.selector));
    }

    function testToPMM() public {
        userProxy.upgradePMM(address(strategy), true);
        vm.prank(relayer, relayer);
        userProxy.toPMM(abi.encode(MockStrategy.execute.selector));
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

    function testCannotToRFQWithWrongFunction() public {
        userProxy.upgradeRFQ(address(strategy), true);
        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toRFQ("0x");

        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toRFQ(abi.encode(userProxy.setAMMStatus.selector));
    }

    function testToRFQ() public {
        userProxy.upgradeRFQ(address(strategy), true);
        vm.prank(relayer, relayer);
        userProxy.toRFQ(abi.encode(MockStrategy.execute.selector));
    }

    /***************************************************
     *              Test: call RFQv2                   *
     ***************************************************/

    function testCannotToRFQv2WhenDisabled() public {
        userProxy.setRFQv2Status(false);
        vm.expectRevert("UserProxy: RFQv2 is disabled");
        userProxy.toRFQv2(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToRFQv2ByNotEOA() public {
        userProxy.setRFQv2Status(true);
        vm.expectRevert("UserProxy: only EOA");
        userProxy.toRFQv2(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToRFQv2WithWrongFunction() public {
        userProxy.upgradeRFQv2(address(strategy), true);
        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toRFQv2("0x");

        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toRFQv2(abi.encode(userProxy.setAMMStatus.selector));
    }

    function testToRFQv2() public {
        userProxy.upgradeRFQv2(address(strategy), true);
        vm.prank(relayer, relayer);
        userProxy.toRFQv2(abi.encode(MockStrategy.execute.selector));
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

    function testCannotToLimitOrdertWithWrongFunction() public {
        userProxy.upgradeLimitOrder(address(strategy), true);
        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toLimitOrder("0x");

        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toLimitOrder(abi.encode(userProxy.setAMMStatus.selector));
    }

    function testToLimitOrder() public {
        userProxy.upgradeLimitOrder(address(strategy), true);
        vm.prank(relayer, relayer);
        userProxy.toLimitOrder(abi.encode(MockStrategy.execute.selector));
    }

    /***************************************************
     *                Test: multicall                  *
     ***************************************************/

    function testMulticallNoRevertOnFail() public {
        MockStrategy mockAMM = new MockStrategy();
        mockAMM.setShouldFail(false);
        userProxy.upgradeAMMWrapper(address(mockAMM), true);
        MockStrategy mockRFQ = new MockStrategy();
        mockRFQ.setShouldFail(true);
        userProxy.upgradeRFQ(address(mockRFQ), true);

        bytes[] memory data = new bytes[](2);
        bytes memory strategyData = abi.encodeWithSelector(MockStrategy.execute.selector);
        data[0] = abi.encodeWithSelector(UserProxy.toAMM.selector, strategyData);
        data[1] = abi.encodeWithSelector(UserProxy.toRFQ.selector, strategyData);

        // MulticallFailure event should be emitted to indicate failures
        vm.expectEmit(true, true, true, true);
        emit MulticallFailure(1, "Execution failed");

        // tx should succeed even one of subcall failed (RFQ)
        vm.prank(relayer, relayer);

        (bool[] memory successes, bytes[] memory results) = userProxy.multicall(data, false);
        bytes[] memory expectedResult = new bytes[](2);
        expectedResult[1] = abi.encodeWithSignature("Error(string)", "Execution failed");
        assertEq(successes[0], true);
        assertEq0(results[0], expectedResult[0]);
        assertEq(successes[1], false);
        assertEq0(results[1], expectedResult[1]);
    }

    function testMulticallRevertOnFail() public {
        MockStrategy mockAMM = new MockStrategy();
        mockAMM.setShouldFail(false);
        userProxy.upgradeAMMWrapper(address(mockAMM), true);
        MockStrategy mockRFQ = new MockStrategy();
        mockRFQ.setShouldFail(true);
        userProxy.upgradeRFQ(address(mockRFQ), true);

        bytes[] memory data = new bytes[](2);
        bytes memory strategyData = abi.encodeWithSelector(MockStrategy.execute.selector);
        data[0] = abi.encodeWithSelector(UserProxy.toAMM.selector, strategyData);
        data[1] = abi.encodeWithSelector(UserProxy.toRFQ.selector, strategyData);

        // Should revert with message from MockStrategy
        vm.expectRevert("Execution failed");
        vm.prank(relayer, relayer);
        userProxy.multicall(data, true);
    }
}

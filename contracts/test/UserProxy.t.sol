// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

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
        // Setup
        // Set this contract as operator
        // prettier-ignore
        vm.store(
            address(userProxy), // address
            bytes32(uint256(0)), // key
            bytes32(uint256(address(this))) // value
        );
        // Set version
        // prettier-ignore
        vm.store(
            address(userProxy), // address
            bytes32(uint256(1)), // key
            bytes32(uint256(bytes32("5.2.0")) + uint256(5 * 2)) // value
        );

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
        vm.expectRevert("UserProxy: _limitOrderAddr should not be 0");
        userProxy.initialize(address(0));
    }

    function testCannotInitializeAgain() public {
        userProxy.initialize(address(this));

        vm.expectRevert("UserProxy: not upgrading from version 5.2.0");
        userProxy.initialize(address(this));
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

    function testSetPMMStatusByNotOperator() public {
        vm.expectRevert("UserProxy: not the operator");
        vm.prank(user);
        userProxy.setPMMStatus(true);
    }

    function testUpgradePMMByNotOperator() public {
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

    function testToPMM() public {
        userProxy.upgradePMM(address(strategy), true);
        vm.prank(relayer, relayer);
        userProxy.toPMM(abi.encode(MockStrategy.execute.selector));
    }

    function testCannotToPMMWithWrongFunction() public {
        userProxy.upgradePMM(address(strategy), true);
        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toPMM("0x");

        vm.expectRevert();
        vm.prank(relayer, relayer);
        userProxy.toPMM(abi.encode(userProxy.setAMMStatus.selector));
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
}

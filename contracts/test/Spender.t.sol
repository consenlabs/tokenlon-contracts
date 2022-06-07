// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "contracts/Spender.sol";
import "contracts/AllowanceTarget.sol";
import "contracts-test/mocks/MockERC20.sol";
import "contracts-test/mocks/MockDeflationaryERC20.sol";
import "contracts-test/mocks/MockNoReturnERC20.sol";
import "contracts-test/mocks/MockNoRevertERC20.sol";
import "contracts-test/utils/BalanceUtil.sol";

contract SpenderTest is BalanceUtil {
    using SafeERC20 for IERC20;

    event TearDownAllowanceTarget(uint256 tearDownTimeStamp);
    struct SpendWithPermit {
        address tokenAddr;
        address user;
        address recipient;
        uint256 amount;
        uint256 salt;
        uint64 expiry;
    }

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address recipient = address(0x133702);
    address unauthorized = address(0x133704);
    address[] wallet = [address(this), user, recipient];

    Spender spender;
    AllowanceTarget allowanceTarget;
    MockERC20 lon = new MockERC20("TOKENLON", "LON", 18);
    MockDeflationaryERC20 deflationaryERC20 = new MockDeflationaryERC20();
    MockNoReturnERC20 noReturnERC20 = new MockNoReturnERC20();
    MockNoRevertERC20 noRevertERC20 = new MockNoRevertERC20();
    IERC20[] tokens = [IERC20(address(deflationaryERC20)), IERC20(address(noReturnERC20)), IERC20(address(noRevertERC20))];

    uint64 EXPIRY = uint64(block.timestamp + 1);
    SpendWithPermit DEFAULT_SPEND_WITH_PERMIT;

    // effectively a "beforeEach" block
    function setUp() public {
        // Deploy
        spender = new Spender(
            address(this), // This contract would be the operator
            new address[](0)
        );
        allowanceTarget = new AllowanceTarget(address(spender));
        // Setup
        spender.setAllowanceTarget(address(allowanceTarget));
        spender.authorize(wallet);

        // Deal 100 ETH to each account
        for (uint256 i = 0; i < wallet.length; i++) {
            deal(wallet[i], 100 ether);
        }
        // Mint 10k tokens to user
        lon.mint(user, 10000 * 1e18);
        // User approve AllowanceTarget
        vm.startPrank(user);
        lon.approve(address(allowanceTarget), type(uint256).max);
        // Set user's mock tokens balance and approve
        for (uint256 j = 0; j < tokens.length; j++) {
            setERC20Balance(address(tokens[j]), user, 100);
            tokens[j].safeApprove(address(allowanceTarget), type(uint256).max);
        }
        vm.stopPrank();

        // Default SpendWithPermit
        // prettier-ignore
        DEFAULT_SPEND_WITH_PERMIT = SpendWithPermit(
            address(lon), // tokenAddr
            user, // user
            recipient, // receipient
            100 * 1e18, // amount
            uint256(1234), // salt
            EXPIRY // expiry
        );

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(recipient, "Recipient");
        vm.label(unauthorized, "Unauthorized");
        vm.label(address(this), "TestingContract");
        vm.label(address(spender), "SpenderContract");
        vm.label(address(allowanceTarget), "AllowanceTargetContract");
        vm.label(address(lon), "LON");
    }

    /*********************************
     *    Test: set new operator     *
     *********************************/

    function testCannotSetNewOperatorByUser() public {
        vm.expectRevert("Spender: not the operator");
        vm.prank(user);
        spender.setNewOperator(user);
    }

    function testSetNewOperator() public {
        spender.setNewOperator(user);
        assertEq(spender.pendingOperator(), user);
    }

    function testCannotAcceptAsOperatorByNonPendingOperator() public {
        spender.setNewOperator(user);
        vm.prank(unauthorized);
        vm.expectRevert("Spender: only nominated one can accept as new operator");
        spender.acceptAsOperator();
    }

    function testAcceptAsOperator() public {
        spender.setNewOperator(user);
        vm.prank(user);
        spender.acceptAsOperator();
        assertEq(spender.operator(), user);
    }

    /***************************************************
     *       Test: AllowanceTarget interaction         *
     ***************************************************/

    function testSetNewSpender() public {
        Spender newSpender = new Spender(address(this), new address[](0));

        spender.setNewSpender(address(newSpender));
        vm.warp(block.timestamp + 1 days);

        allowanceTarget.completeSetSpender();
        assertEq(allowanceTarget.spender(), address(newSpender));
    }

    function testTeardownAllowanceTarget() public {
        vm.expectEmit(false, false, false, true);
        emit TearDownAllowanceTarget(block.timestamp);

        spender.teardownAllowanceTarget();
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(allowanceTarget.slot)
        }
        assertEq(size, 0, "AllowanceTarget did not selfdestruct");
    }

    /*********************************
     *        Test: authorize        *
     *********************************/

    function testCannotAuthorizeByUser() public {
        vm.expectRevert("Spender: not the operator");
        vm.prank(user);
        spender.authorize(wallet);
    }

    function testAuthorizeWithoutTimelock() public {
        assertFalse(spender.timelockActivated());
        assertFalse(spender.isAuthorized(unauthorized));

        address[] memory authList = new address[](1);
        authList[0] = unauthorized;
        spender.authorize(authList);
        assertTrue(spender.isAuthorized(unauthorized));
    }

    function testAuthorizeWithTimelock() public {
        vm.warp(block.timestamp + 1 days + 1 seconds);
        spender.activateTimelock();

        assertTrue(spender.timelockActivated());
        assertFalse(spender.isAuthorized(unauthorized));

        address[] memory authList = new address[](1);
        authList[0] = unauthorized;
        spender.authorize(authList);

        vm.warp(block.timestamp + 1 days);

        vm.prank(user);
        spender.completeAuthorize();
        assertTrue(spender.isAuthorized(unauthorized));
    }

    function testDeauthorize() public {
        for (uint256 i = 0; i < wallet.length; i++) {
            assertTrue(spender.isAuthorized(wallet[i]));
        }

        spender.deauthorize(wallet);

        for (uint256 i = 0; i < wallet.length; i++) {
            assertFalse(spender.isAuthorized(wallet[i]));
        }
    }

    /*********************************
     *     Test: spendFromUser       *
     *********************************/

    function testCannotSpendFromUserByNotAuthorized() public {
        vm.expectRevert("Spender: not authorized");
        vm.prank(unauthorized);
        spender.spendFromUser(user, address(lon), 100);
    }

    function testCannotSpendFromUserWithBlakclistedToken() public {
        address[] memory blacklistAddress = new address[](1);
        blacklistAddress[0] = address(lon);
        bool[] memory blacklistBool = new bool[](1);
        blacklistBool[0] = true;
        spender.blacklist(blacklistAddress, blacklistBool);

        vm.expectRevert("Spender: token is blacklisted");
        spender.spendFromUser(user, address(lon), 100);
    }

    function testCannotSpendFromUserWithNoReturnValueToken() public {
        uint256 userBalance = noReturnERC20.balanceOf(user);
        vm.expectRevert("Spender: ERC20 transferFrom failed");
        spender.spendFromUser(user, address(noReturnERC20), userBalance);
    }

    function testCannotSpendFromUserWithReturnFalseToken() public {
        uint256 userBalance = noRevertERC20.balanceOf(user);
        vm.expectRevert("Spender: ERC20 transferFrom failed");
        spender.spendFromUser(user, address(noRevertERC20), userBalance + 1);
    }

    function testCannotSpendFromUserWithDeflationaryToken() public {
        vm.expectRevert("Spender: ERC20 transferFrom amount mismatch");
        spender.spendFromUser(user, address(deflationaryERC20), 100);
    }

    function testSpendFromUser() public {
        assertEq(lon.balanceOf(address(this)), 0);

        spender.spendFromUser(user, address(lon), 100);

        assertEq(lon.balanceOf(address(this)), 100);
    }

    /*********************************
     *     Test: spendFromUserTo     *
     *********************************/

    function testCannotSpendFromUserToByNotAuthorized() public {
        vm.expectRevert("Spender: not authorized");
        vm.prank(unauthorized);
        spender.spendFromUserTo(user, address(lon), unauthorized, 100);
    }

    function testCannotSpendFromUserToWithBlakclistedToken() public {
        address[] memory blacklistAddress = new address[](1);
        blacklistAddress[0] = address(lon);
        bool[] memory blacklistBool = new bool[](1);
        blacklistBool[0] = true;
        spender.blacklist(blacklistAddress, blacklistBool);

        vm.expectRevert("Spender: token is blacklisted");
        spender.spendFromUserTo(user, address(lon), recipient, 100);
    }

    function testCannotSpendFromUserToWithNoReturnValueToken() public {
        uint256 userBalance = noReturnERC20.balanceOf(user);
        vm.expectRevert("Spender: ERC20 transferFrom failed");
        spender.spendFromUserTo(user, address(noReturnERC20), recipient, userBalance);
    }

    function testCannotSpendFromUserToWithReturnFalseToken() public {
        uint256 userBalance = noRevertERC20.balanceOf(user);
        vm.expectRevert("Spender: ERC20 transferFrom failed");
        spender.spendFromUserTo(user, address(noRevertERC20), recipient, userBalance + 1);
    }

    function testCannotSpendFromUserToWithDeflationaryToken() public {
        vm.expectRevert("Spender: ERC20 transferFrom amount mismatch");
        spender.spendFromUserTo(user, address(deflationaryERC20), recipient, 100);
    }

    function testSpendFromUserTo() public {
        assertEq(lon.balanceOf(recipient), 0);

        spender.spendFromUserTo(user, address(lon), recipient, 100);

        assertEq(lon.balanceOf(recipient), 100);
    }
}

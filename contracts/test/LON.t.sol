// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/Lon.sol";
import "contracts-test/mocks/MockERC20.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/BalanceUtil.sol";

contract LONTest is Test, BalanceUtil {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address spender = address(0x133701);
    address emergencyRecipient = address(0x133702);

    Lon lon = new Lon(address(this), emergencyRecipient);

    uint256 DEADLINE = block.timestamp + 1;

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonces;
        uint256 deadline;
    }
    Permit DEFAULT_PERMIT;

    // effectively a "beforeEach" block
    function setUp() public {
        // Deal 100 ETH to each account
        vm.deal(user, 100 ether);

        // Default permit
        DEFAULT_PERMIT = Permit(
            user, // owner
            spender, // spender
            1e18, // value
            0, // nonce
            DEADLINE // deadline
        );

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(address(this), "TestingContract");
        vm.label(address(lon), "LONContract");
        vm.label(emergencyRecipient, "EmergencyRecipient");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupLON() public {
        assertEq(lon.owner(), address(this));
        assertEq(lon.minter(), address(this));
        assertEq(lon.emergencyRecipient(), emergencyRecipient);
    }

    /*********************************
     *        Test: setMinter        *
     *********************************/

    function testCannotSetMinterByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        lon.setMinter(user);
    }

    function testSetMinter() public {
        lon.setMinter(user);
        assertEq(address(lon.minter()), user);
    }

    /*********************************
     *          Test: mint           *
     *********************************/

    function testCannotMintByNotMinter() public {
        vm.expectRevert("not minter");
        vm.prank(user);
        lon.mint(user, 1e18);
    }

    function testCannotMintBeyondCap() public {
        uint256 excessAmount = lon.cap() + 1;
        vm.expectRevert("cap exceeded");
        lon.mint(user, excessAmount);
    }

    function testCannotMintToZeroAddress() public {
        vm.expectRevert("zero address");
        lon.mint(address(0), 1e18);
    }

    function testMint() public {
        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        lon.mint(user, 1e18);
        userLon.assertChange(int256(1e18));
    }

    /*********************************
     *          Test: burn           *
     *********************************/

    function testCannotBurnMoreThanOwned() public {
        lon.mint(user, 1e18);
        uint256 excessAmount = lon.balanceOf(user) + 1;
        vm.expectRevert("ERC20: burn amount exceeds balance");
        vm.prank(user);
        lon.burn(excessAmount);
    }

    function testBurn() public {
        lon.mint(user, 1e18);
        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        vm.prank(user);
        lon.burn(1e18);
        userLon.assertChange(-int256(1e18));
    }

    /*********************************
     *   Test: emergencyWithdraw     *
     *********************************/

    function testEmergencyWithdraw() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        dai.mint(address(lon), 1e18);
        BalanceSnapshot.Snapshot memory lonDai = BalanceSnapshot.take(address(lon), address(dai));
        BalanceSnapshot.Snapshot memory emergencyRecipientDai = BalanceSnapshot.take(emergencyRecipient, address(dai));
        vm.prank(user);
        lon.emergencyWithdraw(dai);
        lonDai.assertChange(-int256(1e18));
        emergencyRecipientDai.assertChange(int256(1e18));
    }

    /*********************************
     *         Test: permit          *
     *********************************/

    function testCannotPermitByZeroAddress() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.owner = address(0);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("zero address");
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWithExpiredPermit() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("permit is expired");
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWithInvalidUserSig() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(otherPrivateKey, permit);

        vm.expectRevert("invalid signature");
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testPermit() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        uint256 nonceBefore = lon.nonces(user);
        uint256 allowanceBefore = lon.allowance(permit.owner, permit.spender);
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
        uint256 nonceAfter = lon.nonces(user);
        uint256 allowanceAfter = lon.allowance(permit.owner, permit.spender);

        assertEq(nonceAfter, nonceBefore + 1);
        assertEq(allowanceAfter, allowanceBefore + permit.value);
    }

    function testCannotPermitWithSameSignatureAgain() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.expectRevert("invalid signature");
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function _getPermitHash(Permit memory permit) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = lon.PERMIT_TYPEHASH();
        return keccak256(abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonces, permit.deadline));
    }

    function _getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 DOMAIN_SEPARATOR = lon.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, DOMAIN_SEPARATOR, structHash));
    }

    function _signPermit(uint256 privateKey, Permit memory permit)
        internal
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        bytes32 permitHash = _getPermitHash(permit);
        bytes32 EIP712SignDigest = _getEIP712Hash(permitHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return (v, r, s);
    }
}

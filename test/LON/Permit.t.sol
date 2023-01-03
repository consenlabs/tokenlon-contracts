// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/LON/Setup.t.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";

contract TestLONPermit is TestLON {
    uint256 otherPrivateKey = uint256(2);

    uint256 DEADLINE = block.timestamp + 1;

    address spender = address(0x133701);

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonces;
        uint256 deadline;
    }
    Permit DEFAULT_PERMIT;

    // Override the "beforeEach" block
    function setUp() public override {
        TestLON.setUp();

        // Default permit
        DEFAULT_PERMIT = Permit(
            user, // owner
            spender, // spender
            uint256(1e18), // value
            uint256(0), // nonce
            DEADLINE // deadline
        );
    }

    function testCannotPermitByZeroAddress() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.owner = address(0);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("zero address");
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWhenExpired() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("permit is expired");
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWithInvalidSignature() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(otherPrivateKey, permit);

        vm.expectRevert("invalid signature");
        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitIfSignAgain() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        lon.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

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

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _signPermit(uint256 privateKey, Permit memory permit)
        internal
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        bytes32 permitHash = _getPermitHash(permit);
        bytes32 EIP712SignDigest = getEIP712Hash(lon.DOMAIN_SEPARATOR(), permitHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return (v, r, s);
    }

    function _getPermitHash(Permit memory permit) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = lon.PERMIT_TYPEHASH();
        return keccak256(abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonces, permit.deadline));
    }
}

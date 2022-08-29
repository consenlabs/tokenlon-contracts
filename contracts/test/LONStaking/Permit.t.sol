// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";
import { getEIP712Hash } from "contracts-test/utils/Sig.sol";

contract TestLONStakingPermit is TestLONStaking {
    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonces;
        uint256 deadline;
    }
    Permit DEFAULT_PERMIT;

    // effectively a "beforeEach" block
    function setUp() public override {
        TestLONStaking.setUp();

        // Default permit
        DEFAULT_PERMIT = Permit(
            user, // owner
            spender, // spender
            1e18, // value
            0, // nonce
            DEADLINE // deadline
        );
    }

    function testCannotPermitByZeroAddress() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.owner = address(0);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("owner is zero address");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWhenPermitExpired() public {
        Permit memory permit = DEFAULT_PERMIT;
        permit.deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        vm.expectRevert("permit expired");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWithInvalidSignature() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(otherPrivateKey, permit);

        vm.expectRevert("invalid signature");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testCannotPermitWhenSignatureSeenBefore() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.expectRevert("invalid signature");
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testPermit() public {
        Permit memory permit = DEFAULT_PERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(userPrivateKey, permit);

        uint256 nonceBefore = lonStaking.nonces(user);
        uint256 allowanceBefore = lonStaking.allowance(permit.owner, permit.spender);
        lonStaking.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
        uint256 nonceAfter = lonStaking.nonces(user);
        uint256 allowanceAfter = lonStaking.allowance(permit.owner, permit.spender);

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
        bytes32 EIP712SignDigest = getEIP712Hash(lonStaking.DOMAIN_SEPARATOR(), permitHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return (v, r, s);
    }

    function _getPermitHash(Permit memory permit) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = lonStaking.PERMIT_TYPEHASH();
        return keccak256(abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonces, permit.deadline));
    }
}

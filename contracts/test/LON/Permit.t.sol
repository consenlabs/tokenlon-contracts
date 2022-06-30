// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/LON/Setup.t.sol";

contract TestLONPermit is TestLON {
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
}

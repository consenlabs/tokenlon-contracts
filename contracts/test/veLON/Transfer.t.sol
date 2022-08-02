// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "contracts/test/veLON/Setup.t.sol";

contract TestVeLONTransfer is TestVeLON {
    function testTransferByOwner() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.startPrank(user);
        veLon.approve(other, tokenId);
        veLon.transferFrom(user, other, tokenId);
        vm.stopPrank();
        assertEq(veLon.ownerOf(tokenId), other);
    }

    function testTransferByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(user);
        veLon.approve(other, tokenId);
        vm.prank(other);
        veLon.transferFrom(user, other, tokenId);
        vm.stopPrank();
        assertEq(veLon.ownerOf(tokenId), other);
    }
}

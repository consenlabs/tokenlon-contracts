// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Ownable } from "contracts/abstracts/Ownable.sol";

contract OwnableTest is Test {
    OwnableTestContract ownable;

    address owner = makeAddr("owner");
    address newOwner = makeAddr("newOwner");
    address nominatedOwner = makeAddr("nominatedOwner");
    address otherAccount = makeAddr("otherAccount");

    function setUp() public {
        vm.startPrank(owner);
        ownable = new OwnableTestContract(owner);
        vm.stopPrank();
    }

    function testOwnableInitialState() public {
        assertEq(ownable.owner(), owner);
    }

    function testCannotInitiateOwnerWithZeroAddress() public {
        vm.expectRevert(Ownable.ZeroOwner.selector);
        new OwnableTestContract(address(0));
    }

    function testCannotAcceptOwnershipWithOtherAccount() public {
        vm.startPrank(owner);
        ownable.nominateNewOwner(newOwner);
        vm.stopPrank();

        vm.startPrank(otherAccount);
        vm.expectRevert(Ownable.NotNominated.selector);
        ownable.acceptOwnership();
        vm.stopPrank();
    }

    function testCannotRenounceOwnershipWithNominatedOwner() public {
        vm.startPrank(owner);
        ownable.nominateNewOwner(newOwner);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(Ownable.NominationExists.selector);
        ownable.renounceOwnership();
        vm.stopPrank();
    }

    function testCannotRenounceOwnershipWithOtherAccount() public {
        vm.startPrank(otherAccount);
        vm.expectRevert(Ownable.NotOwner.selector);
        ownable.renounceOwnership();
        vm.stopPrank();
    }

    function testCannotNominateNewOwnerWithOtherAccount() public {
        vm.startPrank(otherAccount);
        vm.expectRevert(Ownable.NotOwner.selector);
        ownable.nominateNewOwner(newOwner);
        vm.stopPrank();
    }

    function testAcceptOwnership() public {
        vm.startPrank(owner);
        ownable.nominateNewOwner(newOwner);
        vm.stopPrank();

        assertEq(ownable.nominatedOwner(), newOwner);

        vm.expectEmit(true, true, false, false);
        emit Ownable.OwnerChanged(owner, newOwner);

        vm.startPrank(newOwner);
        ownable.acceptOwnership();
        vm.stopPrank();
        vm.snapshotGasLastCall("Ownable", "acceptOwnership(): testAcceptOwnership");

        assertEq(ownable.owner(), newOwner);
        assertEq(ownable.nominatedOwner(), address(0));
    }

    function testRenounceOwnership() public {
        vm.expectEmit(true, true, false, false);
        emit Ownable.OwnerChanged(owner, address(0));

        vm.startPrank(owner);
        ownable.renounceOwnership();
        vm.stopPrank();
        vm.snapshotGasLastCall("Ownable", "renounceOwnership(): testRenounceOwnership");

        assertEq(ownable.owner(), address(0));
    }

    function testNominateNewOwner() public {
        vm.expectEmit(true, false, false, false);
        emit Ownable.OwnerNominated(newOwner);

        vm.startPrank(owner);
        ownable.nominateNewOwner(newOwner);
        vm.stopPrank();
        vm.snapshotGasLastCall("Ownable", "nominateNewOwner(): testNominateNewOwner");

        assertEq(ownable.nominatedOwner(), newOwner);
    }
}

contract OwnableTestContract is Ownable {
    constructor(address _owner) Ownable(_owner) {}
}

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
        vm.prank(owner);
        ownable = new OwnableTestContract(owner);
    }

    function testOwnableInitialState() public {
        assertEq(ownable.owner(), owner);
    }

    function testCannotInitiateOwnerWithZeroAddress() public {
        vm.expectRevert(Ownable.ZeroOwner.selector);
        new OwnableTestContract(address(0));
    }

    function testCannotAcceptOwnershipWithOtherAccount() public {
        vm.prank(owner);
        ownable.nominateNewOwner(newOwner);

        vm.prank(otherAccount);
        vm.expectRevert(Ownable.NotNominated.selector);
        ownable.acceptOwnership();
    }

    function testCannotRenounceOwnershipWithNominatedOwner() public {
        vm.prank(owner);
        ownable.nominateNewOwner(newOwner);

        vm.prank(owner);
        vm.expectRevert(Ownable.NominationExists.selector);
        ownable.renounceOwnership();
    }

    function testCannotRenounceOwnershipWithOtherAccount() public {
        vm.prank(otherAccount);
        vm.expectRevert(Ownable.NotOwner.selector);
        ownable.renounceOwnership();
    }

    function testCannotNominateNewOwnerWithOtherAccount() public {
        vm.prank(otherAccount);
        vm.expectRevert(Ownable.NotOwner.selector);
        ownable.nominateNewOwner(newOwner);
    }

    function testAcceptOwnership() public {
        vm.prank(owner);
        ownable.nominateNewOwner(newOwner);

        assertEq(ownable.nominatedOwner(), newOwner);

        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit Ownable.OwnerChanged(owner, newOwner);
        ownable.acceptOwnership();

        assertEq(ownable.owner(), newOwner);
        assertEq(ownable.nominatedOwner(), address(0));
    }

    function testRenounceOwnership() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit Ownable.OwnerChanged(owner, address(0));
        ownable.renounceOwnership();

        assertEq(ownable.owner(), address(0));
    }

    function testNominateNewOwner() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Ownable.OwnerNominated(newOwner);
        ownable.nominateNewOwner(newOwner);

        assertEq(ownable.nominatedOwner(), newOwner);
    }
}

contract OwnableTestContract is Ownable {
    constructor(address _owner) Ownable(_owner) {}
}

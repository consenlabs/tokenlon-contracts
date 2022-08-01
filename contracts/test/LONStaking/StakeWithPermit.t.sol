// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";

contract TestLONStakingStakeWithPermit is TestLONStaking {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;
    struct StakeWithPermit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonces;
        uint256 deadline;
    }
    StakeWithPermit DEFAULT_STAKEWITHPERMIT;

    // effectively a "beforeEach" block
    function setUp() public override {
        TestLONStaking.setUp();

        // Default stakeWithPermit
        DEFAULT_STAKEWITHPERMIT = StakeWithPermit(
            user, // owner
            address(lonStaking), // spender
            DEFAULT_STAKE_AMOUNT, // value
            0, // nonce
            DEADLINE // deadline
        );
    }

    function testCannotStakeWhenPermitExpired() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        stakeWithPermit.deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        vm.expectRevert("permit is expired");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    function testCannotStakeWithInvalidSignature() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(otherPrivateKey, stakeWithPermit);

        vm.expectRevert("invalid signature");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    function testCannotStakeWhenPaused() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        lonStaking.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    function testCannotStakeWhenSignatureSeenBefore() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);

        vm.expectRevert("invalid signature");
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
    }

    function testStakeWithPermit() public {
        StakeWithPermit memory stakeWithPermit = DEFAULT_STAKEWITHPERMIT;
        (uint8 v, bytes32 r, bytes32 s) = _signStakeWithPermit(userPrivateKey, stakeWithPermit);

        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        BalanceSnapshot.Snapshot memory lonStakingLon = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory userXLON = BalanceSnapshot.take(user, address(lonStaking));
        uint256 stakeAmount = stakeWithPermit.value;
        uint256 expectedStakeAmount = _getExpectedXLON(stakeAmount);

        uint256 nonceBefore = lon.nonces(user);
        vm.prank(user);
        lonStaking.stakeWithPermit(stakeWithPermit.value, stakeWithPermit.deadline, v, r, s);
        uint256 nonceAfter = lon.nonces(user);

        assertEq(nonceAfter, nonceBefore + 1);
        userLon.assertChange(-int256(stakeAmount));
        lonStakingLon.assertChange(int256(stakeAmount));
        userXLON.assertChange(int256(expectedStakeAmount));
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _getStakeWithPermitHash(StakeWithPermit memory stakeWithPermit) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = lon.PERMIT_TYPEHASH();
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    stakeWithPermit.owner,
                    stakeWithPermit.spender,
                    stakeWithPermit.value,
                    stakeWithPermit.nonces,
                    stakeWithPermit.deadline
                )
            );
    }

    function _getLONEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 DOMAIN_SEPARATOR = lon.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, DOMAIN_SEPARATOR, structHash));
    }

    function _signStakeWithPermit(uint256 privateKey, StakeWithPermit memory stakeWithPermit)
        internal
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        bytes32 stakeWithPermitHash = _getStakeWithPermitHash(stakeWithPermit);
        bytes32 EIP712SignDigest = _getLONEIP712Hash(stakeWithPermitHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return (v, r, s);
    }
}

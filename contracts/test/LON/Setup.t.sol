// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/Lon.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestLON is Test {
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
    function setUp() public virtual {
        // Deal 100 ETH to each account
        deal(user, 100 ether);

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
        bytes32 EIP712SignDigest = _getEIP712Hash(permitHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return (v, r, s);
    }

    function _getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 DOMAIN_SEPARATOR = lon.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, DOMAIN_SEPARATOR, structHash));
    }

    function _getPermitHash(Permit memory permit) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = lon.PERMIT_TYPEHASH();
        return keccak256(abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonces, permit.deadline));
    }
}

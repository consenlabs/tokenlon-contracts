// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/Lon.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TestLON is Test {
    uint256 userPrivateKey = uint256(1);

    address user = vm.addr(userPrivateKey);
    address emergencyRecipient = address(0x133702);

    Lon lon = new Lon(address(this), emergencyRecipient);

    // effectively a "beforeEach" block
    function setUp() public virtual {
        // Deal 100 ETH to each account
        deal(user, 100 ether);

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(address(this), "TestingContract");
        vm.label(address(lon), "LONContract");
        vm.label(emergencyRecipient, "EmergencyRecipient");
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 DOMAIN_SEPARATOR = lon.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, DOMAIN_SEPARATOR, structHash));
    }
}

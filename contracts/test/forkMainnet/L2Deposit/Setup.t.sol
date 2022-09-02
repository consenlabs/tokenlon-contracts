// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "contracts-test/utils/BalanceUtil.sol";
import "contracts-test/utils/StrategySharedSetup.sol";
import { getEIP712Hash } from "contracts-test/utils/Sig.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "contracts/L2Deposit.sol";
import "contracts/utils/SignatureValidator.sol";
import "contracts/utils/L2DepositLibEIP712.sol";
import "contracts/interfaces/IArbitrumL1GatewayRouter.sol";
import "contracts/interfaces/IArbitrumL1Inbox.sol";
import "contracts/interfaces/IOptimismL1StandardBridge.sol";

contract TestL2Deposit is StrategySharedSetup {
    using SafeERC20 for IERC20;

    uint256 userPrivateKey = uint256(1);
    uint256 bobPrivateKey = uint256(2);
    address user = vm.addr(userPrivateKey);
    address arbitrumL2RefundCollector = address(0x133702);

    L2Deposit l2Deposit;

    // Arbitrum
    IArbitrumL1GatewayRouter arbitrumL1GatewayRouter = IArbitrumL1GatewayRouter(ARBITRUM_L1_GATEWAY_ROUTER_ADDR);
    IArbitrumL1Inbox arbitrumL1Inbox = IArbitrumL1Inbox(ARBITRUM_L1_INBOX_ADDR);
    IERC20 arbitrumLONAddr = IERC20(arbitrumL1GatewayRouter.calculateL2TokenAddress(LON_ADDRESS));

    // Optimism
    IOptimismL1StandardBridge optimismL1StandardBridge = IOptimismL1StandardBridge(OPTIMISM_L1_STANDARD_BRIDGE_ADDR);

    IERC20[] tokens = [IERC20(LON_ADDRESS)];
    uint256 DEFAULT_DEADLINE = block.timestamp + 1;
    L2DepositLibEIP712.Deposit DEFAULT_DEPOSIT;

    event Deposited(
        L2DepositLibEIP712.L2Identifier indexed l2Identifier,
        address indexed l1TokenAddr,
        address l2TokenAddr,
        address indexed sender,
        address recipient,
        uint256 amount,
        bytes data,
        bytes bridgeResponse
    );

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        setUpSystemContracts();

        // Set user token balance and approve
        setEOABalanceAndApprove(user, tokens, 100);

        DEFAULT_DEPOSIT = L2DepositLibEIP712.Deposit(
            L2DepositLibEIP712.L2Identifier.Arbitrum, // l2Identifier
            LON_ADDRESS, // l1TokenAddr
            address(arbitrumLONAddr), // l2TokenAddr
            user, // sender
            user, // recipient
            1 ether, // amount
            1234, // salt
            DEFAULT_DEADLINE, // expiry
            bytes("") // data
        );

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(arbitrumL2RefundCollector, "arbitrumL2RefundCollector");
        vm.label(address(this), "TestingContract");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        l2Deposit = new L2Deposit(
            address(this), // This contract would be the owner
            address(userProxy),
            ISpender(address(spender)),
            permanentStorage,
            arbitrumL1GatewayRouter,
            arbitrumL1Inbox,
            arbitrumL2RefundCollector,
            optimismL1StandardBridge
        );

        // Hook up L2Deposit
        userProxy.upgradeL2Deposit(address(l2Deposit), true);
        permanentStorage.upgradeL2Deposit(address(l2Deposit));
        permanentStorage.setPermission(permanentStorage.l2DepositSeenStorageId(), address(l2Deposit), true);
        return address(l2Deposit);
    }

    function _signDeposit(uint256 privateKey, L2DepositLibEIP712.Deposit memory deposit) internal returns (bytes memory) {
        bytes32 depositHash = L2DepositLibEIP712._getDepositHash(deposit);
        bytes32 EIP712SignDigest = getEIP712Hash(l2Deposit.EIP712_DOMAIN_SEPARATOR(), depositHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }
}

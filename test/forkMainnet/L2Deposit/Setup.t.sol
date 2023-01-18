// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "test/utils/StrategySharedSetup.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "contracts/L2Deposit.sol";
import "contracts/utils/SignatureValidator.sol";
import "contracts/utils/L2DepositLibEIP712.sol";
import "contracts/interfaces/IArbitrumL1GatewayRouter.sol";
import "contracts/interfaces/IOptimismL1StandardBridge.sol";

interface IArbitrumBridge {
    function delayedMessageCount() external view returns (uint256);
}

contract TestL2Deposit is StrategySharedSetup {
    using SafeERC20 for IERC20;

    uint256 userPrivateKey = uint256(1);
    uint256 bobPrivateKey = uint256(2);
    address owner = makeAddr("owner");
    address user = vm.addr(userPrivateKey);

    L2Deposit l2Deposit;

    // Arbitrum
    IArbitrumL1GatewayRouter arbitrumL1GatewayRouter;
    IArbitrumBridge arbitrumL1Bridge;
    IERC20 arbitrumLONAddr;

    // Optimism
    IOptimismL1StandardBridge optimismL1StandardBridge;

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

        arbitrumLONAddr = IERC20(arbitrumL1GatewayRouter.calculateL2TokenAddress(address(lon)));

        // Set user token balance and approve
        tokens = [lon];
        setEOABalanceAndApprove(user, tokens, 100);

        DEFAULT_DEPOSIT = L2DepositLibEIP712.Deposit(
            L2DepositLibEIP712.L2Identifier.Arbitrum, // l2Identifier
            address(lon), // l1TokenAddr
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
        vm.label(owner, "Owner");
        vm.label(address(this), "TestingContract");
        vm.label(address(l2Deposit), "L2DepositContract");
        vm.label(address(arbitrumL1GatewayRouter), "ArbitrumL1GatewayContract");
        vm.label(address(arbitrumL1Bridge), "ArbitrumL1BridgeContract");
        vm.label(address(optimismL1StandardBridge), "OptimismL1StandardBridgeContract");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        arbitrumL1GatewayRouter = IArbitrumL1GatewayRouter(ARBITRUM_L1_GATEWAY_ROUTER_ADDR);
        arbitrumL1Bridge = IArbitrumBridge(ARBITRUM_L1_BRIDGE_ADDR);
        optimismL1StandardBridge = IOptimismL1StandardBridge(OPTIMISM_L1_STANDARD_BRIDGE_ADDR);

        l2Deposit = new L2Deposit(
            owner,
            address(userProxy),
            WETH_ADDRESS,
            address(permanentStorage),
            address(spender),
            arbitrumL1GatewayRouter,
            optimismL1StandardBridge
        );

        // Hook up L2Deposit
        userProxy.upgradeL2Deposit(address(l2Deposit), true);
        vm.startPrank(psOperator, psOperator);
        permanentStorage.upgradeL2Deposit(address(l2Deposit));
        permanentStorage.setPermission(permanentStorage.l2DepositSeenStorageId(), address(l2Deposit), true);
        vm.stopPrank();
        return address(l2Deposit);
    }

    function _setupDeployedStrategy() internal override {
        arbitrumL1GatewayRouter = IArbitrumL1GatewayRouter(vm.envAddress("ARBITRUM_L1_GATEWAY_ROUTER_ADDRESS"));
        arbitrumL1Bridge = IArbitrumBridge(vm.envAddress("ARBITRUM_L1_BRIDGE_ADDRESS"));
        optimismL1StandardBridge = IOptimismL1StandardBridge(vm.envAddress("OPTIMISM_L1_STANDARD_BRIDGE_ADDRESS"));
        l2Deposit = L2Deposit(payable(vm.envAddress("L2DEPOSIT_ADDRESS")));
        owner = l2Deposit.owner();
    }

    function _signDeposit(uint256 privateKey, L2DepositLibEIP712.Deposit memory deposit) internal returns (bytes memory) {
        // Calculate EIP-712 sig without Lib712 deliberately.
        bytes32 DEPOSIT_TYPEHASH = keccak256(
            abi.encodePacked(
                "Deposit(",
                "uint8 l2Identifier,",
                "address l1TokenAddr,",
                "address l2TokenAddr,",
                "address sender,",
                "address recipient,",
                "uint256 amount,",
                "uint256 salt,",
                "uint256 expiry,",
                "bytes data",
                ")"
            )
        );
        bytes32 depositHash = keccak256(
            abi.encode(
                DEPOSIT_TYPEHASH,
                deposit.l2Identifier,
                deposit.l1TokenAddr,
                deposit.l2TokenAddr,
                deposit.sender,
                deposit.recipient,
                deposit.amount,
                deposit.salt,
                deposit.expiry,
                keccak256(deposit.data)
            )
        );
        bytes32 EIP712SignDigest = getEIP712Hash(l2Deposit.EIP712_DOMAIN_SEPARATOR(), depositHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v, bytes32(0), uint8(SignatureValidator.SignatureType.EIP712));
    }
}

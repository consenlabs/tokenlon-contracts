// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IArbitrumL1GatewayRouter.sol";
import "./interfaces/IArbitrumL1Inbox.sol";
import "./interfaces/IL2Deposit.sol";
import "./interfaces/IOptimismL1StandardBridge.sol";
import "./interfaces/IPermanentStorage.sol";
import "./interfaces/ISpender.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/Ownable.sol";
import "./utils/L2DepositLibEIP712.sol";
import "./utils/SignatureValidator.sol";

contract L2Deposit is IL2Deposit, ReentrancyGuard, Ownable, BaseLibEIP712, SignatureValidator {
    using SafeERC20 for IERC20;

    // Peripherals
    address public immutable userProxy;
    IPermanentStorage public immutable permStorage;

    // Bridges
    IArbitrumL1GatewayRouter public immutable arbitrumL1GatewayRouter;
    IArbitrumL1Inbox public immutable arbitrumL1Inbox;
    IOptimismL1StandardBridge public immutable optimismL1StandardBridge;

    // Below are the variables which consume storage slots.
    ISpender public spender;

    constructor(
        address _owner,
        address _userProxy,
        ISpender _spender,
        IPermanentStorage _permStorage,
        IArbitrumL1GatewayRouter _arbitrumL1GatewayRouter,
        IArbitrumL1Inbox _arbitrumL1Inbox,
        IOptimismL1StandardBridge _optimismL1StandardBridge
    ) Ownable(_owner) {
        userProxy = _userProxy;
        spender = _spender;
        permStorage = _permStorage;
        arbitrumL1GatewayRouter = _arbitrumL1GatewayRouter;
        arbitrumL1Inbox = _arbitrumL1Inbox;
        optimismL1StandardBridge = _optimismL1StandardBridge;
    }

    modifier onlyUserProxy() {
        require(address(userProxy) == msg.sender, "L2Deposit: not the UserProxy contract");
        _;
    }

    function upgradeSpender(address _newSpender) external onlyOwner {
        require(_newSpender != address(0), "L2Deposit: spender can not be zero address");
        spender = ISpender(_newSpender);

        emit UpgradeSpender(_newSpender);
    }

    function deposit(IL2Deposit.DepositParams calldata _params) external payable override nonReentrant onlyUserProxy {
        require(_params.deposit.expiry > block.timestamp, "L2Deposit: Deposit is expired");

        bytes32 depositHash = getEIP712Hash(L2DepositLibEIP712._getDepositHash(_params.deposit));
        require(isValidSignature(_params.deposit.sender, depositHash, bytes(""), _params.depositSig), "L2Deposit: Invalid deposit signature");

        // PermanentStorage will revert when L2 deposit hash is already seen
        permStorage.setL2DepositSeen(depositHash);

        // Transfer token from sender to this contract
        spender.spendFromUser(_params.deposit.sender, _params.deposit.l1TokenAddr, _params.deposit.amount);

        // Bypass stack too deep
        DepositInfo memory depositInfo = DepositInfo(
            _params.deposit.l1TokenAddr,
            _params.deposit.l2TokenAddr,
            _params.deposit.sender,
            _params.deposit.recipient,
            _params.deposit.arbitrumRefundAddr,
            _params.deposit.amount,
            _params.deposit.data
        );

        _deposit(_params.deposit.l2Identifier, depositInfo);
    }

    struct DepositInfo {
        address l1TokenAddr;
        address l2TokenAddr;
        address sender;
        address recipient;
        address arbitrumRefundAddr;
        uint256 amount;
        bytes data;
    }

    function _deposit(L2DepositLibEIP712.L2Identifier _l2Identifier, DepositInfo memory _depositInfo) internal {
        bytes memory response;

        if (_l2Identifier == L2DepositLibEIP712.L2Identifier.Arbitrum) {
            response = _depositArbitrum(_depositInfo);
        } else if (_l2Identifier == L2DepositLibEIP712.L2Identifier.Optimism) {
            response = _depositOptimism(_depositInfo);
        } else {
            revert("L2Deposit: Unknown L2 identifer");
        }

        emit Deposited(
            _l2Identifier,
            _depositInfo.l1TokenAddr,
            _depositInfo.l2TokenAddr,
            _depositInfo.sender,
            _depositInfo.recipient,
            _depositInfo.amount,
            _depositInfo.data,
            response
        );
    }

    function _depositArbitrum(DepositInfo memory _depositInfo) internal returns (bytes memory response) {
        // Ensure L2 token address assigned by sender matches that one recorded on Arbitrum gateway
        address expectedL2TokenAddr = arbitrumL1GatewayRouter.calculateL2TokenAddress(_depositInfo.l1TokenAddr);
        require(_depositInfo.l2TokenAddr == expectedL2TokenAddr, "L2Deposit: Incorrect L2 token address");

        (uint256 maxSubmissionCost, uint256 maxGas, uint256 gasPriceBid) = abi.decode(_depositInfo.data, (uint256, uint256, uint256));

        // Approve token to underlying token gateway
        address l1TokenGatewayAddr = arbitrumL1GatewayRouter.getGateway(_depositInfo.l1TokenAddr);
        IERC20(_depositInfo.l1TokenAddr).safeApprove(l1TokenGatewayAddr, _depositInfo.amount);

        // Deposit token through gateway router
        response = arbitrumL1GatewayRouter.outboundTransferCustomRefund{ value: msg.value }(
            _depositInfo.l1TokenAddr,
            _depositInfo.arbitrumRefundAddr,
            _depositInfo.recipient,
            _depositInfo.amount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, bytes(""))
        );

        // Clear token approval to underlying token gateway
        IERC20(_depositInfo.l1TokenAddr).safeApprove(l1TokenGatewayAddr, 0);

        return response;
    }

    function _depositOptimism(DepositInfo memory _depositInfo) internal returns (bytes memory response) {
        uint32 l2Gas = abi.decode(_depositInfo.data, (uint32));

        // Approve token to bridge
        IERC20(_depositInfo.l1TokenAddr).safeApprove(address(optimismL1StandardBridge), _depositInfo.amount);

        // Deposit token through bridge
        optimismL1StandardBridge.depositERC20To(
            _depositInfo.l1TokenAddr,
            _depositInfo.l2TokenAddr,
            _depositInfo.recipient,
            _depositInfo.amount,
            l2Gas,
            bytes("")
        );

        // Clear token approval to underlying token gateway
        IERC20(_depositInfo.l1TokenAddr).safeApprove(address(optimismL1StandardBridge), 0);

        return bytes("");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IArbitrumL1GatewayRouter.sol";
import "./interfaces/IL2Deposit.sol";
import "./interfaces/IOptimismL1StandardBridge.sol";
import "./interfaces/IPermanentStorage.sol";
import "./interfaces/ISpender.sol";
import "./utils/StrategyBase.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/Ownable.sol";
import "./utils/L2DepositLibEIP712.sol";
import "./utils/SignatureValidator.sol";

/// @title L2Deposit Contract
/// @author imToken Labs
contract L2Deposit is IL2Deposit, StrategyBase, ReentrancyGuard, BaseLibEIP712, SignatureValidator {
    using SafeERC20 for IERC20;

    // Bridges
    IArbitrumL1GatewayRouter public immutable arbitrumL1GatewayRouter;
    IOptimismL1StandardBridge public immutable optimismL1StandardBridge;

    constructor(
        address _owner,
        address _userProxy,
        address _weth,
        address _permStorage,
        address _spender,
        IArbitrumL1GatewayRouter _arbitrumL1GatewayRouter,
        IOptimismL1StandardBridge _optimismL1StandardBridge
    ) StrategyBase(_owner, _userProxy, _weth, _permStorage, _spender) {
        arbitrumL1GatewayRouter = _arbitrumL1GatewayRouter;
        optimismL1StandardBridge = _optimismL1StandardBridge;
    }

    /// @inheritdoc IL2Deposit
    function deposit(IL2Deposit.DepositParams calldata _params) external payable override nonReentrant onlyUserProxy {
        require(_params.deposit.expiry > block.timestamp, "L2Deposit: Deposit is expired");

        bytes32 depositHash = getEIP712Hash(L2DepositLibEIP712._getDepositHash(_params.deposit));
        require(isValidSignature(_params.deposit.sender, depositHash, bytes(""), _params.depositSig), "L2Deposit: Invalid deposit signature");

        // PermanentStorage will revert when L2 deposit hash is already seen
        permStorage.setL2DepositSeen(depositHash);

        // Transfer token from sender to this contract
        spender.spendFromUser(_params.deposit.sender, _params.deposit.l1TokenAddr, _params.deposit.amount);

        _deposit(_params.deposit);
    }

    function _deposit(L2DepositLibEIP712.Deposit memory _depositParams) internal {
        bytes memory response;

        if (_depositParams.l2Identifier == L2DepositLibEIP712.L2Identifier.Arbitrum) {
            response = _depositArbitrum(_depositParams);
        } else if (_depositParams.l2Identifier == L2DepositLibEIP712.L2Identifier.Optimism) {
            response = _depositOptimism(_depositParams);
        } else {
            revert("L2Deposit: Unknown L2 identifer");
        }

        emit Deposited(
            _depositParams.l2Identifier,
            _depositParams.l1TokenAddr,
            _depositParams.l2TokenAddr,
            _depositParams.sender,
            _depositParams.recipient,
            _depositParams.amount,
            _depositParams.data,
            response
        );
    }

    function _depositArbitrum(L2DepositLibEIP712.Deposit memory _depositParams) internal returns (bytes memory response) {
        // Ensure L2 token address assigned by sender matches that one recorded on Arbitrum gateway
        address expectedL2TokenAddr = arbitrumL1GatewayRouter.calculateL2TokenAddress(_depositParams.l1TokenAddr);
        require(_depositParams.l2TokenAddr == expectedL2TokenAddr, "L2Deposit: Incorrect L2 token address");

        (address refundAddr, uint256 maxSubmissionCost, uint256 maxGas, uint256 gasPriceBid) = abi.decode(
            _depositParams.data,
            (address, uint256, uint256, uint256)
        );

        // Approve token to underlying token gateway
        address l1TokenGatewayAddr = arbitrumL1GatewayRouter.getGateway(_depositParams.l1TokenAddr);
        IERC20(_depositParams.l1TokenAddr).safeApprove(l1TokenGatewayAddr, _depositParams.amount);

        // Deposit token through gateway router
        response = arbitrumL1GatewayRouter.outboundTransferCustomRefund{ value: msg.value }(
            _depositParams.l1TokenAddr,
            refundAddr,
            _depositParams.recipient,
            _depositParams.amount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, bytes(""))
        );

        // Clear token approval to underlying token gateway
        IERC20(_depositParams.l1TokenAddr).safeApprove(l1TokenGatewayAddr, 0);

        return response;
    }

    function _depositOptimism(L2DepositLibEIP712.Deposit memory _depositParams) internal returns (bytes memory response) {
        uint32 l2Gas = abi.decode(_depositParams.data, (uint32));

        // Approve token to bridge
        IERC20(_depositParams.l1TokenAddr).safeApprove(address(optimismL1StandardBridge), _depositParams.amount);

        // Deposit token through bridge
        optimismL1StandardBridge.depositERC20To(
            _depositParams.l1TokenAddr,
            _depositParams.l2TokenAddr,
            _depositParams.recipient,
            _depositParams.amount,
            l2Gas,
            bytes("")
        );

        // Clear token approval to underlying token gateway
        IERC20(_depositParams.l1TokenAddr).safeApprove(address(optimismL1StandardBridge), 0);

        return bytes("");
    }
}

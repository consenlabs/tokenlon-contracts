pragma solidity >=0.7.0;
pragma abicoder v2;

import "./ISetAllowance.sol";
import "../utils/AMMLibEIP712.sol";

interface IAMMWrapper is ISetAllowance {
    event TransferOwnership(address newOperator);
    event UpgradeSpender(address newSpender);
    event AllowTransfer(address spender);
    event DisallowTransfer(address spender);
    event DepositETH(uint256 ethBalance);
    event SetDefaultFeeFactor(uint256 newDefaultFeeFactor);

    event Swapped(
        string source,
        bytes32 indexed transactionHash,
        address indexed userAddr,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint256 receivedAmount,
        uint16 feeFactor,
        bool relayed
    );

    function trade(AMMLibEIP712.Order calldata _order, bytes memory _sig) external payable returns (uint256);

    function tradeByRelayer(
        AMMLibEIP712.Order calldata _order,
        bytes memory _sig,
        uint16 _feeFactor
    ) external payable returns (uint256);
}

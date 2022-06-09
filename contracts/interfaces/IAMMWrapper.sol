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
    event SetFeeFactor(uint256 newFeeFactor);

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
        uint16 feeFactor
    );

    function trade(AMMLibEIP712.Order calldata _order, bytes memory _sig) external payable returns (uint256);
}

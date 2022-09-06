// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IArbitrumL1GatewayRouter {
    // DepositInitiated actually is not fired by gateway router, but by underlying token gateway (ERC20, Custom, or others).
    // Put it here since we would only interact with gateway router.
    event DepositInitiated(address l1Token, address indexed from, address indexed to, uint256 indexed sequenceNumber, uint256 amount);

    function outboundTransferCustomRefund(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable returns (bytes memory);

    function getGateway(address _l1TokenAddr) external view returns (address gateway);

    function calculateL2TokenAddress(address _l1TokenAddr) external view returns (address l2TokenAddr);
}

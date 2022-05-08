pragma solidity 0.7.6;

import "./BaseLibEIP712.sol";

contract AMMLibEIP712 is BaseLibEIP712 {
    /***********************************|
    |             Constants             |
    |__________________________________*/

    struct Order {
        address makerAddr;
        address takerAssetAddr;
        address makerAssetAddr;
        uint256 takerAssetAmount;
        uint256 makerAssetAmount;
        address userAddr;
        address payable receiverAddr;
        uint256 salt;
        uint256 deadline;
    }

    // keccak256("tradeWithPermit(address makerAddr,address takerAssetAddr,address makerAssetAddr,uint256 takerAssetAmount,uint256 makerAssetAmount,address userAddr,address receiverAddr,uint256 salt,uint256 deadline)");
    bytes32 public constant TRADE_WITH_PERMIT_TYPEHASH =
        keccak256(
            abi.encodePacked(
                "tradeWithPermit(",
                "address makerAddr,",
                "address takerAssetAddr,",
                "address makerAssetAddr,",
                "uint256 takerAssetAmount,",
                "uint256 makerAssetAmount,",
                "address userAddr,",
                "address receiverAddr,",
                "uint256 salt,",
                "uint256 deadline",
                ")"
            )
        );
}

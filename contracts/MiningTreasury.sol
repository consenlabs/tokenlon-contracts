pragma solidity 0.6.12;

import "./MultiSig.sol";

contract MiningTreasury is MultiSig {
    constructor(address[] memory _owners, uint256 _required) public MultiSig(_owners, _required) {}
}

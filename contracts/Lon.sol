// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/ILon.sol";
import "./utils/Ownable.sol";

contract Lon is ERC20, ILon, Ownable {
    using SafeMath for uint256;

    uint256 public constant override cap = 200_000_000e18; // CAP is 200,000,000 LON

    bytes32 public immutable override DOMAIN_SEPARATOR;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    address public emergencyRecipient;

    address public minter;

    mapping(address => uint256) public override nonces;

    constructor(address _owner, address _emergencyRecipient) ERC20("Tokenlon", "LON") Ownable(_owner) {
        minter = _owner;
        emergencyRecipient = _emergencyRecipient;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "not minter");
        _;
    }

    // implement the eip-2612
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(owner != address(0), "zero address");
        require(block.timestamp <= deadline || deadline == 0, "permit is expired");

        bytes32 digest = keccak256(
            abi.encodePacked(uint16(0x1901), DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline)))
        );

        require(owner == ecrecover(digest, v, r, s), "invalid signature");
        _approve(owner, spender, value);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function emergencyWithdraw(IERC20 token) external override {
        token.transfer(emergencyRecipient, token.balanceOf(address(this)));
    }

    function setMinter(address newMinter) external onlyOwner {
        emit MinterChanged(minter, newMinter);
        minter = newMinter;
    }

    function mint(address to, uint256 amount) external override onlyMinter {
        require(to != address(0), "zero address");
        require(totalSupply().add(amount) <= cap, "cap exceeded");

        _mint(to, amount);
    }

    event MinterChanged(address minter, address newMinter);
}

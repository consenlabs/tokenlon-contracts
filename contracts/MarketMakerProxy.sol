// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IWeth.sol";
import "./utils/LibConstant.sol";
import "./utils/Ownable.sol";

contract MarketMakerProxy is Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    event ChangeSigner(address);
    event UpdateWhitelist(address, bool);
    event WrapETH(uint256);
    event WithdrawETH(uint256);

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 public constant EIP1271_MAGICVALUE = 0x1626ba7e;
    IWETH public immutable WETH;

    address public signer;
    mapping(address => bool) public isWithdrawWhitelist;

    constructor(
        address _owner,
        address _signer,
        IWETH _weth
    ) Ownable(_owner) {
        require(_signer != address(0), "MarketMakerProxy: zero address");
        signer = _signer;
        WETH = _weth;
    }

    receive() external payable {}

    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "MarketMakerProxy: zero address");
        emit ChangeSigner(_signer);
        signer = _signer;
    }

    function setAllowance(address[] calldata tokenAddrs, address spender) external onlyOwner {
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            IERC20(tokenAddrs[i]).safeApprove(spender, LibConstant.MAX_UINT);
        }
    }

    function closeAllowance(address[] calldata tokenAddrs, address spender) external onlyOwner {
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            IERC20(tokenAddrs[i]).safeApprove(spender, 0);
        }
    }

    function updateWithdrawWhitelist(address _addr, bool _enabled) external onlyOwner {
        require(_addr != address(0), "MarketMakerProxy: zero address");
        isWithdrawWhitelist[_addr] = _enabled;
        emit UpdateWhitelist(_addr, _enabled);
    }

    function wrapETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            WETH.deposit{ value: balance }();
            emit WrapETH(balance);
        }
    }

    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(isWithdrawWhitelist[to], "MarketMakerProxy: not in withdraw whitelist");
        IERC20(token).safeTransfer(to, amount);
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        require(isWithdrawWhitelist[to], "MarketMakerProxy: not in withdraw whitelist");
        to.sendValue(amount);
        emit WithdrawETH(amount);
    }

    function isValidSignature(bytes32 dataHash, bytes calldata signature) external view returns (bytes4) {
        require(signer == ECDSA.recover(dataHash, signature), "MarketMakerProxy: invalid signature");
        return EIP1271_MAGICVALUE;
    }
}

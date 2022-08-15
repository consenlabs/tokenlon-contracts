pragma solidity 0.7.6;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IWeth.sol";
import "./utils/LibConstant.sol";
import "./Ownable.sol";

interface IIMBTC {
    function burn(uint256 amount, bytes calldata data) external;
}

interface IWBTC {
    function burn(uint256 value) external;
}

contract MarketMakerProxy is Ownable {
    using SafeERC20 for IERC20;

    address public SIGNER;
    address public operator;

    // auto withdraw weth to eth
    address public WETH_ADDR;
    address public withdrawer;
    mapping(address => bool) public isWithdrawWhitelist;

    modifier onlyWithdrawer() {
        require(msg.sender == withdrawer, "MarketMakerProxy: only contract withdrawer");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "MarketMakerProxy: only contract operator");
        _;
    }

    constructor() Ownable(msg.sender) {
        operator = msg.sender;
    }

    receive() external payable {}

    // Manage
    function setSigner(address _signer) public onlyOperator {
        SIGNER = _signer;
    }

    function setConfig(address _weth) public onlyOperator {
        WETH_ADDR = _weth;
    }

    function setWithdrawer(address _withdrawer) public onlyOperator {
        withdrawer = _withdrawer;
    }

    function setOperator(address _newOperator) public onlyOwner {
        operator = _newOperator;
    }

    function setAllowance(address[] memory token_addrs, address spender) public onlyOperator {
        for (uint256 i = 0; i < token_addrs.length; i++) {
            address token = token_addrs[i];
            IERC20(token).safeApprove(spender, LibConstant.MAX_UINT);
        }
    }

    function closeAllowance(address[] memory token_addrs, address spender) public onlyOperator {
        for (uint256 i = 0; i < token_addrs.length; i++) {
            address token = token_addrs[i];
            IERC20(token).safeApprove(spender, 0);
        }
    }

    function registerWithdrawWhitelist(address _addr, bool _add) public onlyOperator {
        isWithdrawWhitelist[_addr] = _add;
    }

    function withdraw(
        address token,
        address payable to,
        uint256 amount
    ) public onlyWithdrawer {
        require(isWithdrawWhitelist[to], "MarketMakerProxy: not in withdraw whitelist");
        if (token == WETH_ADDR) {
            IWETH(WETH_ADDR).withdraw(amount);
            to.transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function withdrawETH(address payable to, uint256 amount) public onlyWithdrawer {
        require(isWithdrawWhitelist[to], "MarketMakerProxy: not in withdraw whitelist");
        to.transfer(amount);
    }

    function isValidSignature(bytes32 orderHash, bytes memory signature) public view returns (bytes32) {
        require(SIGNER == ECDSA.recover(ECDSA.toEthSignedMessageHash(orderHash), signature), "MarketMakerProxy: invalid signature");
        return keccak256("isValidWalletSignature(bytes32,address,bytes)");
    }
}

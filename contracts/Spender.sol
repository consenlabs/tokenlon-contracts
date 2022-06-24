// SPDX-License-Identifier: MIT

pragma solidity ^0.6.5;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAllowanceTarget.sol";

/**
 * @dev Spender contract
 */
contract Spender {
    using SafeMath for uint256;

    // Constants do not have storage slot.
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant ZERO_ADDRESS = address(0);
    uint256 constant private TIME_LOCK_DURATION = 1 days;

    // Below are the variables which consume storage slots.
    address public operator;
    address public pendingOperator;
    address public allowanceTarget;
    mapping(address => bool) private authorized;
    mapping(address => bool) private tokenBlacklist;
    uint256 public numPendingAuthorized;
    mapping(uint256 => address) public pendingAuthorized;
    uint256 public timelockExpirationTime;
    uint256 public contractDeployedTime;
    bool public timelockActivated;
    mapping(address => bool) public consumeGasERC20Tokens;

    // System events
    event TimeLockActivated(uint256 activatedTimeStamp);
    // Operator events
    event TransferOwnership(address newOperator);
    event SetAllowanceTarget(address allowanceTarget);
    event SetNewSpender(address newSpender);
    event SetConsumeGasERC20Token(address token);
    event TearDownAllowanceTarget(uint256 tearDownTimeStamp);
    event BlackListToken(address token, bool isBlacklisted);
    event AuthorizeSpender(address spender, bool isAuthorized);


    /************************************************************
    *          Access control and ownership management          *
    *************************************************************/
    modifier onlyOperator() {
        require(operator == msg.sender, "Spender: not the operator");
        _;
    }

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "Spender: not authorized");
        _;
    }

    function setNewOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0), "Spender: operator can not be zero address");
        pendingOperator = _newOperator;
    }

    function acceptAsOperator() external {
        require(pendingOperator == msg.sender, "Spender: only nominated one can accept as new operator");
        operator = pendingOperator;
        pendingOperator = address(0);
        emit TransferOwnership(pendingOperator);
    }


    /************************************************************
    *                    Timelock management                    *
    *************************************************************/
    /// @dev Everyone can activate timelock after the contract has been deployed for more than 1 day.
    function activateTimelock() external {
        bool canActivate = block.timestamp.sub(contractDeployedTime) > 1 days;
        require(canActivate && ! timelockActivated, "Spender: can not activate timelock yet or has been activated");
        timelockActivated = true;

        emit TimeLockActivated(block.timestamp);
    }


    /************************************************************
    *              Constructor and init functions               *
    *************************************************************/
    constructor(address _operator, address[] memory _consumeGasERC20Tokens) public {
        require(_operator != address(0), "Spender: _operator should not be 0");

        // Set operator
        operator = _operator;
        timelockActivated = false;
        contractDeployedTime = block.timestamp;

        for (uint256 i = 0; i < _consumeGasERC20Tokens.length; i++) {
            consumeGasERC20Tokens[_consumeGasERC20Tokens[i]] = true;
        }
    }

    function setAllowanceTarget(address _allowanceTarget) external onlyOperator {
        require(allowanceTarget == address(0), "Spender: can not reset allowance target");

        // Set allowanceTarget
        allowanceTarget = _allowanceTarget;

        emit SetAllowanceTarget(_allowanceTarget);
    }



    /************************************************************
    *          AllowanceTarget interaction functions            *
    *************************************************************/
    function setNewSpender(address _newSpender) external onlyOperator {
        IAllowanceTarget(allowanceTarget).setSpenderWithTimelock(_newSpender);

        emit SetNewSpender(_newSpender);
    }

    function teardownAllowanceTarget() external onlyOperator {
        IAllowanceTarget(allowanceTarget).teardown();

        emit TearDownAllowanceTarget(block.timestamp);
    }



    /************************************************************
    *           Whitelist and blacklist functions               *
    *************************************************************/
    function isBlacklisted(address _tokenAddr) external view returns (bool) {
        return tokenBlacklist[_tokenAddr];
    }

    function blacklist(address[] calldata _tokenAddrs, bool[] calldata _isBlacklisted) external onlyOperator {
        require(_tokenAddrs.length == _isBlacklisted.length, "Spender: length mismatch");
        for (uint256 i = 0; i < _tokenAddrs.length; i++) {
            tokenBlacklist[_tokenAddrs[i]] = _isBlacklisted[i];

            emit BlackListToken(_tokenAddrs[i], _isBlacklisted[i]);
        }
    }
    
    function isAuthorized(address _caller) external view returns (bool) {
        return authorized[_caller];
    }

    function authorize(address[] calldata _pendingAuthorized) external onlyOperator {
        require(_pendingAuthorized.length > 0, "Spender: authorize list is empty");
        require(numPendingAuthorized == 0 && timelockExpirationTime == 0, "Spender: an authorize current in progress");

        if (timelockActivated) {
            numPendingAuthorized = _pendingAuthorized.length;
            for (uint256 i = 0; i < _pendingAuthorized.length; i++) {
                require(_pendingAuthorized[i] != address(0), "Spender: can not authorize zero address");
                pendingAuthorized[i] = _pendingAuthorized[i];
            }
            timelockExpirationTime = now + TIME_LOCK_DURATION;
        } else {
            for (uint256 i = 0; i < _pendingAuthorized.length; i++) {
                require(_pendingAuthorized[i] != address(0), "Spender: can not authorize zero address");
                authorized[_pendingAuthorized[i]] = true;

                emit AuthorizeSpender(_pendingAuthorized[i], true);
            }
        }
    }

    function completeAuthorize() external {
        require(timelockExpirationTime != 0, "Spender: no pending authorize");
        require(now >= timelockExpirationTime, "Spender: time lock not expired yet");

        for (uint256 i = 0; i < numPendingAuthorized; i++) {
            authorized[pendingAuthorized[i]] = true;
            emit AuthorizeSpender(pendingAuthorized[i], true);
            delete pendingAuthorized[i];
        }
        timelockExpirationTime = 0;
        numPendingAuthorized = 0;
    }

    function deauthorize(address[] calldata _deauthorized) external onlyOperator {
        for (uint256 i = 0; i < _deauthorized.length; i++) {
            authorized[_deauthorized[i]] = false;

            emit AuthorizeSpender(_deauthorized[i], false);
        }
    }

    function setConsumeGasERC20Tokens(address[] memory _consumeGasERC20Tokens) external onlyOperator {
        for (uint256 i = 0; i < _consumeGasERC20Tokens.length; i++) {
            consumeGasERC20Tokens[_consumeGasERC20Tokens[i]] = true;

            emit SetConsumeGasERC20Token(_consumeGasERC20Tokens[i]);
        }
    }

    /************************************************************
    *                   External functions                      *
    *************************************************************/
    /// @dev Spend tokens on user's behalf. Only an authority can call this.
    /// @param _user The user to spend token from.
    /// @param _tokenAddr The address of the token.
    /// @param _amount Amount to spend.
    function spendFromUser(address _user, address _tokenAddr, uint256 _amount) external onlyAuthorized {
        require(! tokenBlacklist[_tokenAddr], "Spender: token is blacklisted");

        // Fix gas stipend for non standard ERC20 transfer in case token contract's SafeMath violation is triggered
        // and all gas are consumed.
        uint256 gasStipend;
        if(consumeGasERC20Tokens[_tokenAddr]) gasStipend = 80000;
        else gasStipend = gasleft();

        if (_tokenAddr != ETH_ADDRESS && _tokenAddr != ZERO_ADDRESS) {

            uint256 balanceBefore = IERC20(_tokenAddr).balanceOf(msg.sender);
            (bool callSucceed, bytes memory returndata) = address(allowanceTarget).call{gas: gasStipend}(
                abi.encodeWithSelector(
                    IAllowanceTarget.executeCall.selector,
                    _tokenAddr,
                    abi.encodeWithSelector(
                        IERC20.transferFrom.selector,
                        _user,
                        msg.sender,
                        _amount
                    )
                )
            );
            require(callSucceed, "Spender: ERC20 transferFrom failed");
            bytes memory decodedReturnData = abi.decode(returndata, (bytes));
            if (decodedReturnData.length > 0) { // Return data is optional
                // Tokens like ZRX returns false on failed transfer
                require(abi.decode(decodedReturnData, (bool)), "Spender: ERC20 transferFrom failed");
            }
            // Check balance
            uint256 balanceAfter = IERC20(_tokenAddr).balanceOf(msg.sender);
            require(balanceAfter.sub(balanceBefore) == _amount, "Spender: ERC20 transferFrom amount mismatch");
        }
    }

    /// @dev Spend tokens on user's behalf. Only an authority can call this.
    /// @param _user The user to spend token from.
    /// @param _tokenAddr The address of the token.
    /// @param _receiver The receiver of the token.
    /// @param _amount Amount to spend.
    function spendFromUserTo(address _user, address _tokenAddr, address _receiver, uint256 _amount) external onlyAuthorized {
        require(! tokenBlacklist[_tokenAddr], "Spender: token is blacklisted");

        // Fix gas stipend for non standard ERC20 transfer in case token contract's SafeMath violation is triggered
        // and all gas are consumed.
        uint256 gasStipend;
        if(consumeGasERC20Tokens[_tokenAddr]) gasStipend = 80000;
        else gasStipend = gasleft();

        if (_tokenAddr != ETH_ADDRESS && _tokenAddr != ZERO_ADDRESS) {

            uint256 balanceBefore = IERC20(_tokenAddr).balanceOf(msg.sender);
            (bool callSucceed, bytes memory returndata) = address(allowanceTarget).call{gas: gasStipend}(
                abi.encodeWithSelector(
                    IAllowanceTarget.executeCall.selector,
                    _tokenAddr,
                    abi.encodeWithSelector(
                        IERC20.transferFrom.selector,
                        _user,
                        _receiver,
                        _amount
                    )
                )
            );
            require(callSucceed, "Spender: ERC20 transferFrom failed");
            bytes memory decodedReturnData = abi.decode(returndata, (bytes));
            if (decodedReturnData.length > 0) { // Return data is optional
                // Tokens like ZRX returns false on failed transfer
                require(abi.decode(decodedReturnData, (bool)), "Spender: ERC20 transferFrom failed");
            }
            // Check balance
            uint256 balanceAfter = IERC20(_tokenAddr).balanceOf(msg.sender);
            require(balanceAfter.sub(balanceBefore) == _amount, "Spender: ERC20 transferFrom amount mismatch");
        }
    }
}

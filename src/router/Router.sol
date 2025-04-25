// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {Math} from "openzeppelin-math/Math.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessManagedUpgradeable} from "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {RayMath} from "../libraries/RayMath.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {Dispatcher} from "./Dispatcher.sol";

/**
 * @title Router contract
 * @author Spectra Finance
 * @notice Handles executions of complex sequences of actions in the Spectra protocol.
 */
contract Router is
    Dispatcher,
    AccessManagedUpgradeable,
    PausableUpgradeable,
    IRouter,
    IERC3156FlashBorrower
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /** @dev Maximum amount of tokens for which balance can be tracked in _previewRate(). */
    uint256 private constant MAX_INVOLVED_TOKENS = 30;

    /** @dev Expected return value from borrowers onFlashLoan function. */
    bytes32 private immutable ON_FLASH_LOAN = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /* Events
     *********************************************************************************************************/
    event RouterUtilChange(address indexed previousRouterUtil, address indexed newRouterUtil);
    event KyberRouterChange(address indexed previousKyberRouter, address indexed newKyberRouter);

    /* Modifiers
     *********************************************************************************************************/
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionDeadlinePassed();
        _;
    }

    /* Constructor
     *********************************************************************************************************/
    constructor(address _registry) Dispatcher(_registry) {
        _disableInitializers(); // using this so that the deployed logic contract later cannot be initialized.
    }

    /* Initializer
     *********************************************************************************************************/
    function initialize(
        address _routerUtil,
        address _kyberRouter,
        address _initialAuthority
    ) external initializer {
        __Dispatcher_init(_routerUtil, _kyberRouter);
        __AccessManaged_init(_initialAuthority);
    }

    /* Setters
     *********************************************************************************************************/

    /**
     * @inheritdoc IRouter
     */
    function pause() external override restricted {
        _pause();
    }

    /**
     * @inheritdoc IRouter
     */
    function unPause() external override restricted {
        _unpause();
    }

    /**
     * @inheritdoc IRouter
     */
    function setRouterUtil(address _routerUtil) external override restricted {
        if (_routerUtil == address(0)) {
            revert AddressError();
        }
        emit RouterUtilChange(routerUtil, _routerUtil);
        routerUtil = _routerUtil;
    }

    /**
     * @inheritdoc IRouter
     */
    function setKyberRouter(address _kyberRouter) external override restricted {
        emit KyberRouterChange(kyberRouter, _kyberRouter);
        kyberRouter = _kyberRouter;
    }

    /* Getters
     *********************************************************************************************************/

    /**
     * @inheritdoc IRouter
     */
    function getRegistry() external view override returns (address) {
        return registry;
    }

    /**
     * @inheritdoc IRouter
     */
    function getRouterUtil() external view override returns (address) {
        return routerUtil;
    }

    /**
     * @inheritdoc IRouter
     */
    function getKyberRouter() external view override returns (address) {
        return kyberRouter;
    }

    /* Executions
     *********************************************************************************************************/

    /**
     * @inheritdoc IRouter
     */
    function execute(
        bytes calldata _commands,
        bytes[] calldata _inputs,
        uint256 _deadline
    ) external payable override checkDeadline(_deadline) {
        execute(_commands, _inputs);
    }

    /**
     * @inheritdoc IRouter
     */
    function execute(
        bytes calldata _commands,
        bytes[] calldata _inputs
    ) public payable override whenNotPaused {
        uint256 numCommands = _commands.length;
        if (_inputs.length != numCommands) {
            revert LengthMismatch();
        }

        // Relying on msg.sender is problematic as it changes during a flash loan.
        // Thus, it's necessary to track who initiated the original Router execution.
        bool topLevel;
        if (msgSender == address(0)) {
            msgSender = msg.sender;
            topLevel = true;
            msgValue = msg.value;
        } else if (msg.sender != address(this)) {
            revert UnauthorizedReentrantCall();
        }
        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex; commandIndex < numCommands; ) {
            bytes1 command = _commands[commandIndex];

            bytes calldata input = _inputs[commandIndex];

            _dispatch(command, input);
            unchecked {
                commandIndex++;
            }
        }
        if (topLevel) {
            // top-level reset
            msgSender = address(0);
            msgValue = 0;
        }
    }

    /* Previews
     *********************************************************************************************************/

    /**
     * @dev Simulates the execution of a sequence of commands and returns the expected resulting rate
     * @param _commands Encoded instructions passed to the dispatcher
     * @param _inputs An array of byte strings containing ABI-encoded inputs for each command
     * @param _spot If set to true, spot exchange rate is used for swaps. Additionally for all commands,
     *              input amounts are disregarded, and one unit of the token of interest is used instead.
     *              If set to false, the function includes price impact and curve pool fees for swaps.
     * @return The preview rate value, which represents the amount of output token obtained at the end of execution
     * for each wei of input token spent at the start of execution, multiplied by 1 ray unit.
     */
    function _previewRate(
        bytes calldata _commands,
        bytes[] calldata _inputs,
        bool _spot
    ) internal view whenNotPaused returns (uint256) {
        uint256 numCommands = _commands.length;
        if (_inputs.length != numCommands) {
            revert LengthMismatch();
        }

        TokenBalance[] memory balances = new TokenBalance[](MAX_INVOLVED_TOKENS);
        uint256 rate = RayMath.RAY_UNIT;

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex; commandIndex < numCommands; ) {
            bytes1 command = _commands[commandIndex];
            bytes calldata input = _inputs[commandIndex];

            uint256 commandRate = _dispatchPreviewRate(command, input, _spot, balances);

            if (commandRate != RayMath.RAY_UNIT) {
                rate = rate.mulDiv(commandRate, RayMath.RAY_UNIT);
            }

            unchecked {
                commandIndex++;
            }
        }
        return rate;
    }

    /**
     * @inheritdoc IRouter
     */
    function previewRate(
        bytes calldata _commands,
        bytes[] calldata _inputs
    ) external view override returns (uint256) {
        return _previewRate(_commands, _inputs, false);
    }

    /**
     * @inheritdoc IRouter
     */
    function previewSpotRate(
        bytes calldata _commands,
        bytes[] calldata _inputs
    ) external view override returns (uint256) {
        return _previewRate(_commands, _inputs, true);
    }

    /* Flashloans
     *********************************************************************************************************/

    /**
     * @inheritdoc IERC3156FlashBorrower
     */
    function onFlashLoan(
        address /* initiator */,
        address _token,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _data
    ) external returns (bytes32) {
        if (msgSender == address(0)) {
            revert DirectOnFlashloanCall();
        }
        if (msg.sender != flashloanLender) {
            revert UnauthorizedOnFlashloanCaller();
        }
        (bytes memory commands, bytes[] memory inputs) = abi.decode(_data, (bytes, bytes[]));
        this.execute(commands, inputs); // https://ethereum.stackexchange.com/questions/103437/converting-bytes-memory-to-bytes-calldata
        uint256 repayAmount = _amount + _fee;
        uint256 allowance = IERC20(_token).allowance(address(this), msg.sender);
        if (allowance < repayAmount) {
            // Approve the lender to pull the funds if needed
            IERC20(_token).forceApprove(msg.sender, repayAmount);
        }
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance < repayAmount) {
            // Collect remaining debt from the original sender if needed
            IERC20(_token).safeTransferFrom(msgSender, address(this), repayAmount - balance);
        }
        return ON_FLASH_LOAN;
    }
}

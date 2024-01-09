// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-math/Math.sol";
import "../libraries/RayMath.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import {Dispatcher} from "./Dispatcher.sol";
import {IRouter} from "../interfaces/IRouter.sol";

contract Router is Dispatcher, IRouter, Ownable2StepUpgradeable, IERC3156FlashBorrower {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 private immutable ON_FLASH_LOAN = keccak256("ERC3156FlashBorrower.onFlashLoan");

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionDeadlinePassed();
        _;
    }

    /**
     * @notice Constructor of the contract
     */
    constructor() {
        _disableInitializers(); // using this so that the deployed logic contract later cannot be initialized.
    }

    /**
     * @notice Initializer of the contract.
     */
    function initialize(address _routerUtil, address _initialAuthority) external initializer {
        __Ownable_init(_msgSender());
        initializeDispatcher(_routerUtil, _initialAuthority);
    }

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
    function execute(bytes calldata _commands, bytes[] calldata _inputs) public payable override {
        uint256 numCommands = _commands.length;
        if (_inputs.length != numCommands) {
            revert LengthMismatch();
        }

        // Relying on msg.sender is problematic as it changes during a flash loan.
        // Thus, it's necessary to track who initiated the original Router execution.
        if (msgSender == address(0)) {
            msgSender = msg.sender;
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
        if (msgSender == msg.sender)
            // top-level reset
            msgSender = address(0);
    }

    /**
     * Simulates the execution of a sequence of commands and returns the preview value for the return rate.
     * @param _commands Encoded instructions passed to the dispatcher.
     * @param _inputs Encoded arguments to pass to the functions called in the corresponding commands.
     * @param _spot If true, previews the spot rate; otherwise, takes into account price impact and curve pool fees.
     * @return The preview value for the return rate, expressed in ray (the rate is defined as the amount of tokens
     * returned at the end of the sequence of operations executed by the router per unit of token sent to the contract).
     */
    function _previewRate(
        bytes calldata _commands,
        bytes[] calldata _inputs,
        bool _spot
    ) internal view returns (uint256) {
        uint256 numCommands = _commands.length;
        if (_inputs.length != numCommands) {
            revert LengthMismatch();
        }

        uint256 previousAmount;
        uint256 rate = RayMath.RAY_UNIT;

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex; commandIndex < numCommands; ) {
            bytes1 command = _commands[commandIndex];
            bytes calldata input = _inputs[commandIndex];

            (uint256 commandRate, uint256 commandAmount) = _dispatchPreviewRate(
                command,
                input,
                _spot,
                previousAmount
            );

            if (commandRate != RayMath.RAY_UNIT) {
                rate = rate.mulDiv(commandRate, RayMath.RAY_UNIT);
            }

            if (commandAmount != 0) {
                previousAmount = commandAmount; // Keep track of the previous amount if it is forced
            } else if (commandRate != RayMath.RAY_UNIT) {
                previousAmount = previousAmount.mulDiv(commandRate, RayMath.RAY_UNIT); // If not, compute the new amount
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
        (bytes memory commands, bytes[] memory inputs) = abi.decode(_data, (bytes, bytes[]));
        this.execute(commands, inputs); // https://ethereum.stackexchange.com/questions/103437/converting-bytes-memory-to-bytes-calldata
        uint256 repayAmount = _amount + _fee;
        uint256 allowance = IERC20(_token).allowance(address(this), msg.sender);
        if (allowance < repayAmount) {
            // Approve the lender to pull the funds if needed
            IERC20(_token).safeIncreaseAllowance(msg.sender, repayAmount - allowance);
        }
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance < repayAmount) {
            // Collect remaining debt from the original sender if needed
            IERC20(_token).safeTransferFrom(msgSender, address(this), repayAmount - balance);
        }
        return ON_FLASH_LOAN;
    }
}

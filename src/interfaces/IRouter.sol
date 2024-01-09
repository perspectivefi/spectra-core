// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

// https://github.com/Uniswap/universal-router/blob/main/contracts/interfaces/IUniversalRouter.sol

interface IRouter {
    /// @notice Thrown when executing commands with an expired deadline
    error TransactionDeadlinePassed();

    /// @notice Thrown when attempting to execute commands and an incorrect number of inputs are provided
    error LengthMismatch();

    /**
     * @dev Executes encoded commands along with provided inputs. Reverts if deadline has expired.
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing abi encoded inputs for each command
     * @param _deadline The deadline by which the transaction must be executed
     */
    function execute(
        bytes calldata _commands,
        bytes[] calldata _inputs,
        uint256 _deadline
    ) external payable;

    /**
     * @dev Executes encoded commands along with provided inputs.
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing abi encoded inputs for each command
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs) external payable;

    /**
     * @dev Simulates encoded commands along with provided inputs.
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing abi encoded inputs for each command
     * @return The preview value for spot rate, where the rate is defined as the amount of tokens returned
     * by the router after a sequence of operations per unit of token deposited
     */
    function previewRate(
        bytes calldata _commands,
        bytes[] calldata _inputs
    ) external view returns (uint256);

    /**
     * @dev Simulates encoded commands along with provided inputs.
     * As opposed to `preview`, the output does not include slippage, although it does include fees.
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing abi encoded inputs for each command
     * @return The preview value for spot rate, where the rate is defined as the amount of tokens returned
     * by the router after a sequence of operations per unit of token deposited
     */

    function previewSpotRate(
        bytes calldata _commands,
        bytes[] calldata _inputs
    ) external view returns (uint256);
}

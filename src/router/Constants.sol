// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

library Constants {
    /// @dev 18 decimal unit
    uint256 internal constant UNIT = 1e18;

    /// @dev identifier for native ETH
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev maximal number of iterations in the secant method algorithm
    uint256 internal constant MAX_ITERATIONS_SECANT = 255;

    /// @dev maximal number of iterations in the linear search following secant method algorithm
    uint256 internal constant MAX_ITERATIONS_LINEAR_SEARCH = 255;

    /// @dev determines the rate at which an input value is scaled in each iteration of linear search
    uint256 internal constant SCALING_FACTOR_LINEAR_SEARCH = 1e6;

    /// @dev precision divisor for the secant method
    uint256 internal constant PRECISION_DIVISOR = 1000;

    /// @dev Used for identifying cases when this contract's balance of a token is to be used as an input
    /// This value is equivalent to 1<<255, i.e. a singular 1 in the most significant bit.
    uint256 internal constant CONTRACT_BALANCE =
        0x8000000000000000000000000000000000000000000000000000000000000000;

    /// @dev Used as a flag for identifying that msg.sender should be used, saves gas by sending more 0 bytes
    address internal constant MSG_SENDER = address(0xc0);

    /// @dev Used as a flag for identifying address(this) should be used, saves gas by sending more 0 bytes
    address internal constant ADDRESS_THIS = address(0xe0);
}

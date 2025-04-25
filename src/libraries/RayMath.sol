// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/**
 * @title RayMath library
 * @author Spectra Finance
 * @notice Provides conversions for/to any decimal tokens to/from ray.
 * @dev Conversions from Ray are rounded down.
 */
library RayMath {
    /// @dev 27 decimal unit
    uint256 public constant RAY_UNIT = 1e27;
    uint256 public constant RAY_DECIMALS = 27;

    /**
     * @dev Converts a value from Ray (27-decimal precision) to a representation with a specified number of decimals.
     * @param _a The amount in Ray to be converted. Ray is a fixed-point representation with 27 decimals.
     * @param _decimals The target decimal precision for the converted amount.
     * @return b The amount converted from Ray to the specified decimal precision.
     */
    function fromRay(uint256 _a, uint256 _decimals) internal pure returns (uint256 b) {
        uint256 decimals_ratio = 10 ** (RAY_DECIMALS - _decimals);
        assembly {
            b := div(_a, decimals_ratio)
        }
    }

    /**
     * @dev Converts a value from Ray (27-decimal precision) to a representation with a specified number of decimals.
     * @param _a The amount in Ray to be converted. Ray is a fixed-point representation with 27 decimals.
     * @param _decimals The target decimal precision for the converted amount.
     * @param _roundUp If true, the function rounds up the result to the nearest integer value.
     *                If false, it truncates (rounds down) to the nearest integer.
     * @return b The amount converted from Ray to the specified decimal precision, rounded as specified.
     */
    function fromRay(
        uint256 _a,
        uint256 _decimals,
        bool _roundUp
    ) internal pure returns (uint256 b) {
        uint256 decimals_ratio = 10 ** (RAY_DECIMALS - _decimals);
        assembly {
            b := div(_a, decimals_ratio)

            if and(eq(_roundUp, 1), gt(mod(_a, decimals_ratio), 0)) {
                b := add(b, 1)
            }
        }
    }

    /**
     * @dev Converts a value with a specified number of decimals to Ray (27-decimal precision).
     * @param _a The amount to be converted, specified in a decimal format.
     * @param _decimals The number of decimals in the representation of 'a'.
     * @return b The amount in Ray, converted from the specified decimal precision.
     *           Ensures that the conversion maintains the value's integrity (no overflow).
     */
    function toRay(uint256 _a, uint256 _decimals) internal pure returns (uint256 b) {
        uint256 decimals_ratio = 10 ** (RAY_DECIMALS - _decimals);
        // to avoid overflow, b/decimals_ratio == _a
        assembly {
            b := mul(_a, decimals_ratio)

            if iszero(eq(div(b, decimals_ratio), _a)) {
                revert(0, 0)
            }
        }
    }
}

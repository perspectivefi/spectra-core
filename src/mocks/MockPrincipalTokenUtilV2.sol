// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "../interfaces/IYieldToken.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IRegistry.sol";
import "openzeppelin-contracts/interfaces/IERC4626.sol";
import "openzeppelin-math/Math.sol";
import "../libraries/RayMath.sol";

/**
 * @dev This library is used to test upgradeability of PrincipalToken.sol.
 * Only differences with PrincipalTokenUtil.sol is that _computeYield always
 * returns 1000000e18, and all compute fee functions return 0.
 */
library MockPrincipalTokenUtilV2 {
    using Math for uint256;
    using RayMath for uint256;

    error AssetDoesNotImplementMetadata();

    uint256 private constant SAFETY_BOUND = 100; // used to favour the protocol in case of approximations
    uint256 private constant FEE_DIVISOR = 1e18; // equivalent to 100% fees

    /** @dev See {IPrincipalToken-convertToSharesWithRate}. */
    function _convertToSharesWithRate(
        uint256 _assets,
        uint256 _rate,
        uint256 _ibtUnit,
        Math.Rounding _rounding
    ) internal pure returns (uint256 shares) {
        if (_rate == 0) {
            revert IPrincipalToken.RateError();
        }
        return _assets.mulDiv(_ibtUnit, _rate, _rounding);
    }

    /** @dev See {IPrincipalToken-convertToAssetsWithRate}. */
    function _convertToAssetsWithRate(
        uint256 _shares,
        uint256 _rate,
        uint256 _ibtUnit,
        Math.Rounding _rounding
    ) internal pure returns (uint256 assets) {
        return _shares.mulDiv(_rate, _ibtUnit, _rounding);
    }

    /**
     * @dev Compute yield of a user since last update (mocked)
     * @return returns the calculated yield in IBT of user
     */
    function _computeYield(
        address /* _user */,
        uint256 /* _userYieldIBTRay */,
        uint256 /* _oldIBTRate */,
        uint256 /* _ibtRate */,
        uint256 /* _oldPTRate */,
        uint256 /* _ptRate */,
        address /* _yt */
    ) external pure returns (uint256) {
        return 1000000e18;
    }

    /**
     * @dev Attempts to fetch the token decimals. Reverts if the attempt failed in some way.
     * @param _token The token address
     * @return The ERC20 token decimals
     */
    function _tryGetTokenDecimals(address _token) external view returns (uint8) {
        (bool success, bytes memory encodedDecimals) = _token.staticcall(
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return uint8(returnedDecimals);
            }
        }
        revert AssetDoesNotImplementMetadata();
    }

    /**
     * @dev Compute tokenization fee for a given amount (mocked)
     * @return returns The calculated tokenization fee
     */
    function _computeTokenizationFee(
        uint256 /* _amount */,
        address /* _pt */,
        address /* _registry */
    ) internal pure returns (uint256) {
        return 0;
    }

    /**
     * @dev Compute yield fee for a given amount (mocked)
     * @return returns the calculated yield fee
     */
    function _computeYieldFee(
        uint256 /* _amount */,
        address /* _registry */
    ) internal pure returns (uint256) {
        return 0;
    }

    /**
     * @dev Compute flashloan fee for a given amount (mocked)
     * @return returns the calculated flashloan fee
     */
    function _computeFlashloanFee(
        uint256 /* _amount */,
        address /* _registry */
    ) internal pure returns (uint256) {
        return 0;
    }
}

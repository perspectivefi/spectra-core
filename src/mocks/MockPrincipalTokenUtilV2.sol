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
 * Only differences with PrincipalTokenUtil.sol is that computeYield always
 * returns 1000000e18, and all compute fee functions return 0.
 */
library MockPrincipalTokenUtilV2 {
    using Math for uint256;
    using RayMath for uint256;

    error AssetDoesNotImplementMetadata();

    uint256 private constant SAFETY_BOUND = 100; // used to favour the protocol in case of approximations
    uint256 private constant FEE_DIVISOR = 1e18; // equivalent to 100% fees
    uint256 private constant MIN_LENGTH = 32; // minimum length the encoded decimals should have

    /**
     * @dev Compute yield of a user since last update (mocked)
     * @return updatedYieldInIBT the calculated yield in IBT of user
     */
    function computeYield(
        address /* _user */,
        uint256 /* _currentYieldInIBT */,
        uint256 /* _oldIBTRate */,
        uint256 /* _ibtRate */,
        uint256 /* _oldPTRate */,
        uint256 /* _ptRate */,
        address /* _yt */
    ) external pure returns (uint256 updatedYieldInIBT) {
        updatedYieldInIBT = 1000000e18;
    }

    /**
     * @dev Attempts to fetch the token decimals. Reverts if the attempt failed in some way.
     * @param _token The token address
     * @return The ERC20 token decimals
     */
    function tryGetTokenDecimals(address _token) external view returns (uint8) {
        (bool success, bytes memory encodedDecimals) = _token.staticcall(
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        if (success && encodedDecimals.length >= MIN_LENGTH) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return uint8(returnedDecimals);
            }
        }
        revert AssetDoesNotImplementMetadata();
    }

    /**
     * @dev Convert underlying amount to share, with the given rate
     * @param _assetsInRay The amount of underlying (in Ray)
     * @param _rate The share price in underlying (in Ray)
     * @param _rounding The rounding type to be used in the computation
     * @return sharesInRay The amount of share (in Ray)
     */
    function _convertToSharesWithRate(
        uint256 _assetsInRay,
        uint256 _rate,
        Math.Rounding _rounding
    ) internal pure returns (uint256 sharesInRay) {
        if (_rate == 0) {
            revert IPrincipalToken.RateError();
        }
        sharesInRay = _assetsInRay.mulDiv(RayMath.RAY_UNIT, _rate, _rounding);
    }

    /**
     * @dev Convert share amount to underlying, with the given rate
     * @param _sharesInRay The amount of share (in Ray)
     * @param _rate The share price in underlying (in Ray)
     * @param _rounding The rounding type to be used in the computation
     * @return assetsInRay The amount of underlying (in Ray)
     */
    function _convertToAssetsWithRate(
        uint256 _sharesInRay,
        uint256 _rate,
        Math.Rounding _rounding
    ) internal pure returns (uint256 assetsInRay) {
        assetsInRay = _sharesInRay.mulDiv(_rate, RayMath.RAY_UNIT, _rounding);
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

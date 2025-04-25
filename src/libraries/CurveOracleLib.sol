// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {Math} from "openzeppelin-math/Math.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ICurveNGPool} from "../interfaces/ICurveNGPool.sol";
import {IStableSwapNG} from "../interfaces/IStableSwapNG.sol";
import {IPrincipalToken} from "../interfaces/IPrincipalToken.sol";

/**
 * @dev Utilities for computing prices of Spectra PTs, YTs and LP tokens in Curve CryptoSwap pools.
 */

library CurveOracleLib {
    using Math for uint256;

    error PoolLiquidityError();

    uint256 public constant CURVE_UNIT = 1e18;

    /**
     * This function returns the TWAP rate PT/Asset on a Curve Cryptoswap pool, but takes into account the current rate of IBT
     * This accounts for special cases where underlying asset becomes insolvent and has decreasing exchangeRate
     * @param pool Address of the Curve Pool to get rate from
     * @return PT/Underlying exchange rate
     */
    function getPTToAssetRate(address pool) internal view returns (uint256) {
        uint256 ptToIBTRate = getPTToIBTRate(pool);
        IERC4626 ibt = IERC4626(ICurveNGPool(pool).coins(0));
        return ibt.previewRedeem(ptToIBTRate);
    }

    /**
     * This function returns the TWAP rate PT/Asset on a Curve StableSwap NG pool, but takes into account the current rate of IBT
     * This accounts for special cases where underlying asset becomes insolvent and has decreasing exchangeRate
     * @param pool Address of the Curve Pool to get rate from
     * @return PT/Underlying exchange rate
     */
    function getPTToAssetRateSNG(address pool) public view returns (uint256) {
        uint256 ptToIBTRate = getPTToIBTRateSNG(pool);
        IERC4626 ibt = IERC4626(ICurveNGPool(pool).coins(0));
        return ibt.previewRedeem(ptToIBTRate);
    }

    /**
     * @dev This function returns the TWAP rate PT/IBT on a Curve Cryptoswap pool
     * This accounts for special cases where underlying asset becomes insolvent and has decreasing exchangeRate
     * @param pool Address of the Curve Pool to get rate from
     * @return PT/IBT exchange rate
     */
    function getPTToIBTRate(address pool) internal view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(ICurveNGPool(pool).coins(1));
        uint256 maturity = pt.maturity();
        if (maturity <= block.timestamp) {
            return pt.previewRedeemForIBT(pt.getIBTUnit());
        } else {
            return pt.getIBTUnit().mulDiv(ICurveNGPool(pool).price_oracle(), CURVE_UNIT);
        }
    }

    /**
     * @dev This function returns the TWAP rate PT/IBT on a Curve StableSwap NG pool
     * This accounts for special cases where underlying asset becomes insolvent and has decreasing exchangeRate
     * @param pool Address of the Curve Pool to get rate from
     * @return PT/IBT exchange rate
     */
    function getPTToIBTRateSNG(address pool) public view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(ICurveNGPool(pool).coins(1));
        uint256 maturity = pt.maturity();
        if (maturity <= block.timestamp) {
            return pt.previewRedeemForIBT(pt.getIBTUnit());
        } else {
            uint256[] memory storedRates = IStableSwapNG(pool).stored_rates();
            return
                pt.getIBTUnit().mulDiv(storedRates[1], storedRates[0]).mulDiv(
                    IStableSwapNG(pool).price_oracle(0),
                    CURVE_UNIT
                );
        }
    }

    /**
     * This function returns the TWAP rate YT/Asset on a Curve Cryptoswap pool
     * @param pool Curve Pool to get rate from
     * @return YT/Underlying exchange rate
     */
    function getYTToAssetRate(address pool) internal view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(ICurveNGPool(pool).coins(1));
        uint256 ptToAssetRateCore = pt.previewRedeem(pt.getIBTUnit());
        uint256 ptToAssetRateOracle = getPTToAssetRate(pool);
        if (ptToAssetRateOracle > ptToAssetRateCore) {
            revert PoolLiquidityError();
        }
        return (ptToAssetRateCore - ptToAssetRateOracle);
    }

    /**
     * This function returns the TWAP rate YT/Asset on a Curve StableSwap NG pool
     * @param pool Curve Pool to get rate from
     * @return YT/Underlying exchange rate
     */
    function getYTToAssetRateSNG(address pool) internal view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(IStableSwapNG(pool).coins(1));
        uint256 ptToAssetRateCore = pt.previewRedeem(pt.getIBTUnit());
        uint256 ptToAssetRateOracle = getPTToAssetRateSNG(pool);
        if (ptToAssetRateOracle > ptToAssetRateCore) {
            revert PoolLiquidityError();
        }
        return (ptToAssetRateCore - ptToAssetRateOracle);
    }

    /**
     * @dev This function returns the TWAP rate YT/IBT on a Curve Cryptoswap pool
     * @param pool Curve Pool to get rate from
     * @return YT/IBT exchange rate
     */
    function getYTToIBTRate(address pool) internal view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(ICurveNGPool(pool).coins(1));
        uint256 ptToIBTRateCore = pt.previewRedeemForIBT(pt.getIBTUnit());
        uint256 ptToIBTRateOracle = getPTToIBTRate(pool);
        if (ptToIBTRateOracle > ptToIBTRateCore) {
            revert PoolLiquidityError();
        }
        return ptToIBTRateCore - ptToIBTRateOracle;
    }

    /**
     * @dev This function returns the TWAP rate YT/IBT on a Curve StableSwap NG pool
     * @param pool Curve Pool to get rate from
     * @return YT/IBT exchange rate
     */
    function getYTToIBTRateSNG(address pool) internal view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(IStableSwapNG(pool).coins(1));
        uint256 ptToIBTRateCore = pt.previewRedeemForIBT(pt.getIBTUnit());
        uint256 ptToIBTRateOracle = getPTToIBTRateSNG(pool);
        if (ptToIBTRateOracle > ptToIBTRateCore) {
            revert PoolLiquidityError();
        }
        return ptToIBTRateCore - ptToIBTRateOracle;
    }

    /**
     * This function returns the TWAP rate LP/Asset on a Curve Cryptoswap , and takes into account the current rate of IBT
     * @param pool Address of the Curve Pool to get rate from
     * @return LP/Underlying exchange rate
     */
    function getLPTToAssetRate(address pool) internal view returns (uint256) {
        uint256 lptToIBTRate = getLPTToIBTRate(pool);
        IERC4626 ibt = IERC4626(ICurveNGPool(pool).coins(0));
        return ibt.previewRedeem(lptToIBTRate);
    }

    /**
     * @dev This function returns the TWAP rate LP/IBT on a Curve CryptoSwap pool
     * @param pool Address of the Curve Pool to get rate from
     * @return LP/IBT exchange rate
     */
    function getLPTToIBTRate(address pool) internal view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(ICurveNGPool(pool).coins(1));
        uint256 maturity = pt.maturity();
        uint256 balIBT = ICurveNGPool(pool).balances(0);
        uint256 balPT = ICurveNGPool(pool).balances(1);
        uint256 supplyLPT = IERC20(pool).totalSupply();
        if (maturity <= block.timestamp) {
            return
                pt.previewRedeemForIBT(balPT.mulDiv(CURVE_UNIT, supplyLPT)) +
                balIBT.mulDiv(CURVE_UNIT, supplyLPT);
        } else {
            uint256 ptToIBTRate = getPTToIBTRate(pool);
            return
                ((balPT.mulDiv(ptToIBTRate, pt.getIBTUnit())) + balIBT).mulDiv(
                    CURVE_UNIT,
                    supplyLPT
                );
        }
    }

    /**
     * This function returns the TWAP rate LP/Asset on a Curve StableSwap NG pool, and takes into account the current rate of IBT
     * @param pool Address of the Curve Pool to get rate from
     * @return LP/Underlying exchange rate
     */
    function getLPTToAssetRateSNG(address pool) internal view returns (uint256) {
        uint256 lptToIBTRate = getLPTToIBTRateSNG(pool);
        IERC4626 ibt = IERC4626(IStableSwapNG(pool).coins(0));
        return ibt.previewRedeem(lptToIBTRate);
    }

    /**
     * @dev This function returns the TWAP rate LP/IBT on a Curve StableSwap NG pool
     * @param pool Address of the Curve Pool to get rate from
     * @return LP/IBT exchange rate
     */
    function getLPTToIBTRateSNG(address pool) internal view returns (uint256) {
        IPrincipalToken pt = IPrincipalToken(IStableSwapNG(pool).coins(1));
        uint256 maturity = pt.maturity();
        uint256 balIBT = IStableSwapNG(pool).balances(0);
        uint256 balPT = IStableSwapNG(pool).balances(1);
        uint256 supplyLPT = IERC20(pool).totalSupply();
        if (maturity <= block.timestamp) {
            return
                pt.previewRedeemForIBT(balPT.mulDiv(CURVE_UNIT, supplyLPT)) +
                balIBT.mulDiv(CURVE_UNIT, supplyLPT);
        } else {
            uint256 ptToIBTRate = getPTToIBTRateSNG(pool);
            return
                ((balPT.mulDiv(ptToIBTRate, pt.getIBTUnit())) + balIBT).mulDiv(
                    CURVE_UNIT,
                    supplyLPT
                );
        }
    }
}

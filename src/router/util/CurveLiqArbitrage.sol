pragma solidity 0.8.20;

import {Math} from "openzeppelin-math/Math.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ICurvePool} from "../../interfaces/ICurvePool.sol";
import {ICurveNGPool} from "../../interfaces/ICurveNGPool.sol";
import {Constants} from "../Constants.sol";

contract CurveLiqArbitrage {
    using Math for uint256;

    // Constants
    uint256 public constant CURVE_UNIT = 1e18;
    uint256 public constant PROP_MIN = 1e16;
    uint256 public constant PROP_MAX = 1e20;
    uint256 public constant MAX_ITERS = 255;
    uint256 public constant INV_PHI = 618033988749894848;

    // Errors
    error ConvergenceError(
        uint256 propMin,
        uint256 propMax,
        uint256 epsilonTheory,
        uint256 epsilonActual
    );

    /**
     * @dev Previews the rate of LP tokens obtained per unit of token0, when depositing at a given proportion.
     * @param curvePool Address of curve pool
     * @param depositInToken0 Total deposit denominated in token 0.
     * @param proportion proportion at which we want to add liquidity: numberIBTs/numberPTs. In 18 decimals.
     * @return Amount of Curve LP tokens minted per unit of token0 deposited at a given proportion of token0 and token1.
     */
    function previewUnitaryAddLiquidity(
        address curvePool,
        uint256 depositInToken0,
        uint256 proportion
    ) public view returns (uint256) {
        // Constraints: amountToken0 + last_prices * amountToken1 = depositInToken0
        // and amountToken0/amountToken1 = proportion
        // Hence: amountToken0 = amountToken1 * proportion
        // and amountToken1 = depositInToken0/(proportion + last_prices)
        uint256 amountToken1 = depositInToken0.mulDiv(
            CURVE_UNIT,
            proportion + ICurvePool(curvePool).last_prices()
        );

        uint256 amountToken0 = amountToken1.mulDiv(proportion, CURVE_UNIT);

        uint256 tokenUnit = 10 ** IERC20Metadata(ICurvePool(curvePool).coins(0)).decimals();

        return
            ICurvePool(curvePool).calc_token_amount([amountToken0, amountToken1]).mulDiv(
                tokenUnit,
                depositInToken0
            );
    }

    /**
     * @dev Adaptation of above method to support Curve NG pools
     * @dev Previews the rate of LP tokens obtained per unit of token0, when depositing at a given proportion.
     * @param curvePool Address of curve pool
     * @param depositInToken0 Total deposit denominated in token 0.
     * @param proportion proportion at which we want to add liquidity: numberIBTs/numberPTs. In 18 decimals.
     * @return Amount of Curve LP tokens minted per unit of token0 deposited at a given proportion of token0 and token1.
     */
    function previewNGUnitaryAddLiquidity(
        address curvePool,
        uint256 depositInToken0,
        uint256 proportion
    ) public view returns (uint256) {
        // Constraints: amountToken0 + last_prices * amountToken1 = depositInToken0
        // and amountToken0/amountToken1 = proportion
        // Hence: amountToken0 = amountToken1 * proportion
        // and amountToken1 = depositInToken0/(proportion + last_prices)
        uint256 amountToken1 = depositInToken0.mulDiv(
            CURVE_UNIT,
            proportion + ICurveNGPool(curvePool).last_prices()
        );

        uint256 amountToken0 = amountToken1.mulDiv(proportion, CURVE_UNIT);

        uint256 tokenUnit = 10 ** IERC20Metadata(ICurveNGPool(curvePool).coins(0)).decimals();

        return
            ICurveNGPool(curvePool).calc_token_amount([amountToken0, amountToken1], true).mulDiv(
                tokenUnit,
                depositInToken0
            );
    }

    /**
     * @dev Searches for the proportion that maximizes a liquidity deposit of value depositInToken0, using golden section
     * search. Concretely, it maximizes the amount of LP tokens received.
     * Golden Section Search reference: https://en.wikipedia.org/wiki/Golden-section_search
     * @param curvePool Address of curve pool
     * @param depositInToken0 Total deposit denominated in token0.
     * @param epsilon Error tolerance (18 decimals)
     * @return Proportion that maximizes the amount of LP tokens minted.
     */
    function findBestProportion(
        address curvePool,
        uint256 depositInToken0,
        uint256 epsilon
    ) public view returns (uint256) {
        uint256 propMin = PROP_MIN;
        uint256 propMax = PROP_MAX;

        uint256 m1 = 0;
        uint256 m2 = 0;
        uint256 iters = 0;

        uint256 lpRate1 = 0;
        uint256 lpRate2 = 0;

        while (propMax - propMin > epsilon) {
            if (iters > MAX_ITERS) {
                revert ConvergenceError(propMin, propMax, epsilon, propMax - propMin);
            }

            m1 = propMax - (propMax - propMin).mulDiv(INV_PHI, CURVE_UNIT);
            m2 = propMin + (propMax - propMin).mulDiv(INV_PHI, CURVE_UNIT);

            lpRate1 = previewUnitaryAddLiquidity(curvePool, depositInToken0, m1);
            lpRate2 = previewUnitaryAddLiquidity(curvePool, depositInToken0, m2);

            if (lpRate1 > lpRate2) {
                propMax = m2;
            } else {
                propMin = m1;
            }

            ++iters;
        }

        return (propMin + propMax) / 2;
    }

    /**
     * @dev Adaptation of the above method to support Curve NG pools
     * @dev Searches for the proportion that maximizes a liquidity deposit of value depositInToken0, using golden section
     * search. Concretely, it maximizes the amount of LP tokens received.
     * Golden Section Search reference: https://en.wikipedia.org/wiki/Golden-section_search
     * @param curvePool Address of curve pool
     * @param depositInToken0 Total deposit denominated in token0.
     * @param epsilon Error tolerance (18 decimals)
     * @return Proportion that maximizes the amount of LP tokens minted.
     */
    function findBestProportionNG(
        address curvePool,
        uint256 depositInToken0,
        uint256 epsilon
    ) public view returns (uint256) {
        uint256 propMin = PROP_MIN;
        uint256 propMax = PROP_MAX;

        uint256 m1 = 0;
        uint256 m2 = 0;
        uint256 iters = 0;

        uint256 lpRate1 = 0;
        uint256 lpRate2 = 0;

        while (propMax - propMin > epsilon) {
            if (iters > MAX_ITERS) {
                revert ConvergenceError(propMin, propMax, epsilon, propMax - propMin);
            }

            m1 = propMax - (propMax - propMin).mulDiv(INV_PHI, CURVE_UNIT);
            m2 = propMin + (propMax - propMin).mulDiv(INV_PHI, CURVE_UNIT);

            lpRate1 = previewNGUnitaryAddLiquidity(curvePool, depositInToken0, m1);
            lpRate2 = previewNGUnitaryAddLiquidity(curvePool, depositInToken0, m2);

            if (lpRate1 > lpRate2) {
                propMax = m2;
            } else {
                propMin = m1;
            }

            ++iters;
        }

        return (propMin + propMax) / 2;
    }
}

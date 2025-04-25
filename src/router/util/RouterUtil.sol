// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {Math} from "openzeppelin-math/Math.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC3156FlashLender} from "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {CurvePoolUtil} from "../../libraries/CurvePoolUtil.sol";
import {ICurvePool} from "../../interfaces/ICurvePool.sol";
import {IStableSwapNG} from "../../interfaces/IStableSwapNG.sol";
import {ICurveNGPool} from "../../interfaces/ICurveNGPool.sol";
import {IPrincipalToken} from "../../interfaces/IPrincipalToken.sol";
import {Constants} from "../Constants.sol";

/**
 * @title Router Util contract
 * @author Spectra Finance
 * @notice Provides miscellaneous utils and preview functions related to Router executions.
 */
contract RouterUtil {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    error InvalidTokenIndex(uint256 i, uint256 j);
    error PoolLiquidityError();
    error UnsufficientAmountForFlashFee();
    error ResultNotFound();

    /**
     * @dev Gives the spot exchange rate of token i in terms of token j. Exchange rate is in 18 decimals
     * @dev To be used with Curve Cryptoswap pools
     * @param _curvePool PT/IBT curve pool
     * @param _i token index, either 0 or 1
     * @param _j token index, either 0 or 1, must be different than _i
     * @return The spot exchange rate of _i in terms of _j
     */

    function spotExchangeRate(
        address _curvePool,
        uint256 _i,
        uint256 _j
    ) public view returns (uint256) {
        if (_i == 0 && _j == 1) {
            return
                CurvePoolUtil.CURVE_UNIT.mulDiv(
                    CurvePoolUtil.CURVE_UNIT,
                    ICurvePool(_curvePool).last_prices()
                );
        } else if (_i == 1 && _j == 0) {
            return ICurvePool(_curvePool).last_prices();
        } else {
            revert InvalidTokenIndex(_i, _j);
        }
    }

    /**
     * @dev Gives the spot exchange rate of token i in terms of token j. Exchange rate is in 18 decimals
     * @dev To be used with Curve Stableswap pools
     * @param _curvePool PT/IBT curve pool
     * @param _i token index, either 0 or 1
     * @param _j token index, either 0 or 1, must be different than _i
     * @return The spot exchange rate of _i in terms of _j
     */
    function spotExchangeRateSNG(
        address _curvePool,
        int128 _i,
        int128 _j
    ) public view returns (uint256) {
        uint256 last_prices = IStableSwapNG(_curvePool).last_price(0);
        uint256[] memory stored_rates = IStableSwapNG(_curvePool).stored_rates();

        if (_i == 0 && _j == 1) {
            last_prices = stored_rates[0].mulDiv(CurvePoolUtil.CURVE_UNIT, stored_rates[1]).mulDiv(
                CurvePoolUtil.CURVE_UNIT,
                last_prices
            );
            return last_prices;
        } else if (_i == 1 && _j == 0) {
            last_prices = last_prices.mulDiv(stored_rates[1], stored_rates[0]);
            return last_prices;
        } else {
            revert InvalidTokenIndex(uint256(uint128(_i)), uint256(uint128(_j)));
        }
    }

    /**
     * @dev To be used with Curve Cryptoswap pools
     * @dev Gives the upper bound of the interval to perform bisection search in previewFlashSwapExactIBTForYT().
     * @param _inputIBTAmount amount of IBT exchanged for YT
     * @param _curvePool PT/IBT curve pool
     * @return The upper bound for search interval in root finding algorithms
     */
    function convertIBTToYTSpot(
        uint256 _inputIBTAmount,
        address _curvePool
    ) public view returns (uint256) {
        // The spot exchange rate between IBT and YT is evaluated using the tokenization equation without fees.
        // This equation reads: ptRate = 1 PT + 1 YT .

        address pt = ICurvePool(_curvePool).coins(1);
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate(); // Ray
        uint256 ptRate = IPrincipalToken(pt).getPTRate(); // Ray

        uint256 ptInUnderlyingRay = spotExchangeRate(_curvePool, 1, 0).mulDiv(
            ibtRate,
            CurvePoolUtil.CURVE_UNIT
        );
        if (ptInUnderlyingRay > ptRate) {
            revert PoolLiquidityError();
        }
        uint256 ytInUnderlyingRay = ptRate - ptInUnderlyingRay;

        return _inputIBTAmount.mulDiv(ibtRate, ytInUnderlyingRay);
    }

    /**
     * @dev Returns the maximal amount of YT one can obtain with a given amount of IBT (i.e without fees or slippage).
     * @dev To be used with Curve Stableswap NG pools
     * @dev Gives the upper bound of the interval to perform bisection search in previewFlashSwapExactIBTForYT().
     * @param _inputIBTAmount amount of IBT exchanged for YT
     * @param _curvePool PT/IBT curve pool
     * @return The upper bound for search interval in root finding algorithms
     */
    function convertIBTToYTSpotSNG(
        uint256 _inputIBTAmount,
        address _curvePool
    ) public view returns (uint256) {
        // The spot exchange rate between IBT and YT is evaluated using the tokenization equation without fees.
        // This equation reads: ptRate = 1 PT + 1 YT .

        address pt = ICurvePool(_curvePool).coins(1);
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate(); // Ray
        uint256 ptRate = IPrincipalToken(pt).getPTRate(); // Ray

        uint256 ptInUnderlyingRay = spotExchangeRateSNG(_curvePool, 1, 0).mulDiv(
            ibtRate,
            CurvePoolUtil.CURVE_UNIT
        );
        if (ptInUnderlyingRay > ptRate) {
            revert PoolLiquidityError();
        }
        uint256 ytInUnderlyingRay = ptRate - ptInUnderlyingRay;

        return _inputIBTAmount.mulDiv(ibtRate, ytInUnderlyingRay);
    }

    /* PREVIEW FUNCTIONS FOR CURVE CRYPTOSWAP POOLS
     *****************************************************************************************************************/

    /**
     * @dev Computes the amount of IBT required to buy a given output amount of YT.
     * @dev Works for both Cryptoswap
     * @param _curvePool PT/IBT curve pool
     * @param _outputYTAmount desired output YT token amount
     * @return inputIBTAmount The amount of IBT needed for obtaining the defined amount of YT
     * @return borrowedIBTAmount the quantity of IBT borrowed to execute that swap
     */
    function previewFlashSwapIBTToExactYT(
        address _curvePool,
        uint256 _outputYTAmount
    ) public view returns (uint256 inputIBTAmount, uint256 borrowedIBTAmount) {
        // Tokens
        address pt = ICurvePool(_curvePool).coins(1);
        address ibt = IPrincipalToken(pt).getIBT();

        // Units and rates
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate(); // Ray
        uint256 ptRate = IPrincipalToken(pt).getPTRate(); // Ray

        // Outputs
        uint256 swapPTForIBT = ICurvePool(_curvePool).get_dy(1, 0, _outputYTAmount);

        // y PT:YT = (x IBT * ((UNIT - tokenizationFee) / UNIT) * ibtRate) / ptRate
        // <=> x IBT = (y PT:YT * ptRate * UNIT) / (ibtRate * (UNIT - tokenizationFee))
        borrowedIBTAmount = (_outputYTAmount * ptRate * Constants.UNIT).ceilDiv(
            ibtRate * (Constants.UNIT - IPrincipalToken(pt).getTokenizationFee())
        );
        if (swapPTForIBT > borrowedIBTAmount) {
            revert PoolLiquidityError();
        }
        inputIBTAmount =
            borrowedIBTAmount +
            _getFlashFee(pt, ibt, borrowedIBTAmount) -
            swapPTForIBT;
    }

    /**
     * @dev Computes the amount of IBT required to buy a given output amount of YT.
     * @dev Works for both Stableswap NG pools
     * @param _curvePool PT/IBT curve pool
     * @param _outputYTAmount desired output YT token amount
     * @return inputIBTAmount The amount of IBT needed for obtaining the defined amount of YT
     * @return borrowedIBTAmount the quantity of IBT borrowed to execute that swap
     */
    function previewFlashSwapIBTToExactYTSNG(
        address _curvePool,
        uint256 _outputYTAmount
    ) public view returns (uint256 inputIBTAmount, uint256 borrowedIBTAmount) {
        // Tokens
        address pt = ICurvePool(_curvePool).coins(1);
        address ibt = IPrincipalToken(pt).getIBT();

        // Units and rates
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate(); // Ray
        uint256 ptRate = IPrincipalToken(pt).getPTRate(); // Ray

        // Outputs
        uint256 swapPTForIBT = IStableSwapNG(_curvePool).get_dy(1, 0, _outputYTAmount);

        // y PT:YT = (x IBT * ((UNIT - tokenizationFee) / UNIT) * ibtRate) / ptRate
        // <=> x IBT = (y PT:YT * ptRate * UNIT) / (ibtRate * (UNIT - tokenizationFee))
        borrowedIBTAmount = (_outputYTAmount * ptRate * Constants.UNIT).ceilDiv(
            ibtRate * (Constants.UNIT - IPrincipalToken(pt).getTokenizationFee())
        );
        if (swapPTForIBT > borrowedIBTAmount) {
            revert PoolLiquidityError();
        }
        inputIBTAmount =
            borrowedIBTAmount +
            _getFlashFee(pt, ibt, borrowedIBTAmount) -
            swapPTForIBT;
    }

    /**
     * @dev Approximates the expected output amount of YT corresponding to a given input amount of IBT.
     * @dev To be used with Curve Cryptoswap pools
     * @dev May return an output YT amount that corresponds to an input IBT amount lower than the given _inputIBTAmount.
     * @dev This function can be expensive to execute and should only be called off-chain. Avoid using it within a transaction.
     * @param _curvePool PT/IBT curve pool
     * @param _inputIBTAmount amount of IBT exchanged for YT
     * @return ytAmount The guess of YT obtained for the given amount of IBT
     * @return borrowedIBTAmount The quantity of IBT borrowed to execute that swap.
     */
    function previewFlashSwapExactIBTToYT(
        address _curvePool,
        uint256 _inputIBTAmount
    ) public view returns (uint256 ytAmount, uint256 borrowedIBTAmount) {
        // initial guesses
        address pt = ICurvePool(_curvePool).coins(1);
        uint256 x0 = IPrincipalToken(pt).previewDepositIBT(_inputIBTAmount);
        uint256 x1 = convertIBTToYTSpot(_inputIBTAmount, _curvePool);
        uint256 ibtUnit = getUnit(ICurvePool(_curvePool).coins(0));

        // Use secant method to approximate ytAmount
        for (uint256 i = 0; i < Constants.MAX_ITERATIONS_SECANT; ++i) {
            if (
                _delta(x0, x1).mulDiv(ibtUnit, Math.max(x0, x1)) <
                ibtUnit / Constants.PRECISION_DIVISOR
            ) {
                break;
            }

            (uint256 inputIBTAmount0, ) = previewFlashSwapIBTToExactYT(_curvePool, x0);
            (uint256 inputIBTAmount1, ) = previewFlashSwapIBTToExactYT(_curvePool, x1);
            int256 answer0 = inputIBTAmount0.toInt256() - _inputIBTAmount.toInt256();
            int256 answer1 = inputIBTAmount1.toInt256() - _inputIBTAmount.toInt256();

            if (answer0 == answer1) {
                break;
            }

            // x2 = x1 - (f(x1) * (x1 - x0) / (f(x1) - f(x0)))
            // x0, x1 = x1, x2
            uint256 x2 = (x1.toInt256() -
                ((answer1 * (x1.toInt256() - x0.toInt256())) / (answer1 - answer0))).toUint256();
            x0 = x1;
            x1 = x2;
        }
        ytAmount = Math.min(x0, x1);

        uint256 resInputIBTAmount;
        (resInputIBTAmount, borrowedIBTAmount) = previewFlashSwapIBTToExactYT(_curvePool, ytAmount);

        // Run linear search if inputIBTAmount corresponding to ytAmount is higher than requested
        if (resInputIBTAmount > _inputIBTAmount) {
            // linear search
            uint256 sf = Constants.SCALING_FACTOR_LINEAR_SEARCH;
            for (uint256 i = 0; i < Constants.MAX_ITERATIONS_LINEAR_SEARCH; ++i) {
                ytAmount = ytAmount.mulDiv(sf - 1, sf);
                (resInputIBTAmount, borrowedIBTAmount) = previewFlashSwapIBTToExactYT(
                    _curvePool,
                    ytAmount
                );
                if (resInputIBTAmount <= _inputIBTAmount) {
                    break;
                }
            }
        }

        // if result is still higher or too far from requested value
        if (
            resInputIBTAmount > _inputIBTAmount ||
            _delta(_inputIBTAmount, resInputIBTAmount).mulDiv(ibtUnit, _inputIBTAmount) >
            ibtUnit / Constants.PRECISION_DIVISOR
        ) {
            revert ResultNotFound();
        }
    }

    /**
     * @dev Approximates the expected output amount of YT corresponding to a given input amount of IBT.
     * @dev To be used with Curve Stableswap NG pools
     * @dev May return an output YT amount that corresponds to an input IBT amount lower than the given _inputIBTAmount.
     * @dev This function can be expensive to execute and should only be called off-chain. Avoid using it within a transaction.
     * @param _curvePool PT/IBT curve pool
     * @param _inputIBTAmount amount of IBT exchanged for YT
     * @return ytAmount The guess of YT obtained for the given amount of IBT
     * @return borrowedIBTAmount The quantity of IBT borrowed to execute that swap.
     */
    function previewFlashSwapExactIBTToYTSNG(
        address _curvePool,
        uint256 _inputIBTAmount
    ) public view returns (uint256 ytAmount, uint256 borrowedIBTAmount) {
        // initial guesses
        address pt = IStableSwapNG(_curvePool).coins(1);
        uint256 x0 = IPrincipalToken(pt).previewDepositIBT(_inputIBTAmount);
        uint256 x1 = convertIBTToYTSpotSNG(_inputIBTAmount, _curvePool);
        uint256 ibtUnit = getUnit(ICurvePool(_curvePool).coins(0));

        // Use secant method to approximate ytAmount
        for (uint256 i = 0; i < Constants.MAX_ITERATIONS_SECANT; ++i) {
            if (
                _delta(x0, x1).mulDiv(ibtUnit, Math.max(x0, x1)) <
                ibtUnit / Constants.PRECISION_DIVISOR
            ) {
                break;
            }

            (uint256 inputIBTAmount0, ) = previewFlashSwapIBTToExactYTSNG(_curvePool, x0);
            (uint256 inputIBTAmount1, ) = previewFlashSwapIBTToExactYTSNG(_curvePool, x1);
            int256 answer0 = inputIBTAmount0.toInt256() - _inputIBTAmount.toInt256();
            int256 answer1 = inputIBTAmount1.toInt256() - _inputIBTAmount.toInt256();

            if (answer0 == answer1) {
                break;
            }

            // x2 = x1 - (f(x1) * (x1 - x0) / (f(x1) - f(x0)))
            // x0, x1 = x1, x2
            uint256 x2 = (x1.toInt256() -
                ((answer1 * (x1.toInt256() - x0.toInt256())) / (answer1 - answer0))).toUint256();
            x0 = x1;
            x1 = x2;
        }
        ytAmount = Math.min(x0, x1);

        uint256 resInputIBTAmount;
        (resInputIBTAmount, borrowedIBTAmount) = previewFlashSwapIBTToExactYTSNG(
            _curvePool,
            ytAmount
        );

        // Run linear search if inputIBTAmount corresponding to ytAmount is higher than requested
        if (resInputIBTAmount > _inputIBTAmount) {
            // linear search
            uint256 sf = Constants.SCALING_FACTOR_LINEAR_SEARCH;
            for (uint256 i = 0; i < Constants.MAX_ITERATIONS_LINEAR_SEARCH; ++i) {
                ytAmount = ytAmount.mulDiv(sf - 1, sf);
                (resInputIBTAmount, borrowedIBTAmount) = previewFlashSwapIBTToExactYTSNG(
                    _curvePool,
                    ytAmount
                );
                if (resInputIBTAmount <= _inputIBTAmount) {
                    break;
                }
            }
        }

        // if result is still higher or too far from requested value
        if (
            resInputIBTAmount > _inputIBTAmount ||
            _delta(_inputIBTAmount, resInputIBTAmount).mulDiv(ibtUnit, _inputIBTAmount) >
            ibtUnit / Constants.PRECISION_DIVISOR
        ) {
            revert ResultNotFound();
        }
    }

    /**
     * @dev Given an amount of YT, previews the amount of IBT received after exchange
     * @dev To be used with Curve Cryptoswap pools
     * @param _curvePool PT/IBT curve pool
     * @param inputYTAmount amount of YT exchanged for IBT
     * @return The amount of IBT obtained for the given amount of YT
     * @return The amount of IBT borrowed to execute that swap.
     */
    function previewFlashSwapExactYTToIBT(
        address _curvePool,
        uint256 inputYTAmount
    ) public view returns (uint256, uint256) {
        // Tokens
        address pt = ICurvePool(_curvePool).coins(1);
        address ibt = IPrincipalToken(pt).getIBT();
        // Units and Rates
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate();
        uint256 ptRate = IPrincipalToken(pt).getPTRate();
        // Outputs
        uint256 borrowedIBTAmount = CurvePoolUtil.getDx(_curvePool, 0, 1, inputYTAmount);
        uint256 inputYTAmountInIBT = inputYTAmount.mulDiv(ptRate, ibtRate);
        uint256 flashFee = _getFlashFee(pt, ibt, borrowedIBTAmount);
        if (borrowedIBTAmount > inputYTAmountInIBT) {
            revert PoolLiquidityError();
        } else if (borrowedIBTAmount + flashFee > inputYTAmountInIBT) {
            revert UnsufficientAmountForFlashFee();
        }
        uint256 outputIBTAmount = inputYTAmountInIBT - borrowedIBTAmount - flashFee;

        return (outputIBTAmount, borrowedIBTAmount);
    }

    /**
     * @dev Given an amount of YT, previews the amount of IBT received after exchange
     * @dev To be used with Curve StableSwap NG pools
     * @param _curvePool PT/IBT curve pool
     * @param inputYTAmount amount of YT exchanged for IBT
     * @return The amount of IBT obtained for the given amount of YT
     * @return The amount of IBT borrowed to execute that swap.
     */
    function previewFlashSwapExactYTToIBTSNG(
        address _curvePool,
        uint256 inputYTAmount
    ) public view returns (uint256, uint256) {
        // Tokens
        address pt = ICurvePool(_curvePool).coins(1);
        address ibt = IPrincipalToken(pt).getIBT();
        // Units and Rates
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate();
        uint256 ptRate = IPrincipalToken(pt).getPTRate();
        // Outputs
        uint256 borrowedIBTAmount = IStableSwapNG(_curvePool).get_dx(0, 1, inputYTAmount);
        uint256 inputYTAmountInIBT = inputYTAmount.mulDiv(ptRate, ibtRate);
        uint256 flashFee = _getFlashFee(pt, ibt, borrowedIBTAmount);
        if (borrowedIBTAmount > inputYTAmountInIBT) {
            revert PoolLiquidityError();
        } else if (borrowedIBTAmount + flashFee > inputYTAmountInIBT) {
            revert UnsufficientAmountForFlashFee();
        }
        uint256 outputIBTAmount = inputYTAmountInIBT - borrowedIBTAmount - flashFee;

        return (outputIBTAmount, borrowedIBTAmount);
    }

    /**
     * @notice Given an amount of asset, previews the amount of lp tokens received after depositing in the curve pool
     * @notice To be used with Curve Cryptoswap pools
     * @param _curvePool address of the curve pool
     * @param _assets amount of assets to deposit into the curve pool
     * @return minMintAmount amount of lp tokens received
     */
    function previewAddLiquidityWithAsset(
        address _curvePool,
        uint256 _assets
    ) public view returns (uint256 minMintAmount) {
        address ibt = ICurvePool(_curvePool).coins(0);
        uint256 ibts = IERC4626(ibt).previewDeposit(_assets);
        minMintAmount = previewAddLiquidityWithIBT(_curvePool, ibts);
    }

    /**
     * @notice Given an amount of asset, previews the amount of lp tokens received after depositing in the curve pool
     * @notice To be used with Curve Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _assets amount of assets to deposit into the curve pool
     * @return minMintAmount amount of lp tokens received
     */
    function previewAddLiquidityWithAssetSNG(
        address _curvePool,
        uint256 _assets
    ) public view returns (uint256 minMintAmount) {
        address ibt = ICurvePool(_curvePool).coins(0);
        uint256 ibts = IERC4626(ibt).previewDeposit(_assets);
        minMintAmount = previewAddLiquidityWithIBTSNG(_curvePool, ibts);
    }

    /**
     * @notice Given an amount of ibt, previews the amount of lp tokens received after depositing in the curve pool
     * @notice To be used with Curve Cryptoswap pools
     * @param _curvePool address of the curve pool
     * @param _ibts amount of ibt to deposit into the curve pool
     * @return minMintAmount amount of lp tokens received
     */
    function previewAddLiquidityWithIBT(
        address _curvePool,
        uint256 _ibts
    ) public view returns (uint256 minMintAmount) {
        address pt = ICurvePool(_curvePool).coins(1);
        uint256 ibtToDepositInPT = CurvePoolUtil.calcIBTsToTokenizeForCurvePool(
            _ibts,
            _curvePool,
            pt
        );
        uint256 amount0 = _ibts - ibtToDepositInPT;
        uint256 amount1 = IPrincipalToken(pt).previewDepositIBT(ibtToDepositInPT);
        minMintAmount = previewAddLiquidity(_curvePool, [amount0, amount1]);
    }

    /**
     * @notice Given an amount of ibt, previews the amount of lp tokens received after depositing in the curve pool
     * @notice To be used with Curve Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _ibts amount of ibt to deposit into the curve pool
     * @return minMintAmount amount of lp tokens received
     */
    function previewAddLiquidityWithIBTSNG(
        address _curvePool,
        uint256 _ibts
    ) public view returns (uint256 minMintAmount) {
        address pt = IStableSwapNG(_curvePool).coins(1);
        uint256 ibtToDepositInPT = CurvePoolUtil.calcIBTsToTokenizeForCurvePool(
            _ibts,
            _curvePool,
            pt
        );
        uint256 amount0 = _ibts - ibtToDepositInPT;
        uint256 amount1 = IPrincipalToken(pt).previewDepositIBT(ibtToDepositInPT);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
        minMintAmount = previewAddLiquiditySNG(_curvePool, amounts);
    }

    /**
     * @notice Given an amount of ibts and pts, previews the amount of lp tokens received after depositing in the curve pool
     * @notice To be used with Curve Cryptoswap pools
     * @param _curvePool address of the curve pool
     * @param _amounts array of length two containing the amount of ibt and pt to deposit into the pool respectively
     * @return minMintAmount amount of lp tokens received
     */
    function previewAddLiquidity(
        address _curvePool,
        uint256[2] memory _amounts
    ) public view returns (uint256 minMintAmount) {
        minMintAmount = CurvePoolUtil.previewAddLiquidity(_curvePool, _amounts);
    }

    /**
     * @notice Given an amount of ibts and pts, previews the amount of lp tokens received after depositing in the curve pool
     * @notice To be used with Curve Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _amounts array of length two containing the amount of ibt and pt to deposit into the pool respectively
     * @return minMintAmount amount of lp tokens received
     */
    function previewAddLiquiditySNG(
        address _curvePool,
        uint256[] memory _amounts
    ) public view returns (uint256 minMintAmount) {
        minMintAmount = CurvePoolUtil.previewAddLiquiditySNG(_curvePool, _amounts);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of asset received after withdrawing from the curve pool
     * @notice To be used with Curve Cryptoswap and Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @return assets amount of asset received
     */
    function previewRemoveLiquidityForAsset(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 assets) {
        uint256[2] memory minAmounts = CurvePoolUtil.previewRemoveLiquidity(_curvePool, _lpAmount);
        assets =
            IERC4626(ICurvePool(_curvePool).coins(0)).previewRedeem(minAmounts[0]) +
            IPrincipalToken(ICurvePool(_curvePool).coins(1)).previewRedeem(minAmounts[1]);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of asset received after withdrawing from the curve pool
     * @notice To be used with Curve Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @return assets amount of asset received
     */
    function previewRemoveLiquidityForAssetSNG(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 assets) {
        uint256[] memory minAmounts = CurvePoolUtil.previewRemoveLiquiditySNG(
            _curvePool,
            _lpAmount
        );
        assets =
            IERC4626(ICurvePool(_curvePool).coins(0)).previewRedeem(minAmounts[0]) +
            IPrincipalToken(ICurvePool(_curvePool).coins(1)).previewRedeem(minAmounts[1]);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of ibt received after withdrawing from the curve pool
     * @notice To be used with Curve Cryptoswap
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @return ibts amount of ibt received
     */
    function previewRemoveLiquidityForIBT(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 ibts) {
        uint256[2] memory minAmounts = CurvePoolUtil.previewRemoveLiquidity(_curvePool, _lpAmount);
        ibts =
            minAmounts[0] +
            IPrincipalToken(ICurvePool(_curvePool).coins(1)).previewRedeemForIBT(minAmounts[1]);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of ibt received after withdrawing from the curve pool
     * @notice To be used with Curve Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @return ibts amount of ibt received
     */
    function previewRemoveLiquidityForIBTSNG(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 ibts) {
        uint256[] memory minAmounts = CurvePoolUtil.previewRemoveLiquiditySNG(
            _curvePool,
            _lpAmount
        );
        ibts =
            minAmounts[0] +
            IPrincipalToken(ICurvePool(_curvePool).coins(1)).previewRedeemForIBT(minAmounts[1]);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of ibt and pt received after withdrawing from the curve pool
     * @notice To be used with Curve Cryptoswap and Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @return minAmounts array of length two cointaining the amount of ibt and pt received after withdrawing from the curve pool
     */
    function previewRemoveLiquidity(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256[2] memory minAmounts) {
        minAmounts = CurvePoolUtil.previewRemoveLiquidity(_curvePool, _lpAmount);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of ibt and pt received after withdrawing from the curve pool
     * @notice To be used with Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @return minAmounts array of length two cointaining the amount of ibt and pt received after withdrawing from the curve pool
     */
    function previewRemoveLiquiditySNG(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256[] memory minAmounts) {
        minAmounts = CurvePoolUtil.previewRemoveLiquiditySNG(_curvePool, _lpAmount);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of token at index _i received after withdrawing from the curve pool
     * @notice To be used with Curve Cryptoswap and  pools
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @param _i Index of the token to withdraw in
     * @return minAmount amount of token at index _i after withdrawing from the curve pool
     */
    function previewRemoveLiquidityOneCoin(
        address _curvePool,
        uint256 _lpAmount,
        uint256 _i
    ) public view returns (uint256 minAmount) {
        minAmount = CurvePoolUtil.previewRemoveLiquidityOneCoin(_curvePool, _lpAmount, _i);
    }

    /**
     * @notice Given an amount of lp tokens, previews the amount of token at index _i received after withdrawing from the curve pool
     * @notice To be used with Curve  Stableswap NG pools
     * @param _curvePool address of the curve pool
     * @param _lpAmount amount of lp tokens to withdraw from the curve pool
     * @param _i Index of the token to withdraw in
     * @return minAmount amount of token at index _i after withdrawing from the curve pool
     */
    function previewRemoveLiquidityOneCoinSNG(
        address _curvePool,
        uint256 _lpAmount,
        int128 _i
    ) public view returns (uint256 minAmount) {
        minAmount = CurvePoolUtil.previewRemoveLiquidityOneCoinSNG(_curvePool, _lpAmount, _i);
    }

    /* PREVIEW FUNCTIONS FOR CURVE TWOCRYPTO-NG POOLS
     *****************************************************************************************************************/

    /**
     * @dev Computes the amount of IBT required to buy a given output amount of YT.
     * @param _curvePool PT/IBT curve pool
     * @param _outputYTAmount desired output YT token amount
     * @return inputIBTAmount The amount of IBT needed for obtaining the defined amount of YT
     * @return borrowedIBTAmount the quantity of IBT borrowed to execute that swap
     */
    function previewNGFlashSwapIBTToExactYT(
        address _curvePool,
        uint256 _outputYTAmount
    ) public view returns (uint256 inputIBTAmount, uint256 borrowedIBTAmount) {
        return previewFlashSwapIBTToExactYT(_curvePool, _outputYTAmount);
    }

    /**
     * @dev Approximates the expected output amount of YT corresponding to a given input amount of IBT.
     * @dev May return an output YT amount that corresponds to an input IBT amount lower than the given _inputIBTAmount.
     * @dev This function can be expensive to execute and should only be called off-chain. Avoid using it within a transaction.
     * @param _curvePool PT/IBT curve pool
     * @param _inputIBTAmount amount of IBT exchanged for YT
     * @return ytAmount The guess of YT obtained for the given amount of IBT
     * @return borrowedIBTAmount The quantity of IBT borrowed to execute that swap.
     */
    function previewNGFlashSwapExactIBTToYT(
        address _curvePool,
        uint256 _inputIBTAmount
    ) public view returns (uint256 ytAmount, uint256 borrowedIBTAmount) {
        return previewFlashSwapExactIBTToYT(_curvePool, _inputIBTAmount);
    }

    /**
     * @dev Given an amount of YT, previews the amount of IBT received after exchange
     * @param _curvePool PT/IBT curve pool
     * @param inputYTAmount amount of YT exchanged for IBT
     * @return The amount of IBT obtained for the given amount of YT
     * @return The amount of IBT borrowed to execute that swap.
     */
    function previewNGFlashSwapExactYTToIBT(
        address _curvePool,
        uint256 inputYTAmount
    ) public view returns (uint256, uint256) {
        // Tokens
        address pt = ICurvePool(_curvePool).coins(1);
        address ibt = IPrincipalToken(pt).getIBT();
        // Units and Rates
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate();
        uint256 ptRate = IPrincipalToken(pt).getPTRate();
        // Outputs
        uint256 borrowedIBTAmount = ICurveNGPool(_curvePool).get_dx(0, 1, inputYTAmount);
        uint256 inputYTAmountInIBT = inputYTAmount.mulDiv(ptRate, ibtRate);
        uint256 flashFee = _getFlashFee(pt, ibt, borrowedIBTAmount);
        if (borrowedIBTAmount > inputYTAmountInIBT) {
            revert PoolLiquidityError();
        } else if (borrowedIBTAmount + flashFee > inputYTAmountInIBT) {
            revert UnsufficientAmountForFlashFee();
        }
        uint256 outputIBTAmount = inputYTAmountInIBT - borrowedIBTAmount - flashFee;

        return (outputIBTAmount, borrowedIBTAmount);
    }

    function previewNGAddLiquidityWithAsset(
        address _curvePool,
        uint256 _assets
    ) public view returns (uint256 minMintAmount) {
        address ibt = ICurveNGPool(_curvePool).coins(0);
        uint256 ibts = IERC4626(ibt).previewDeposit(_assets);
        minMintAmount = previewNGAddLiquidityWithIBT(_curvePool, ibts);
    }

    function previewNGAddLiquidityWithIBT(
        address _curvePool,
        uint256 _ibts
    ) public view returns (uint256 minMintAmount) {
        address pt = ICurveNGPool(_curvePool).coins(1);
        uint256 ibtToDepositInPT = CurvePoolUtil.calcIBTsToTokenizeForCurvePool(
            _ibts,
            _curvePool,
            pt
        );
        uint256 amount0 = _ibts - ibtToDepositInPT;
        uint256 amount1 = IPrincipalToken(pt).previewDepositIBT(ibtToDepositInPT);
        minMintAmount = CurvePoolUtil.previewAddLiquidityNG(_curvePool, [amount0, amount1]);
    }

    function previewNGAddLiquidity(
        address _curvePool,
        uint256[2] memory _amounts
    ) public view returns (uint256 minMintAmount) {
        minMintAmount = CurvePoolUtil.previewAddLiquidityNG(_curvePool, _amounts);
    }

    function previewNGRemoveLiquidityForAsset(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 assets) {
        uint256[2] memory minAmounts = CurvePoolUtil.previewRemoveLiquidityNG(
            _curvePool,
            _lpAmount
        );
        assets =
            IERC4626(ICurveNGPool(_curvePool).coins(0)).previewRedeem(minAmounts[0]) +
            IPrincipalToken(ICurveNGPool(_curvePool).coins(1)).previewRedeem(minAmounts[1]);
    }

    function previewNGRemoveLiquidityForIBT(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 ibts) {
        uint256[2] memory minAmounts = CurvePoolUtil.previewRemoveLiquidityNG(
            _curvePool,
            _lpAmount
        );
        ibts =
            minAmounts[0] +
            IPrincipalToken(ICurvePool(_curvePool).coins(1)).previewRedeemForIBT(minAmounts[1]);
    }

    function previewNGRemoveLiquidity(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256[2] memory minAmounts) {
        minAmounts = CurvePoolUtil.previewRemoveLiquidityNG(_curvePool, _lpAmount);
    }

    function previewNGRemoveLiquidityOneCoin(
        address _curvePool,
        uint256 _lpAmount,
        uint256 _i
    ) public view returns (uint256 minAmount) {
        minAmount = CurvePoolUtil.previewRemoveLiquidityOneCoinNG(_curvePool, _lpAmount, _i);
    }

    /* PUBLIC UTILS
     *****************************************************************************************************************/

    /**
     * @dev Returns the unit element of the underlying asset of a PT
     * @param _pt address of Principal Token
     * @return The unit of underlying asset
     */
    function getPTUnderlyingUnit(address _pt) external view returns (uint256) {
        return getUnit(IPrincipalToken(_pt).underlying());
    }

    /**
     * @dev Returns the unit element of the token
     * @param _token address of token
     * @return The unit of asset
     */
    function getUnit(address _token) public view returns (uint256) {
        return 10 ** IERC20Metadata(_token).decimals();
    }

    /* INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    /**
     * @dev Calculates the flash loan fee for borrowing a given quantity of IBT
     * @param _pt address of Principal Token
     * @param _ibt address of Interest Bearing Token
     * @param _borrowedIBTAmount amount of Interest Bearing Tokens that have been borrowed in the flash loan
     * @return The amount of fees charged for flash loan
     */
    function _getFlashFee(
        address _pt,
        address _ibt,
        uint256 _borrowedIBTAmount
    ) internal view returns (uint256) {
        return IERC3156FlashLender(_pt).flashFee(_ibt, _borrowedIBTAmount);
    }

    /**
     * @dev abs(a, b)
     * @param a some integer
     * @param b some integer
     * @return The absolute value of a - b
     */
    function _delta(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}

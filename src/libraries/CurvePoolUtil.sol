// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "../interfaces/ICurvePool.sol";
import "../interfaces/ICurveNGPool.sol";
import "../interfaces/IStableSwapNG.sol";
import "../interfaces/IPrincipalToken.sol";
import "./RayMath.sol";
import "openzeppelin-math/Math.sol";

/**
 * @title CurvePoolUtil library
 * @author Spectra Finance
 * @notice Provides miscellaneous utils for computations related to Curve CryptoSwap pools.
 */
library CurvePoolUtil {
    using Math for uint256;
    using RayMath for uint256;

    error SolutionNotFound();
    error FailedToFetchExpectedLPTokenAmount();
    error FailedToFetchExpectedCoinAmount();

    /// @notice Decimal precision used internally in the Curve AMM
    uint256 public constant CURVE_DECIMALS = 18;
    /// @notice Base unit for Curve AMM calculations
    uint256 public constant CURVE_UNIT = 1e18;
    /// @notice Make rounding errors favoring other LPs a tiny bit
    uint256 private constant APPROXIMATION_DECREMENT = 1;
    /// @notice Maximal number of iterations in the binary search algorithm
    uint256 private constant MAX_ITERATIONS_BINSEARCH = 255;

    /**
     * @notice Returns the expected LP token amount received for depositing given amounts of IBT and PT
     * @notice Method to be used with legacy Curve Cryptoswap pools
     * @param _curvePool The address of the Curve Pool in which liquidity will be deposited
     * @param _amounts Array containing the amounts of IBT and PT to deposit in the Curve Pool
     * @return minMintAmount The amount of expected LP tokens received for depositing the liquidity in the pool
     */
    function previewAddLiquidity(
        address _curvePool,
        uint256[2] memory _amounts
    ) external view returns (uint256 minMintAmount) {
        (bool success, bytes memory responseData) = _curvePool.staticcall(
            abi.encodeCall(ICurvePool(address(0)).calc_token_amount, (_amounts))
        );
        if (!success) {
            revert FailedToFetchExpectedLPTokenAmount();
        }
        minMintAmount = abi.decode(responseData, (uint256));
    }

    /**
     * @notice Returns the expected LP token amount received for depositing given amounts of IBT and PT
     * @notice Method to be used with legacy Curve Cryptoswap NG pools
     * @param _curvePool The address of the Curve Pool in which liquidity will be deposited
     * @param _amounts Array containing the amounts of IBT and PT to deposit in the Curve Pool
     * @return minMintAmount The amount of expected LP tokens received for depositing the liquidity in the pool
     */
    function previewAddLiquidityNG(
        address _curvePool,
        uint256[2] memory _amounts
    ) external view returns (uint256 minMintAmount) {
        (bool success, bytes memory responseData) = _curvePool.staticcall(
            abi.encodeCall(ICurveNGPool(address(0)).calc_token_amount, (_amounts, true))
        );
        if (!success) {
            revert FailedToFetchExpectedLPTokenAmount();
        }
        minMintAmount = abi.decode(responseData, (uint256));
    }

    /**
     * @notice Returns the expected LP token amount received for depositing given amounts of IBT and PT
     * @notice Method to be used with StableSwap NG pools
     * @param _curvePool The address of the Curve Pool in which liquidity will be deposited
     * @param _amounts Array containing the amounts of IBT and PT to deposit in the Curve Pool
     * @return minMintAmount The amount of expected LP tokens received for depositing the liquidity in the pool
     */
    function previewAddLiquiditySNG(
        address _curvePool,
        uint256[] memory _amounts
    ) external view returns (uint256 minMintAmount) {
        // @dev set the is_deposit to true
        (bool success, bytes memory responseData) = _curvePool.staticcall(
            abi.encodeCall(IStableSwapNG(address(0)).calc_token_amount, (_amounts, true))
        );
        if (!success) {
            revert FailedToFetchExpectedLPTokenAmount();
        }
        minMintAmount = abi.decode(responseData, (uint256));
    }

    /**
     * @notice Returns the IBT and PT amounts received for burning a given amount of LP tokens
     * @notice Method to be used with legacy Curve Cryptoswap pools
     * @param _curvePool The address of the curve pool
     * @param _lpTokenAmount The amount of the lp token to burn
     * @return minAmounts The expected respective amounts of IBT and PT withdrawn from the curve pool
     */
    function previewRemoveLiquidity(
        address _curvePool,
        uint256 _lpTokenAmount
    ) external view returns (uint256[2] memory minAmounts) {
        address lpToken = ICurvePool(_curvePool).token();
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        (uint256 ibtBalance, uint256 ptBalance) = _getCurvePoolBalances(_curvePool);
        // decrement following what Curve is doing
        if (_lpTokenAmount > APPROXIMATION_DECREMENT && totalSupply != 0) {
            _lpTokenAmount -= APPROXIMATION_DECREMENT;
            minAmounts = [
                (ibtBalance * _lpTokenAmount) / totalSupply,
                (ptBalance * _lpTokenAmount) / totalSupply
            ];
        } else {
            minAmounts = [uint256(0), uint256(0)];
        }
    }

    /**
     * @notice Returns the IBT and PT amounts received for burning a given amount of LP tokens
     * @notice Method to be used with Curve Cryptoswap NG pools
     * @param _curvePool The address of the curve pool
     * @param _lpTokenAmount The amount of the lp token to burn
     * @return minAmounts The expected respective amounts of IBT and PT withdrawn from the curve pool
     */
    function previewRemoveLiquidityNG(
        address _curvePool,
        uint256 _lpTokenAmount
    ) external view returns (uint256[2] memory minAmounts) {
        uint256 totalSupply = ICurveNGPool(_curvePool).totalSupply();
        (uint256 ibtBalance, uint256 ptBalance) = _getCurvePoolBalances(_curvePool);
        // reproduces Curve implementation
        if (_lpTokenAmount == totalSupply) {
            minAmounts = [ibtBalance, ptBalance];
        } else if (_lpTokenAmount > APPROXIMATION_DECREMENT && totalSupply != 0) {
            _lpTokenAmount -= APPROXIMATION_DECREMENT;
            minAmounts = [
                ibtBalance.mulDiv(_lpTokenAmount, totalSupply),
                ptBalance.mulDiv(_lpTokenAmount, totalSupply)
            ];
        } else {
            minAmounts = [uint256(0), uint256(0)];
        }
    }

    /**
     * @notice Returns the IBT and PT amounts received for burning a given amount of LP tokens
     * @notice Method to be used with StableSwap NG pools
     * @param _curvePool The address of the curve pool
     * @param _lpTokenAmount The amount of the lp token to burn
     * @return minAmounts The expected respective amounts of IBT and PT withdrawn from the curve pool
     */
    function previewRemoveLiquiditySNG(
        address _curvePool,
        uint256 _lpTokenAmount
    ) external view returns (uint256[] memory) {
        uint256 totalSupply = IERC20(_curvePool).totalSupply();
        (uint256 ibtBalance, uint256 ptBalance) = _getCurvePoolBalances(_curvePool);
        // decrement following what Curve is doing
        uint256[] memory minAmounts = new uint256[](2);
        if (_lpTokenAmount > APPROXIMATION_DECREMENT && totalSupply != 0) {
            _lpTokenAmount -= APPROXIMATION_DECREMENT;
            minAmounts[0] = (ibtBalance * _lpTokenAmount) / totalSupply;
            minAmounts[1] = (ptBalance * _lpTokenAmount) / totalSupply;
        } else {
            minAmounts[0] = 0;
            minAmounts[1] = 0;
        }
        return minAmounts;
    }

    /**
     * @notice Returns the amount of coin i received for burning a given amount of LP tokens
     * @notice Method to be used with legacy Curve CryptoSwap pools
     * @param _curvePool The address of the curve pool
     * @param _lpTokenAmount The amount of the LP tokens to burn
     * @param _i The index of the unique coin to withdraw
     * @return minAmount The expected amount of coin i withdrawn from the curve pool
     */
    function previewRemoveLiquidityOneCoin(
        address _curvePool,
        uint256 _lpTokenAmount,
        uint256 _i
    ) external view returns (uint256 minAmount) {
        (bool success, bytes memory responseData) = _curvePool.staticcall(
            abi.encodeCall(ICurvePool(address(0)).calc_withdraw_one_coin, (_lpTokenAmount, _i))
        );
        if (!success) {
            revert FailedToFetchExpectedCoinAmount();
        }
        minAmount = abi.decode(responseData, (uint256));
    }

    /**
     * @notice Returns the amount of coin i received for burning a given amount of LP tokens
     * @notice Method to be used with Curve NG pools
     * @param _curvePool The address of the curve pool
     * @param _lpTokenAmount The amount of the LP tokens to burn
     * @param _i The index of the unique coin to withdraw
     * @return minAmount The expected amount of coin i withdrawn from the curve pool
     */
    function previewRemoveLiquidityOneCoinNG(
        address _curvePool,
        uint256 _lpTokenAmount,
        uint256 _i
    ) external view returns (uint256 minAmount) {
        (bool success, bytes memory responseData) = _curvePool.staticcall(
            abi.encodeCall(ICurveNGPool(address(0)).calc_withdraw_one_coin, (_lpTokenAmount, _i))
        );
        if (!success) {
            revert FailedToFetchExpectedCoinAmount();
        }
        minAmount = abi.decode(responseData, (uint256));
    }

    /**
     * @notice Returns the amount of coin i received for burning a given amount of LP tokens
     * @notice Method to be used with StableSwap NG pools
     * @param _curvePool The address of the curve pool
     * @param _lpTokenAmount The amount of the LP tokens to burn
     * @param _i The index of the unique coin to withdraw
     * @return minAmount The expected amount of coin i withdrawn from the curve pool
     */
    function previewRemoveLiquidityOneCoinSNG(
        address _curvePool,
        uint256 _lpTokenAmount,
        int128 _i
    ) external view returns (uint256 minAmount) {
        (bool success, bytes memory responseData) = _curvePool.staticcall(
            abi.encodeCall(IStableSwapNG(address(0)).calc_withdraw_one_coin, (_lpTokenAmount, _i))
        );
        if (!success) {
            revert FailedToFetchExpectedCoinAmount();
        }
        minAmount = abi.decode(responseData, (uint256));
    }

    /**
     * @notice Return the amount of IBT to deposit in the curve pool, given the total amount of IBT available for deposit
     * @param _amount The total amount of IBT available for deposit
     * @param _curvePool The address of the pool to deposit the amounts
     * @param _pt The address of the PT
     * @return ibts The amount of IBT which will be deposited in the curve pool
     */
    function calcIBTsToTokenizeForCurvePool(
        uint256 _amount,
        address _curvePool,
        address _pt
    ) external view returns (uint256 ibts) {
        (uint256 ibtBalance, uint256 ptBalance) = _getCurvePoolBalances(_curvePool);
        uint256 ibtBalanceInPT = IPrincipalToken(_pt).previewDepositIBT(ibtBalance);
        // Liquidity added in a ratio that (closely) matches the existing pool's ratio
        ibts = _amount.mulDiv(ptBalance, ibtBalanceInPT + ptBalance);
    }

    /**
     * @notice Return the amount of IBT to deposit in the curve pool given the proportion in which we want to deposit, given the total amount of IBT available for deposit
     * @param _amount The total amount of IBT available for deposit
     * @param _prop The proportion in which we want to make the deposit: _prop = nIBT / (nIBT + nPT)
     * @param _pt The address of the PT
     * @return ibts The amount of IBT which will be deposited in the curve pool
     */
    function calcIBTsToTokenizeForCurvePoolCustomProp(
        uint256 _amount,
        uint256 _prop,
        address _pt
    ) external view returns (uint256 ibts) {
        uint256 rate = IPrincipalToken(_pt).previewDepositIBT(_amount).mulDiv(CURVE_UNIT, _amount);
        ibts = _amount.mulDiv(CURVE_UNIT, CURVE_UNIT + _prop.mulDiv(rate, CURVE_UNIT));
    }

    /**
     * @param _curvePool : PT/IBT curve pool
     * @param _i token index
     * @param _j token index
     * @param _targetDy amount out desired
     * @return dx The amount of token to provide in order to obtain _targetDy after swap
     */
    function getDx(
        address _curvePool,
        uint256 _i,
        uint256 _j,
        uint256 _targetDy
    ) external view returns (uint256 dx) {
        // Initial guesses
        uint256 _minGuess = type(uint256).max;
        uint256 _maxGuess = type(uint256).max;
        uint256 _factor100;
        uint256 _guess = ICurvePool(_curvePool).get_dy(_i, _j, _targetDy);

        if (_guess > _targetDy) {
            _maxGuess = _targetDy;
            _factor100 = 10;
        } else {
            _minGuess = _targetDy;
            _factor100 = 1000;
        }
        uint256 loops;
        _guess = _targetDy;
        while (!_dxSolved(_curvePool, _i, _j, _guess, _targetDy, _minGuess, _maxGuess)) {
            loops++;

            (_minGuess, _maxGuess, _guess) = _runLoop(
                _minGuess,
                _maxGuess,
                _factor100,
                _guess,
                _targetDy,
                _curvePool,
                _i,
                _j
            );

            if (loops >= MAX_ITERATIONS_BINSEARCH) {
                revert SolutionNotFound();
            }
        }
        dx = _guess;
    }

    /**
     * @dev Runs bisection search
     * @param _minGuess lower bound on searched value
     * @param _maxGuess upper bound on searched value
     * @param _factor100 search interval scaling factor
     * @param _guess The previous guess for the `dx` value that is being refined through the search process
     * @param _targetDy The target output of the `get_dy` function, which the search aims to achieve by adjusting `dx`.
     * @param _curvePool PT/IBT curve pool
     * @param _i token index, either 0 or 1
     * @param _j token index, either 0 or 1, must be different than _i
     * @return The lower bound on _guess, upper bound on _guess and next _guess
     */
    function _runLoop(
        uint256 _minGuess,
        uint256 _maxGuess,
        uint256 _factor100,
        uint256 _guess,
        uint256 _targetDy,
        address _curvePool,
        uint256 _i,
        uint256 _j
    ) internal view returns (uint256, uint256, uint256) {
        if (_minGuess == type(uint256).max || _maxGuess == type(uint256).max) {
            _guess = (_guess * _factor100) / 100;
        } else {
            _guess = (_maxGuess + _minGuess) >> 1;
        }
        uint256 dy = ICurvePool(_curvePool).get_dy(_i, _j, _guess);
        if (dy < _targetDy) {
            _minGuess = _guess;
        } else if (dy > _targetDy) {
            _maxGuess = _guess;
        }
        return (_minGuess, _maxGuess, _guess);
    }

    /**
     * @dev Returns true if algorithm converged
     * @param _curvePool PT/IBT curve pool
     * @param _i token index, either 0 or 1
     * @param _j token index, either 0 or 1, must be different than _i
     * @param _dx The current guess for the `dx` value that is being refined through the search process.
     * @param _targetDy The target output of the `get_dy` function, which the search aims to achieve by adjusting `dx`.
     * @param _minGuess lower bound on searched value
     * @param _maxGuess upper bound on searched value
     * @return true if the solution to the search problem was found, false otherwise
     */
    function _dxSolved(
        address _curvePool,
        uint256 _i,
        uint256 _j,
        uint256 _dx,
        uint256 _targetDy,
        uint256 _minGuess,
        uint256 _maxGuess
    ) internal view returns (bool) {
        if (_minGuess == type(uint256).max || _maxGuess == type(uint256).max) {
            return false;
        }
        uint256 dy = ICurvePool(_curvePool).get_dy(_i, _j, _dx);
        if (dy == _targetDy) {
            return true;
        }
        uint256 dy1 = ICurvePool(_curvePool).get_dy(_i, _j, _dx + 1);
        if (dy < _targetDy && _targetDy < dy1) {
            return true;
        }
        return false;
    }

    /**
     * @notice Returns the balances of the two tokens in provided curve pool
     * @param _curvePool address of the curve pool
     * @return The IBT and PT balances of the curve pool
     */
    function _getCurvePoolBalances(address _curvePool) internal view returns (uint256, uint256) {
        return (ICurvePool(_curvePool).balances(0), ICurvePool(_curvePool).balances(1));
    }
}

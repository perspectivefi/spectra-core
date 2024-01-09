// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-math/Math.sol";
import "openzeppelin-contracts/utils/math/SafeCast.sol";
import "../../libraries/CurvePoolUtil.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC3156FlashLender} from "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Dispatcher} from "../Dispatcher.sol";
import {Constants} from "../Constants.sol";
import {IRouter} from "../../interfaces/IRouter.sol";
import {IPrincipalToken} from "../../interfaces/IPrincipalToken.sol";
import {ICurvePool} from "../../interfaces/ICurvePool.sol";

contract RouterUtil {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    error InvalidTokenIndex(uint256 i, uint256 j);

    /**
     * @dev Gives the spot exchange rate of token i in terms of token j. Exchange rate is in 18 decimals
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
            return Constants.UNIT.mulDiv(Constants.UNIT, ICurvePool(_curvePool).last_prices());
        } else if (_i == 1 && _j == 0) {
            return ICurvePool(_curvePool).last_prices();
        } else {
            revert InvalidTokenIndex(_i, _j);
        }
    }

    /**
     * @dev Returns the maximal amount of YT one can obtain with a given amount of IBT (i.e without fees or slippage).
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
        // This equation reads: ptRate * IBT / ibtRate = 1 PT + 1 YT .

        address pt = ICurvePool(_curvePool).coins(1);

        uint256 ibtRate = IPrincipalToken(pt).getIBTRate(); // asset decimals
        uint256 ptRate = IPrincipalToken(pt).getPTRate(); // asset decimals

        uint256 assetUnit = getUnderlyingUnit(pt); // asset decimals
        uint256 assetUnitAdjusted = assetUnit.mulDiv(ptRate, assetUnit); // asset decimals

        uint256 ptInUnderlying = spotExchangeRate(_curvePool, 1, 0).mulDiv(ibtRate, Constants.UNIT);
        uint256 ytInUnderlying = assetUnitAdjusted - ptInUnderlying;

        return _inputIBTAmount.mulDiv(ibtRate, ytInUnderlying); // ibt decimals
    }

    /**
     * @dev Given an output amountof YT desired, yields the amount of IBT required to get this amount
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
        uint256 ibtRate = IPrincipalToken(pt).getIBTRate(); // 27 decimals
        uint256 ptRate = IPrincipalToken(pt).getPTRate(); // 27 decimals

        // Outputs
        uint256 swapPTForIBT = ICurvePool(_curvePool).get_dy(1, 0, _outputYTAmount);

        // y PT:YT = (x IBT * ((UNIT - tokenizationFee) / UNIT) * ibtRate) / ptRate
        // <=> x IBT = (y PT:YT * ptRate * UNIT) / (ibtRate * (UNIT - tokenizationFee))
        borrowedIBTAmount = (_outputYTAmount * ptRate * Constants.UNIT).ceilDiv(
            ibtRate * (Constants.UNIT - IPrincipalToken(pt).getTokenizationFee())
        );

        inputIBTAmount =
            borrowedIBTAmount +
            _getFlashFee(pt, ibt, borrowedIBTAmount) -
            swapPTForIBT;
    }

    /**
     * @dev Given an input IBT amount, previews the expected amount of YT obtained after executing the swap
     * @param _curvePool PT/IBT curve pool
     * @param _inputIBTAmount amount of IBT exchanged for YT
     * @return The max guess of YT obtained for the given amount of IBT
     * @return The min guess of YT obtained for the given amount of IBT
     * @return The quantity of IBT borrowed to execute that swap.
     */
    function previewFlashSwapExactIBTToYT(
        address _curvePool,
        uint256 _inputIBTAmount
    ) public view returns (uint256, uint256, uint256) {
        int256 x0 = _inputIBTAmount.toInt256();
        int256 x1 = convertIBTToYTSpot(_inputIBTAmount, _curvePool).toInt256();
        int256 x2;

        //x2 = x1 - f(x1) * (x1 - x0) / (f(x1) - f(x0))
        // x0, x1 = x1, x2

        for (uint256 i = 0; i < Constants.MAX_ITERATIONS_SECANT; ++i) {
            if (_delta(x0.toUint256(), x1.toUint256()) < Constants.PRECISION) {
                break;
            }

            (uint256 inputIBTAmount0, ) = previewFlashSwapIBTToExactYT(_curvePool, x0.toUint256());

            (uint256 inputIBTAmount1, ) = previewFlashSwapIBTToExactYT(_curvePool, x1.toUint256());

            int256 answer0 = inputIBTAmount0.toInt256() - _inputIBTAmount.toInt256();
            int256 answer1 = inputIBTAmount1.toInt256() - _inputIBTAmount.toInt256();

            if (answer0 == answer1) {
                break;
            }

            x2 = x1 - (answer1 * (x1 - x0)) / (answer1 - answer0);

            x0 = x1;
            x1 = x2;
        }
        (, uint256 borrowedIBTAmount) = previewFlashSwapIBTToExactYT(_curvePool, x2.toUint256());

        uint256 minGuess;
        uint256 maxGuess;

        if (x2.toUint256() >= x1.toUint256()) {
            maxGuess = x2.toUint256();
            minGuess = x1.toUint256();
        } else {
            maxGuess = x1.toUint256();
            minGuess = x2.toUint256();
        }

        return (maxGuess, minGuess, borrowedIBTAmount);
    }

    /**
     * @dev Given an amount of YT, previews the amount of IBT received after exchange
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
        uint256 outputIBTAmount = inputYTAmount.mulDiv(ptRate, ibtRate) -
            borrowedIBTAmount -
            _getFlashFee(pt, ibt, borrowedIBTAmount);

        return (outputIBTAmount, borrowedIBTAmount);
    }

    function previewAddLiquidityWithAsset(
        address _curvePool,
        uint256 _assets
    ) public view returns (uint256 minMintAmount) {
        address ibt = ICurvePool(_curvePool).coins(0);
        uint256 ibts = IERC4626(ibt).previewDeposit(_assets);
        minMintAmount = previewAddLiquidityWithIBT(_curvePool, ibts);
    }

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

    function previewAddLiquidity(
        address _curvePool,
        uint256[2] memory _amounts
    ) public view returns (uint256 minMintAmount) {
        minMintAmount = CurvePoolUtil.previewAddLiquidity(_curvePool, _amounts);
    }

    function previewRemoveLiquidityForAsset(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 assets) {
        uint256[2] memory minAmounts = CurvePoolUtil.previewRemoveLiquidity(_curvePool, _lpAmount);
        assets =
            IERC4626(ICurvePool(_curvePool).coins(0)).previewRedeem(minAmounts[0]) +
            IPrincipalToken(ICurvePool(_curvePool).coins(1)).previewRedeem(minAmounts[1]);
    }

    function previewRemoveLiquidityForIBT(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256 ibts) {
        uint256[2] memory minAmounts = CurvePoolUtil.previewRemoveLiquidity(_curvePool, _lpAmount);
        ibts =
            minAmounts[0] +
            IPrincipalToken(ICurvePool(_curvePool).coins(1)).previewRedeemForIBT(minAmounts[1]);
    }

    function previewRemoveLiquidity(
        address _curvePool,
        uint256 _lpAmount
    ) public view returns (uint256[2] memory minAmounts) {
        minAmounts = CurvePoolUtil.previewRemoveLiquidity(_curvePool, _lpAmount);
    }

    function previewRemoveLiquidityOneCoin(
        address _curvePool,
        uint256 _lpAmount,
        uint256 _i
    ) public view returns (uint256 minAmount) {
        minAmount = CurvePoolUtil.previewRemoveLiquidityOneCoin(_curvePool, _lpAmount, _i);
    }

    /**
     * @dev Returns the unit element of the underlying asset of the PT/IBT
     * @param _pt address of Principal Token
     * @return The unit of asset
     */
    function getUnderlyingUnit(address _pt) public view returns (uint256) {
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

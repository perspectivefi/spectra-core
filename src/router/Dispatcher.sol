// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-math/Math.sol";
import "../libraries/RayMath.sol";
import "../libraries/CurvePoolUtil.sol";
import "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IPrincipalToken} from "src/interfaces/IPrincipalToken.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";
import {Commands} from "./Commands.sol";
import {Constants} from "./Constants.sol";
import {ICurvePool} from "../interfaces/ICurvePool.sol";
import {RouterUtil} from "./util/RouterUtil.sol";

abstract contract Dispatcher is AccessManagedUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using RayMath for uint256;

    error InvalidCommandType(uint256 commandType);
    error MinimumBalanceNotReached(
        address token,
        address owner,
        uint256 minimumBalance,
        uint256 actualBalance
    );
    error InvalidTokenIndex(uint256 i, uint256 j);
    error AddressError();

    address internal msgSender;
    address public routerUtil;

    function initializeDispatcher(
        address _routerUtil,
        address _initialAuthority
    ) internal initializer {
        if (_routerUtil == address(0)) {
            revert AddressError();
        }
        routerUtil = _routerUtil;
        __AccessManaged_init(_initialAuthority);
    }

    /**
     * @dev Setter for the router utility contract
     * @param _newRouterUtil the new address of the router utility contract
     */
    function setRouterUtil(address _newRouterUtil) external restricted {
        if (_newRouterUtil == address(0)) {
            revert AddressError();
        }
        if (_newRouterUtil == routerUtil) {
            return;
        }
        routerUtil = _newRouterUtil;
    }

    /**
     * @dev Executes a single command along with its encoded input data
     * @param _commandType encoded representation of the command
     * @param _inputs calldata carrying the arguments to the functions that should be called
     */
    function _dispatch(bytes1 _commandType, bytes calldata _inputs) internal {
        uint256 command = uint8(_commandType & Commands.COMMAND_TYPE_MASK);

        if (command == Commands.TRANSFER_FROM) {
            (address token, uint256 value) = abi.decode(_inputs, (address, uint256));
            IERC20(token).safeTransferFrom(msgSender, address(this), value);
        } else if (command == Commands.TRANSFER_FROM_WITH_PERMIT) {
            (address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi
                .decode(_inputs, (address, uint256, uint256, uint8, bytes32, bytes32));
            IERC20Permit(token).permit(msgSender, address(this), value, deadline, v, r, s);
            IERC20(token).safeTransferFrom(msgSender, address(this), value);
        } else if (command == Commands.TRANSFER) {
            (address token, address recipient, uint256 value) = abi.decode(
                _inputs,
                (address, address, uint256)
            );
            recipient = _resolveAddress(recipient);
            IERC20(token).safeTransfer(
                recipient,
                value == Constants.CONTRACT_BALANCE ? IERC20(token).balanceOf(address(this)) : value
            );
        } else if (command == Commands.CURVE_SWAP) {
            (
                address pool,
                uint256 i,
                uint256 j,
                uint256 amountIn,
                uint256 minAmountOut,
                address recipient
            ) = abi.decode(_inputs, (address, uint256, uint256, uint256, uint256, address));
            address token = ICurvePool(pool).coins(i);
            amountIn = _resolveTokenValue(token, amountIn);
            recipient = _resolveAddress(recipient);
            _ensureApproved(token, pool, amountIn); // pool.coins(i) is the token to be swapped
            ICurvePool(pool).exchange(
                i,
                j,
                amountIn,
                minAmountOut,
                false, // Do not use ETH
                recipient
            );
        } else if (command == Commands.DEPOSIT_ASSET_IN_IBT) {
            (address ibt, uint256 assets, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            address asset = IERC4626(ibt).asset();
            assets = _resolveTokenValue(asset, assets);
            recipient = _resolveAddress(recipient);
            _ensureApproved(asset, ibt, assets);
            IERC4626(ibt).deposit(assets, recipient);
        } else if (command == Commands.DEPOSIT_ASSET_IN_PT) {
            (address pt, uint256 assets, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            address asset = IPrincipalToken(pt).underlying();
            assets = _resolveTokenValue(asset, assets);
            recipient = _resolveAddress(recipient);
            _ensureApproved(asset, pt, assets);
            IPrincipalToken(pt).deposit(assets, recipient);
        } else if (command == Commands.DEPOSIT_IBT_IN_PT) {
            (address pt, uint256 ibts, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            address ibt = IPrincipalToken(pt).getIBT();
            ibts = _resolveTokenValue(ibt, ibts);
            recipient = _resolveAddress(recipient);
            _ensureApproved(ibt, pt, ibts);
            IPrincipalToken(pt).depositIBT(ibts, recipient);
        } else if (
            command == Commands.REDEEM_IBT_FOR_ASSET || command == Commands.REDEEM_PT_FOR_ASSET
        ) {
            // Redeems an ERC4626 IBT or a PT for the corresponding ERC20 underlying
            // token represents the target IBT/PT and shares represents the amount of IBT/PT to redeem
            (address token, uint256 shares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            shares = _resolveTokenValue(token, shares);
            recipient = _resolveAddress(recipient);
            IERC4626(token).redeem(shares, recipient, address(this));
        } else if (command == Commands.REDEEM_PT_FOR_IBT) {
            (address pt, uint256 shares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            shares = _resolveTokenValue(pt, shares);
            recipient = _resolveAddress(recipient);
            IPrincipalToken(pt).redeemForIBT(shares, recipient, address(this));
        } else if (command == Commands.FLASH_LOAN) {
            (
                IERC3156FlashLender lender,
                IERC3156FlashBorrower receiver,
                address token,
                uint256 amount,
                bytes memory data
            ) = abi.decode(
                    _inputs,
                    (IERC3156FlashLender, IERC3156FlashBorrower, address, uint256, bytes)
                );
            lender.flashLoan(receiver, token, amount, data);
        } else if (command == Commands.CURVE_SPLIT_IBT_LIQUIDITY) {
            (address pool, uint256 ibts, address recipient, address ytRecipient) = abi.decode(
                _inputs,
                (address, uint256, address, address)
            );
            recipient = _resolveAddress(recipient);
            ytRecipient = _resolveAddress(ytRecipient);
            address ibt = ICurvePool(pool).coins(0);
            address pt = ICurvePool(pool).coins(1);
            ibts = _resolveTokenValue(ibt, ibts);
            uint256 ibtToDepositInPT = CurvePoolUtil.calcIBTsToTokenizeForCurvePool(ibts, pool, pt);
            if (ibtToDepositInPT != 0) {
                _ensureApproved(ibt, pt, ibtToDepositInPT);
                IPrincipalToken(pt).depositIBT(ibtToDepositInPT, recipient, ytRecipient);
            }
            if (recipient != address(this)) {
                IERC20(ibt).safeTransfer(recipient, ibts - ibtToDepositInPT);
            }
        } else if (command == Commands.CURVE_ADD_LIQUIDITY) {
            (
                address pool,
                uint256[2] memory amounts,
                uint256 min_mint_amount,
                address recipient
            ) = abi.decode(_inputs, (address, uint256[2], uint256, address));
            recipient = _resolveAddress(recipient);
            address ibt = ICurvePool(pool).coins(0);
            address pt = ICurvePool(pool).coins(1);
            amounts[0] = _resolveTokenValue(ibt, amounts[0]);
            amounts[1] = _resolveTokenValue(pt, amounts[1]);
            _ensureApproved(ibt, pool, amounts[0]);
            _ensureApproved(pt, pool, amounts[1]);
            ICurvePool(pool).add_liquidity(amounts, min_mint_amount, false, recipient);
        } else if (command == Commands.CURVE_REMOVE_LIQUIDITY) {
            (address pool, uint256 lps, uint256[2] memory min_amounts, address recipient) = abi
                .decode(_inputs, (address, uint256, uint256[2], address));
            recipient = _resolveAddress(recipient);
            address lpToken = ICurvePool(pool).token();
            lps = _resolveTokenValue(lpToken, lps);
            _ensureApproved(lpToken, pool, lps);
            ICurvePool(pool).remove_liquidity(lps, min_amounts, false, recipient);
        } else if (command == Commands.CURVE_REMOVE_LIQUIDITY_ONE_COIN) {
            (address pool, uint256 lps, uint256 i, uint256 min_amount, address recipient) = abi
                .decode(_inputs, (address, uint256, uint256, uint256, address));
            recipient = _resolveAddress(recipient);
            address lpToken = ICurvePool(pool).token();
            lps = _resolveTokenValue(lpToken, lps);
            _ensureApproved(lpToken, pool, lps);
            ICurvePool(pool).remove_liquidity_one_coin(lps, i, min_amount, false, recipient);
        } else if (command == Commands.ASSERT_MIN_BALANCE) {
            (address token, address owner, uint256 minValue) = abi.decode(
                _inputs,
                (address, address, uint256)
            );
            owner = _resolveAddress(owner);
            uint256 balance = IERC20(token).balanceOf(owner);
            if (balance < minValue) {
                revert MinimumBalanceNotReached(token, owner, minValue, balance);
            }
        } else {
            revert InvalidCommandType(command);
        }
    }

    /**
     * @dev Returns either the input token value as is, or replaced with its corresponding behaviour in Constants.sol
     * @param _token address of the token
     * @param _value token amount
     * @return The amount stored previously if current amount used for detecting contract balance, else current value
     */
    function _resolveTokenValue(address _token, uint256 _value) internal view returns (uint256) {
        if (_value == Constants.CONTRACT_BALANCE) {
            return IERC20(_token).balanceOf(address(this));
        } else {
            return _value;
        }
    }

    /**
     * @dev Returns either the input address as is, or replaced with its corresponding behaviour in Constants.sol
     * @param _input input address
     * @return address corresponding to input
     */
    function _resolveAddress(address _input) internal view returns (address) {
        if (_input == Constants.ADDRESS_THIS) {
            return address(this);
        } else if (_input == Constants.MSG_SENDER) {
            return msgSender;
        } else {
            return _input;
        }
    }

    /**
     * @dev Checks the allowance of a token and approves the spender if necessary
     * @param _token address of the token to be approved
     * @param _spender address of the spender
     * @param _value token amount
     */
    function _ensureApproved(address _token, address _spender, uint256 _value) internal {
        uint256 allowance = IERC20(_token).allowance(address(this), _spender);
        if (allowance < _value) {
            // This approval will only be executed the first time to save gas for subsequent operations
            IERC20(_token).safeIncreaseAllowance(_spender, type(uint256).max - allowance);
        }
    }

    /**
     * Simulates the execution of batched commands.
     * @param _commandType Type of command to be executed.
     * @param _inputs Calldata for the commands.
     * @param _spot If true, the preview uses the spot exchange rate. Otherwise, includes price impact and curve pool fees.
     * @param _previousAmount Amount of tokens from the previous command.
     * @return The preview of the rate and token amount in 27 decimals precision.
     */
    function _dispatchPreviewRate(
        bytes1 _commandType,
        bytes calldata _inputs,
        bool _spot,
        uint256 _previousAmount
    ) internal view returns (uint256, uint256) {
        uint256 command = uint8(_commandType & Commands.COMMAND_TYPE_MASK);
        if (command == Commands.TRANSFER_FROM || command == Commands.TRANSFER_FROM_WITH_PERMIT) {
            // Does not affect the rate, but amount is now set as the input value
            (address token, uint256 value) = abi.decode(_inputs, (address, uint256));
            if (_spot) {
                return (RayMath.RAY_UNIT, RouterUtil(routerUtil).getUnit(token));
            } else {
                return (RayMath.RAY_UNIT, value);
            }
        } else if (command == Commands.TRANSFER) {
            return (RayMath.RAY_UNIT, 0);
        }
        // Does not affect the amount
        else if (command == Commands.CURVE_SWAP) {
            (address pool, uint256 i, uint256 j, uint256 amountIn, , ) = abi.decode(
                _inputs,
                (address, uint256, uint256, uint256, uint256, address)
            );
            uint256 exchangeRate;
            if (_spot) {
                exchangeRate = RouterUtil(routerUtil).spotExchangeRate(pool, i, j).toRay(
                    CurvePoolUtil.CURVE_DECIMALS
                );
            } else {
                amountIn = _resolvePreviewTokenValue(amountIn, _previousAmount);
                exchangeRate = ICurvePool(pool).get_dy(i, j, amountIn).mulDiv(
                    RayMath.RAY_UNIT,
                    amountIn
                );
            }
            return (exchangeRate, 0);
        } else if (command == Commands.DEPOSIT_ASSET_IN_IBT) {
            (address ibt, uint256 assets, ) = abi.decode(_inputs, (address, uint256, address));
            if (_spot) {
                assets = RouterUtil(routerUtil).getUnit(ibt);
            } else {
                assets = _resolvePreviewTokenValue(assets, _previousAmount);
            }
            // rate : shares * rayUnit / assets
            return (IERC4626(ibt).previewDeposit(assets).mulDiv(RayMath.RAY_UNIT, assets), 0);
        } else if (command == Commands.DEPOSIT_ASSET_IN_PT) {
            (address pt, uint256 assets, ) = abi.decode(_inputs, (address, uint256, address));
            if (_spot) {
                assets = RouterUtil(routerUtil).getUnderlyingUnit(pt);
            } else {
                assets = _resolvePreviewTokenValue(assets, _previousAmount);
            }
            // rate : shares * rayUnit / assets
            return (IPrincipalToken(pt).previewDeposit(assets).mulDiv(RayMath.RAY_UNIT, assets), 0);
        } else if (command == Commands.DEPOSIT_IBT_IN_PT) {
            (address pt, uint256 ibts, ) = abi.decode(_inputs, (address, uint256, address));
            if (_spot) {
                ibts = RouterUtil(routerUtil).getUnit(pt);
            } else {
                ibts = _resolvePreviewTokenValue(ibts, _previousAmount);
            }
            // rate : shares * rayUnit / ibts
            return (IPrincipalToken(pt).previewDepositIBT(ibts).mulDiv(RayMath.RAY_UNIT, ibts), 0);
        } else if (
            command == Commands.REDEEM_IBT_FOR_ASSET || command == Commands.REDEEM_PT_FOR_ASSET
        ) {
            (address token, uint256 shares, ) = abi.decode(_inputs, (address, uint256, address));
            if (_spot) {
                shares = RouterUtil(routerUtil).getUnit(token);
            } else {
                shares = _resolvePreviewTokenValue(shares, _previousAmount);
            }
            // rate : assets * rayUnit / shares
            return (IERC4626(token).previewRedeem(shares).mulDiv(RayMath.RAY_UNIT, shares), 0);
        } else if (command == Commands.REDEEM_PT_FOR_IBT) {
            (address pt, uint256 shares, ) = abi.decode(_inputs, (address, uint256, address));
            if (_spot) {
                shares = RouterUtil(routerUtil).getUnit(pt);
            } else {
                shares = _resolvePreviewTokenValue(shares, _previousAmount);
            }
            // rate : ibts * rayUnit / shares
            return (
                IPrincipalToken(pt).previewRedeemForIBT(shares).mulDiv(RayMath.RAY_UNIT, shares),
                0
            );
        } else if (command == Commands.ASSERT_MIN_BALANCE) {
            return (RayMath.RAY_UNIT, 0);
        } else {
            revert InvalidCommandType(command);
        }
    }

    /**
     * @dev Returns either the input value as is or replaced with its corresponding behaviour in Constants.sol,
     * taking into account the previous amount in preview mode as if it were the contract balance
     * @param _value current value
     * @param _previousAmount previous value
     * @return The actual amount of tokens one needs
     */
    function _resolvePreviewTokenValue(
        uint256 _value,
        uint256 _previousAmount
    ) internal pure returns (uint256) {
        // In preview mode, the amount returned from the previous operation is used
        // to simulate the contract balance.
        if (_value == Constants.CONTRACT_BALANCE) {
            return _previousAmount;
        } else {
            return _value;
        }
    }
}

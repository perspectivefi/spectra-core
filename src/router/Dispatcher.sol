// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {Math} from "openzeppelin-math/Math.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {AccessManagedUpgradeable} from "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Commands} from "./Commands.sol";
import {Constants} from "./Constants.sol";
import {CurvePoolUtil} from "../libraries/CurvePoolUtil.sol";
import {RayMath} from "../libraries/RayMath.sol";
import {ICurvePool} from "../interfaces/ICurvePool.sol";
import {IPrincipalToken} from "src/interfaces/IPrincipalToken.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
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
    error InvalidFlashloanLender(address lender);
    error InvalidTokenIndex(uint256 i, uint256 j);
    error AddressError();
    error PermitFailed();
    error MaxInvolvedTokensExceeded();
    error BalanceUnderflow();

    // used for tracking balance changes in _previewRate
    struct TokenBalance {
        address token;
        uint256 balance;
    }

    address public immutable registry;

    address internal msgSender;
    address internal flashloanLender;
    address public routerUtil;

    constructor(address _registry) {
        if (_registry == address(0)) {
            revert AddressError();
        }
        registry = _registry;
    }

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
            try IERC20Permit(token).permit(msgSender, address(this), value, deadline, v, r, s) {
                // Permit executed successfully, proceed
            } catch {
                // Check allowance to see if permit was already executed
                uint256 allowance = IERC20(token).allowance(msgSender, address(this));
                if (allowance < value) {
                    revert PermitFailed();
                }
            }
            IERC20(token).safeTransferFrom(msgSender, address(this), value);
        } else if (command == Commands.TRANSFER) {
            (address token, address recipient, uint256 value) = abi.decode(
                _inputs,
                (address, address, uint256)
            );
            recipient = _resolveAddress(recipient);
            value = _resolveTokenValue(token, value);
            if (value != 0) {
                IERC20(token).safeTransfer(recipient, value);
            }
        } else if (command == Commands.CURVE_SWAP) {
            (
                address pool,
                uint256 i,
                uint256 j,
                uint256 amountIn,
                uint256 minAmountOut,
                address recipient
            ) = abi.decode(_inputs, (address, uint256, uint256, uint256, uint256, address));
            // pool.coins(i) is the token to be swapped
            address token = ICurvePool(pool).coins(i);
            amountIn = _resolveTokenValue(token, amountIn);
            recipient = _resolveAddress(recipient);
            IERC20(token).forceApprove(pool, amountIn);
            ICurvePool(pool).exchange(
                i,
                j,
                amountIn,
                minAmountOut,
                false, // Do not use ETH
                recipient
            );
            IERC20(token).forceApprove(pool, 0);
        } else if (command == Commands.DEPOSIT_ASSET_IN_IBT) {
            (address ibt, uint256 assets, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            address asset = IERC4626(ibt).asset();
            assets = _resolveTokenValue(asset, assets);
            recipient = _resolveAddress(recipient);
            IERC20(asset).forceApprove(ibt, assets);
            IERC4626(ibt).deposit(assets, recipient);
            IERC20(asset).forceApprove(ibt, 0);
        } else if (command == Commands.DEPOSIT_ASSET_IN_PT) {
            (
                address pt,
                uint256 assets,
                address ptRecipient,
                address ytRecipient,
                uint256 minShares
            ) = abi.decode(_inputs, (address, uint256, address, address, uint256));
            address asset = IPrincipalToken(pt).underlying();
            assets = _resolveTokenValue(asset, assets);
            ptRecipient = _resolveAddress(ptRecipient);
            ytRecipient = _resolveAddress(ytRecipient);
            bool isRegisteredPT = IRegistry(registry).isRegisteredPT(pt);
            if (isRegisteredPT) {
                _ensureApproved(asset, pt, assets);
            } else {
                IERC20(asset).forceApprove(pt, assets);
            }
            IPrincipalToken(pt).deposit(assets, ptRecipient, ytRecipient, minShares);
            if (!isRegisteredPT) {
                IERC20(asset).forceApprove(pt, 0);
            }
        } else if (command == Commands.DEPOSIT_IBT_IN_PT) {
            (
                address pt,
                uint256 ibts,
                address ptRecipient,
                address ytRecipient,
                uint256 minShares
            ) = abi.decode(_inputs, (address, uint256, address, address, uint256));
            address ibt = IPrincipalToken(pt).getIBT();
            ibts = _resolveTokenValue(ibt, ibts);
            ptRecipient = _resolveAddress(ptRecipient);
            ytRecipient = _resolveAddress(ytRecipient);
            bool isRegisteredPT = IRegistry(registry).isRegisteredPT(pt);
            if (isRegisteredPT) {
                _ensureApproved(ibt, pt, ibts);
            } else {
                IERC20(ibt).forceApprove(pt, ibts);
            }
            IPrincipalToken(pt).depositIBT(ibts, ptRecipient, ytRecipient, minShares);
            if (!isRegisteredPT) {
                IERC20(ibt).forceApprove(pt, 0);
            }
        } else if (command == Commands.REDEEM_IBT_FOR_ASSET) {
            (address ibt, uint256 shares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            shares = _resolveTokenValue(ibt, shares);
            recipient = _resolveAddress(recipient);
            IERC4626(ibt).redeem(shares, recipient, address(this));
        } else if (command == Commands.REDEEM_PT_FOR_ASSET) {
            (address pt, uint256 shares, address recipient, uint256 minAssets) = abi.decode(
                _inputs,
                (address, uint256, address, uint256)
            );
            shares = _resolveTokenValue(pt, shares);
            recipient = _resolveAddress(recipient);
            IPrincipalToken(pt).redeem(shares, recipient, address(this), minAssets);
        } else if (command == Commands.REDEEM_PT_FOR_IBT) {
            (address pt, uint256 shares, address recipient, uint256 minIbts) = abi.decode(
                _inputs,
                (address, uint256, address, uint256)
            );
            shares = _resolveTokenValue(pt, shares);
            recipient = _resolveAddress(recipient);
            IPrincipalToken(pt).redeemForIBT(shares, recipient, address(this), minIbts);
        } else if (command == Commands.FLASH_LOAN) {
            (address lender, address token, uint256 amount, bytes memory data) = abi.decode(
                _inputs,
                (address, address, uint256, bytes)
            );
            if (!IRegistry(registry).isRegisteredPT(lender)) {
                revert InvalidFlashloanLender(lender);
            }
            flashloanLender = lender;
            IERC3156FlashLender(lender).flashLoan(
                IERC3156FlashBorrower(address(this)),
                token,
                amount,
                data
            );
            flashloanLender = address(0);
        } else if (command == Commands.CURVE_SPLIT_IBT_LIQUIDITY) {
            (
                address pool,
                uint256 ibts,
                address recipient,
                address ytRecipient,
                uint256 minPTShares
            ) = abi.decode(_inputs, (address, uint256, address, address, uint256));
            recipient = _resolveAddress(recipient);
            ytRecipient = _resolveAddress(ytRecipient);
            address ibt = ICurvePool(pool).coins(0);
            address pt = ICurvePool(pool).coins(1);
            ibts = _resolveTokenValue(ibt, ibts);
            uint256 ibtToDepositInPT = CurvePoolUtil.calcIBTsToTokenizeForCurvePool(ibts, pool, pt);
            if (ibtToDepositInPT != 0) {
                bool isRegisteredPT = IRegistry(registry).isRegisteredPT(pt);
                if (isRegisteredPT) {
                    _ensureApproved(ibt, pt, ibtToDepositInPT);
                } else {
                    IERC20(ibt).forceApprove(pt, ibtToDepositInPT);
                }
                IPrincipalToken(pt).depositIBT(
                    ibtToDepositInPT,
                    recipient,
                    ytRecipient,
                    minPTShares
                );
                if (!isRegisteredPT) {
                    IERC20(ibt).forceApprove(pt, 0);
                }
            }
            if (recipient != address(this) && (ibts - ibtToDepositInPT) != 0) {
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
            IERC20(ibt).forceApprove(pool, amounts[0]);
            IERC20(pt).forceApprove(pool, amounts[1]);
            ICurvePool(pool).add_liquidity(amounts, min_mint_amount, false, recipient);
            IERC20(ibt).forceApprove(pool, 0);
            IERC20(pt).forceApprove(pool, 0);
        } else if (command == Commands.CURVE_REMOVE_LIQUIDITY) {
            (address pool, uint256 lps, uint256[2] memory min_amounts, address recipient) = abi
                .decode(_inputs, (address, uint256, uint256[2], address));
            recipient = _resolveAddress(recipient);
            address lpToken = ICurvePool(pool).token();
            lps = _resolveTokenValue(lpToken, lps);
            ICurvePool(pool).remove_liquidity(lps, min_amounts, false, recipient);
        } else if (command == Commands.CURVE_REMOVE_LIQUIDITY_ONE_COIN) {
            (address pool, uint256 lps, uint256 i, uint256 min_amount, address recipient) = abi
                .decode(_inputs, (address, uint256, uint256, uint256, address));
            recipient = _resolveAddress(recipient);
            address lpToken = ICurvePool(pool).token();
            lps = _resolveTokenValue(lpToken, lps);
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
            IERC20(_token).forceApprove(_spender, type(uint256).max);
        }
    }

    /**
     * Simulates the execution of batched commands.
     * @param _commandType Type of command to be executed.
     * @param _inputs Calldata for the commands.
     * @param _spot If true, the preview uses the spot exchange rate. Otherwise, includes price impact and curve pool fees.
     * @param _balances Array of balances to track balances changes during this preview.
     * @return The preview of the rate and token amount in 27 decimals precision.
     */
    function _dispatchPreviewRate(
        bytes1 _commandType,
        bytes calldata _inputs,
        bool _spot,
        TokenBalance[] memory _balances
    ) internal view returns (uint256) {
        uint256 command = uint8(_commandType & Commands.COMMAND_TYPE_MASK);
        if (command == Commands.TRANSFER_FROM || command == Commands.TRANSFER_FROM_WITH_PERMIT) {
            // Does not affect the rate, but amount is now set as the input value
            if (!_spot) {
                (address token, uint256 value) = abi.decode(_inputs, (address, uint256));
                _increasePreviewTokenValue(value, token, _balances);
            }
            return RayMath.RAY_UNIT;
        } else if (command == Commands.TRANSFER) {
            if (!_spot) {
                (address token, address recipient, uint256 value) = abi.decode(
                    _inputs,
                    (address, address, uint256)
                );
                recipient = _resolveAddress(recipient);
                if (recipient != address(this)) {
                    _decreasePreviewTokenValue(value, token, _balances);
                }
            }
            return RayMath.RAY_UNIT;
        }
        // Does not affect the amount
        else if (command == Commands.CURVE_SWAP) {
            (address pool, uint256 i, uint256 j, uint256 amountIn, , address recipient) = abi
                .decode(_inputs, (address, uint256, uint256, uint256, uint256, address));
            uint256 exchangeRate;
            if (_spot) {
                exchangeRate = RouterUtil(routerUtil).spotExchangeRate(pool, i, j).toRay(
                    CurvePoolUtil.CURVE_DECIMALS
                );
            } else {
                amountIn = _decreasePreviewTokenValue(
                    amountIn,
                    ICurvePool(pool).coins(i),
                    _balances
                );
                uint256 dy = ICurvePool(pool).get_dy(i, j, amountIn);
                recipient = _resolveAddress(recipient);
                if (recipient == address(this)) {
                    _increasePreviewTokenValue(dy, ICurvePool(pool).coins(j), _balances);
                }
                exchangeRate = dy.mulDiv(RayMath.RAY_UNIT, amountIn);
            }
            return exchangeRate;
        } else if (command == Commands.DEPOSIT_ASSET_IN_IBT) {
            (address ibt, uint256 assets, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            if (_spot) {
                assets = RouterUtil(routerUtil).getUnit(ibt);
            } else {
                assets = _decreasePreviewTokenValue(assets, IERC4626(ibt).asset(), _balances);
            }
            uint256 _expectedShares = IERC4626(ibt).previewDeposit(assets);
            recipient = _resolveAddress(recipient);
            if (recipient == address(this)) {
                _increasePreviewTokenValue(_expectedShares, ibt, _balances);
            }
            // rate : shares * rayUnit / assets
            return _expectedShares.mulDiv(RayMath.RAY_UNIT, assets);
        } else if (command == Commands.DEPOSIT_ASSET_IN_PT) {
            (address pt, uint256 assets, address ptRecipient, address ytRecipient) = abi.decode(
                _inputs,
                (address, uint256, address, address)
            );
            if (_spot) {
                assets = RouterUtil(routerUtil).getUnderlyingUnit(pt);
            } else {
                assets = _decreasePreviewTokenValue(
                    assets,
                    IPrincipalToken(pt).underlying(),
                    _balances
                );
            }
            uint256 _expectedShares = IPrincipalToken(pt).previewDeposit(assets);
            ptRecipient = _resolveAddress(ptRecipient);
            if (ptRecipient == address(this)) {
                _increasePreviewTokenValue(_expectedShares, pt, _balances);
            }
            ytRecipient = _resolveAddress(ytRecipient);
            if (ytRecipient == address(this)) {
                _increasePreviewTokenValue(_expectedShares, IPrincipalToken(pt).getYT(), _balances);
            }
            // rate : shares * rayUnit / assets
            return _expectedShares.mulDiv(RayMath.RAY_UNIT, assets);
        } else if (command == Commands.DEPOSIT_IBT_IN_PT) {
            (address pt, uint256 ibts, address ptRecipient, address ytRecipient) = abi.decode(
                _inputs,
                (address, uint256, address, address)
            );
            if (_spot) {
                ibts = RouterUtil(routerUtil).getUnit(pt);
            } else {
                ibts = _decreasePreviewTokenValue(ibts, IPrincipalToken(pt).getIBT(), _balances);
            }
            uint256 _expectedShares = IPrincipalToken(pt).previewDepositIBT(ibts);
            ptRecipient = _resolveAddress(ptRecipient);
            if (ptRecipient == address(this)) {
                _increasePreviewTokenValue(_expectedShares, pt, _balances);
            }
            ytRecipient = _resolveAddress(ytRecipient);
            if (ytRecipient == address(this)) {
                _increasePreviewTokenValue(_expectedShares, IPrincipalToken(pt).getYT(), _balances);
            }
            // rate : shares * rayUnit / ibts
            return _expectedShares.mulDiv(RayMath.RAY_UNIT, ibts);
        } else if (command == Commands.REDEEM_IBT_FOR_ASSET) {
            (address ibt, uint256 shares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            if (_spot) {
                shares = RouterUtil(routerUtil).getUnit(ibt);
            } else {
                shares = _decreasePreviewTokenValue(shares, ibt, _balances);
            }
            uint256 _expectedAssets = IERC4626(ibt).previewRedeem(shares);
            recipient = _resolveAddress(recipient);
            if (recipient == address(this)) {
                _increasePreviewTokenValue(_expectedAssets, IERC4626(ibt).asset(), _balances);
            }
            // rate : assets * rayUnit / shares
            return _expectedAssets.mulDiv(RayMath.RAY_UNIT, shares);
        } else if (command == Commands.REDEEM_PT_FOR_ASSET) {
            (address pt, uint256 shares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            if (_spot) {
                shares = RouterUtil(routerUtil).getUnit(pt);
            } else {
                shares = _decreasePreviewTokenValue(shares, pt, _balances);
                if (block.timestamp < IPrincipalToken(pt).maturity()) {
                    _decreasePreviewTokenValue(shares, IPrincipalToken(pt).getYT(), _balances);
                }
            }
            uint256 _expectedAssets = IPrincipalToken(pt).previewRedeem(shares);
            recipient = _resolveAddress(recipient);
            if (recipient == address(this)) {
                _increasePreviewTokenValue(
                    _expectedAssets,
                    IPrincipalToken(pt).underlying(),
                    _balances
                );
            }
            // rate : assets * rayUnit / shares
            return _expectedAssets.mulDiv(RayMath.RAY_UNIT, shares);
        } else if (command == Commands.REDEEM_PT_FOR_IBT) {
            (address pt, uint256 shares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            if (_spot) {
                shares = RouterUtil(routerUtil).getUnit(pt);
            } else {
                shares = _decreasePreviewTokenValue(shares, pt, _balances);
                if (block.timestamp < IPrincipalToken(pt).maturity()) {
                    _decreasePreviewTokenValue(shares, IPrincipalToken(pt).getYT(), _balances);
                }
            }
            uint256 _expectedIBTs = IPrincipalToken(pt).previewRedeemForIBT(shares);
            recipient = _resolveAddress(recipient);
            if (recipient == address(this)) {
                _increasePreviewTokenValue(_expectedIBTs, IPrincipalToken(pt).getIBT(), _balances);
            }
            // rate : ibts * rayUnit / shares
            return _expectedIBTs.mulDiv(RayMath.RAY_UNIT, shares);
        } else if (command == Commands.ASSERT_MIN_BALANCE) {
            return (RayMath.RAY_UNIT);
        } else {
            revert InvalidCommandType(command);
        }
    }

    /**
     * @dev Decrease balance for given token by given value in provided balances array.
     * @param _value value to subtract from token balance
     * @param _token token address
     * @param _balances TokenBalance array
     * @return The token balance BEFORE decrease
     */
    function _decreasePreviewTokenValue(
        uint256 _value,
        address _token,
        TokenBalance[] memory _balances
    ) internal pure returns (uint256) {
        if (_token == address(0)) {
            revert AddressError();
        }
        uint256 _length = _balances.length;
        for (uint256 i = 0; i < _length; ++i) {
            if (_balances[i].token == address(0)) {
                break;
            } else if (_balances[i].token == _token) {
                uint256 _res;
                if (_value == Constants.CONTRACT_BALANCE) {
                    _res = _balances[i].balance;
                    _balances[i].balance = 0;
                } else {
                    _res = _balances[i].balance;
                    if (_res < _value) {
                        revert BalanceUnderflow();
                    }
                    _balances[i].balance -= _value;
                }
                return _res;
            }
        }
        revert BalanceUnderflow();
    }

    /**
     * @dev Increase balance for given token by given value in provided balances array.
     * @param _value value to subtract from token balance
     * @param _token token address
     * @param _balances TokenBalance array
     * @return The token balance AFTER increase
     */
    function _increasePreviewTokenValue(
        uint256 _value,
        address _token,
        TokenBalance[] memory _balances
    ) internal pure returns (uint256) {
        if (_token == address(0)) {
            revert AddressError();
        }
        uint256 _length = _balances.length;
        for (uint256 i = 0; i < _length; ++i) {
            if (_balances[i].token == address(0)) {
                _balances[i] = TokenBalance(_token, _value);
                return _value;
            } else if (_balances[i].token == _token) {
                _balances[i].balance += _value;
                return _balances[i].balance;
            }
        }
        revert MaxInvolvedTokensExceeded();
    }
}

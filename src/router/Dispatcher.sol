// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {Math} from "openzeppelin-math/Math.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {Commands} from "./Commands.sol";
import {Constants} from "./Constants.sol";
import {RayMath} from "../libraries/RayMath.sol";
import {CurvePoolUtil} from "../libraries/CurvePoolUtil.sol";
import {ICurvePool} from "../interfaces/ICurvePool.sol";
import {IStableSwapNG} from "../interfaces/IStableSwapNG.sol";
import {ICurveNGPool} from "../interfaces/ICurveNGPool.sol";
import {IPrincipalToken} from "src/interfaces/IPrincipalToken.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ISpectra4626Wrapper} from "../interfaces/ISpectra4626Wrapper.sol";
import {RouterUtil} from "./util/RouterUtil.sol";
import {INATIVE} from "../interfaces/INATIVE.sol";

abstract contract Dispatcher is Initializable {
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
    error AddressError();
    error AmountError();
    error CallFailed();
    error PermitFailed();
    error MaxInvolvedTokensExceeded();
    error BalanceUnderflow();
    error KyberRouterNotSet();

    // used for tracking balance changes in _previewRate
    struct TokenBalance {
        address token;
        uint256 balance;
    }

    /** @dev registry of the protocol */
    address internal immutable registry;
    /** @dev used during a router execution to track the initiator of the execution */
    address internal msgSender;
    /** @dev used during a flashloan execution to track the lender address */
    address internal flashloanLender;
    /** @notice Router Util contract */
    address internal routerUtil;
    /** @notice Kyberswap Router */
    address internal kyberRouter;
    /** @dev used during a router execution to track the msg.value */
    uint256 internal msgValue;

    constructor(address _registry) {
        if (_registry == address(0)) {
            revert AddressError();
        }
        registry = _registry;
    }

    function __Dispatcher_init(
        address _routerUtil,
        address _kyberRouter
    ) internal onlyInitializing {
        if (_routerUtil == address(0)) {
            revert AddressError();
        }
        routerUtil = _routerUtil;
        kyberRouter = _kyberRouter;
    }

    receive() external payable {}

    /**
     * @dev Executes a single command along with its encoded input data
     * @param _commandType The encoded representation of the command
     * @param _inputs The encoded arguments for the specified command
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
        } else if (
            command == Commands.CURVE_SWAP ||
            command == Commands.CURVE_NG_SWAP ||
            command == Commands.CURVE_SWAP_SNG
        ) {
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
            if (command == Commands.CURVE_SWAP) {
                ICurvePool(pool).exchange(
                    i,
                    j,
                    amountIn,
                    minAmountOut,
                    false, // Do not use ETH
                    recipient
                );
            } else if (command == Commands.CURVE_NG_SWAP) {
                ICurveNGPool(pool).exchange(i, j, amountIn, minAmountOut, recipient);
            } else {
                IStableSwapNG(pool).exchange(
                    int128(int256(i)),
                    int128(int256(j)),
                    amountIn,
                    minAmountOut,
                    recipient
                );
            }
            IERC20(token).forceApprove(pool, 0);
        } else if (command == Commands.WRAP_VAULT_IN_4626_ADAPTER) {
            (
                address wrapper,
                uint256 vaultShares,
                address recipient,
                uint256 minWrapperShares
            ) = abi.decode(_inputs, (address, uint256, address, uint256));
            address vault = ISpectra4626Wrapper(wrapper).vaultShare();
            recipient = _resolveAddress(recipient);
            vaultShares = _resolveTokenValue(vault, vaultShares);
            IERC20(vault).forceApprove(wrapper, vaultShares);
            ISpectra4626Wrapper(wrapper).wrap(vaultShares, recipient, minWrapperShares);
            IERC20(vault).forceApprove(wrapper, 0);
        } else if (command == Commands.UNWRAP_VAULT_FROM_4626_ADAPTER) {
            (
                address wrapper,
                uint256 wrapperShares,
                address recipient,
                uint256 minVaultShares
            ) = abi.decode(_inputs, (address, uint256, address, uint256));
            recipient = _resolveAddress(recipient);
            wrapperShares = _resolveTokenValue(wrapper, wrapperShares);
            ISpectra4626Wrapper(wrapper).unwrap(
                wrapperShares,
                recipient,
                address(this),
                minVaultShares
            );
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
        } else if (command == Commands.REDEEM_PT_FOR_ASSET || command == Commands.REDEEM_PT_FOR_IBT) {
            (address pt, uint256 shares, address recipient, uint256 minOut) = abi.decode(
                _inputs,
                (address, uint256, address, uint256)
            );
            recipient = _resolveAddress(recipient);
            shares = _resolveTokenValue(pt, shares);
            uint256 redeemShares = block.timestamp < IPrincipalToken(pt).maturity()
            ? Math.min(shares, IERC20(IPrincipalToken(pt).getYT()).balanceOf(address(this)))
            : shares;
            if (command == Commands.REDEEM_PT_FOR_ASSET) {
                IPrincipalToken(pt).redeem(redeemShares, recipient, address(this), minOut);
            } else {
                IPrincipalToken(pt).redeemForIBT(redeemShares, recipient, address(this), minOut);
            }
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
        } else if (
            command == Commands.CURVE_SPLIT_IBT_LIQUIDITY ||
            command == Commands.CURVE_NG_SPLIT_IBT_LIQUIDITY ||
            command == Commands.CURVE_SPLIT_IBT_LIQUIDITY_SNG
        ) {
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
        } else if (
            command == Commands.CURVE_SPLIT_IBT_LIQUIDITY_CUSTOM_PROP ||
            command == Commands.CURVE_SPLIT_IBT_LIQUIDITY_CUSTOM_PROP_NG ||
            command == Commands.CURVE_SPLIT_IBT_LIQUIDITY_CUSTOM_PROP_SNG
        ) {
            (
                address pool,
                uint256 ibts,
                uint256 prop,
                address recipient,
                address ytRecipient,
                uint256 minPTShares
            ) = abi.decode(_inputs, (address, uint256, uint256, address, address, uint256));
            recipient = _resolveAddress(recipient);
            ytRecipient = _resolveAddress(ytRecipient);
            address ibt = ICurvePool(pool).coins(0);
            address pt = ICurvePool(pool).coins(1);
            ibts = _resolveTokenValue(ibt, ibts);
            uint256 ibtToDepositInPT = CurvePoolUtil.calcIBTsToTokenizeForCurvePoolCustomProp(
                ibts,
                prop,
                pt
            );
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
        } else if (
            command == Commands.CURVE_ADD_LIQUIDITY || command == Commands.CURVE_NG_ADD_LIQUIDITY
        ) {
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
            (command == Commands.CURVE_ADD_LIQUIDITY)
                ? ICurvePool(pool).add_liquidity(amounts, min_mint_amount, false, recipient)
                : ICurveNGPool(pool).add_liquidity(amounts, min_mint_amount, recipient);
            IERC20(ibt).forceApprove(pool, 0);
            IERC20(pt).forceApprove(pool, 0);
        } else if (
            command == Commands.CURVE_REMOVE_LIQUIDITY ||
            command == Commands.CURVE_NG_REMOVE_LIQUIDITY
        ) {
            (address pool, uint256 lps, uint256[2] memory min_amounts, address recipient) = abi
                .decode(_inputs, (address, uint256, uint256[2], address));
            recipient = _resolveAddress(recipient);
            address lpToken = (command == Commands.CURVE_REMOVE_LIQUIDITY)
                ? ICurvePool(pool).token()
                : pool;
            lps = _resolveTokenValue(lpToken, lps);
            (command == Commands.CURVE_REMOVE_LIQUIDITY)
                ? ICurvePool(pool).remove_liquidity(lps, min_amounts, false, recipient)
                : ICurveNGPool(pool).remove_liquidity(lps, min_amounts, recipient);
        } else if (
            command == Commands.CURVE_NG_REMOVE_LIQUIDITY_ONE_COIN ||
            command == Commands.CURVE_REMOVE_LIQUIDITY_ONE_COIN
        ) {
            (address pool, uint256 lps, uint256 i, uint256 min_amount, address recipient) = abi
                .decode(_inputs, (address, uint256, uint256, uint256, address));
            recipient = _resolveAddress(recipient);
            address lpToken = (command == Commands.CURVE_REMOVE_LIQUIDITY_ONE_COIN)
                ? ICurvePool(pool).token()
                : pool;
            lps = _resolveTokenValue(lpToken, lps);
            (command == Commands.CURVE_REMOVE_LIQUIDITY_ONE_COIN)
                ? ICurvePool(pool).remove_liquidity_one_coin(lps, i, min_amount, false, recipient)
                : ICurveNGPool(pool).remove_liquidity_one_coin(lps, i, min_amount, recipient);
        } else if (command == Commands.KYBER_SWAP) {
            if (kyberRouter == address(0)) {
                revert KyberRouterNotSet();
            }
            (address tokenIn, uint256 amountIn, address tokenOut, , bytes memory targetData) = abi
                .decode(_inputs, (address, uint256, address, uint256, bytes));
            if (tokenOut == Constants.ETH) {
                revert AddressError();
            }
            if (tokenIn == Constants.ETH) {
                if (msgValue != amountIn) {
                    revert AmountError();
                }
                (bool success, ) = kyberRouter.call{value: msgValue}(targetData);
                if (!success) {
                    revert CallFailed();
                }
            } else {
                amountIn = _resolveTokenValue(tokenIn, amountIn);
                IERC20(tokenIn).forceApprove(kyberRouter, amountIn);
                (bool success, ) = kyberRouter.call(targetData);
                if (!success) {
                    revert CallFailed();
                }
                IERC20(tokenIn).forceApprove(kyberRouter, 0);
            }
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
        } else if (command == Commands.CURVE_ADD_LIQUIDITY_SNG) {
            (
                address pool,
                uint256[] memory amounts,
                uint256 min_mint_amount,
                address recipient
            ) = abi.decode(_inputs, (address, uint256[], uint256, address));

            recipient = _resolveAddress(recipient);
            address ibt = IStableSwapNG(pool).coins(0);
            address pt = IStableSwapNG(pool).coins(1);
            amounts[0] = _resolveTokenValue(ibt, amounts[0]);
            amounts[1] = _resolveTokenValue(pt, amounts[1]);
            IERC20(ibt).forceApprove(pool, amounts[0]);
            IERC20(pt).forceApprove(pool, amounts[1]);
            IStableSwapNG(pool).add_liquidity(amounts, min_mint_amount, recipient);
            IERC20(ibt).forceApprove(pool, 0);
            IERC20(pt).forceApprove(pool, 0);
        } else if (command == Commands.CURVE_REMOVE_LIQUIDITY_SNG) {
            (address pool, uint256 lps, uint256[] memory min_amounts, address recipient) = abi
                .decode(_inputs, (address, uint256, uint256[], address));
            recipient = _resolveAddress(recipient);
            lps = _resolveTokenValue(pool, lps);
            IStableSwapNG(pool).remove_liquidity(lps, min_amounts, recipient);
        } else if (command == Commands.CURVE_REMOVE_LIQUIDITY_ONE_COIN_SNG) {
            (address pool, uint256 lps, int128 i, uint256 min_amount, address recipient) = abi
                .decode(_inputs, (address, uint256, int128, uint256, address));
            recipient = _resolveAddress(recipient);
            lps = _resolveTokenValue(pool, lps);
            IStableSwapNG(pool).remove_liquidity_one_coin(lps, i, min_amount, recipient);
        } else if (command == Commands.DEPOSIT_NATIVE_IN_WRAPPER) {
            (address wrapper, uint256 amount) = abi.decode(_inputs, (address, uint256));
            INATIVE(wrapper).deposit{value: amount}();
        } else if (command == Commands.WITHDRAW_NATIVE_FROM_WRAPPER) {
            (address wrapper, uint256 amount) = abi.decode(_inputs, (address, uint256));
            INATIVE(wrapper).withdraw(amount);
        } else if (command == Commands.TRANSFER_NATIVE) {
            (address recipient, uint256 amount) = abi.decode(_inputs, (address, uint256));
            (bool success, ) = payable(recipient).call{value: amount}("");
            if (!success) {
                revert CallFailed();
            }
        } else {
            revert InvalidCommandType(command);
        }
    }

    /**
     * @dev Returns either the input token value as is, or replaced with its corresponding behaviour in Constants.sol
     * @param _token The address of the token
     * @param _value The token amount
     * @return The amount stored previously if current amount used for detecting contract balance, else current value
     */
    function _resolveTokenValue(address _token, uint256 _value) internal view returns (uint256) {
        return
            (_value == Constants.CONTRACT_BALANCE)
                ? IERC20(_token).balanceOf(address(this))
                : _value;
    }

    /**
     * @dev Returns either the input address as is, or replaced with its corresponding behaviour in Constants.sol
     * @param _input The input address
     * @return The address corresponding to input
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
     * @dev Simulates the execution of a command and returns the expected resulting rate
     * @param _commandType The encoded representation of the command
     * @param _inputs The encoded arguments for the specified command
     * @param _spot If set to true, spot exchange rate is used for swaps. Additionally for all commands,
     *              input amounts are disregarded, and one unit of the token of interest is used instead.
     *              If set to false, the function includes price impact and curve pool fees for swaps.
     * @param _balances Array of balances to track balances changes during this preview
     * @return The preview rate value, which represents the amount of output token obtained for each wei
     * of input token, multiplied by 1 ray unit.
     */
    function _dispatchPreviewRate(
        bytes1 _commandType,
        bytes calldata _inputs,
        bool _spot,
        TokenBalance[] memory _balances
    ) internal view returns (uint256) {
        uint256 command = uint8(_commandType & Commands.COMMAND_TYPE_MASK);
        if (command == Commands.TRANSFER_FROM || command == Commands.TRANSFER_FROM_WITH_PERMIT) {
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
        } else if (
            command == Commands.CURVE_SWAP ||
            command == Commands.CURVE_NG_SWAP ||
            command == Commands.CURVE_SWAP_SNG
        ) {
            (address pool, uint256 i, uint256 j, uint256 amountIn, , address recipient) = abi
                .decode(_inputs, (address, uint256, uint256, uint256, uint256, address));
            uint256 exchangeRate;
            if (_spot) {
                // rate : spotExchangeRate * (ibtUnit / curveUnit) * rayUnit / ibtUnit
                uint256 rate = (command == Commands.CURVE_SWAP || command == Commands.CURVE_NG_SWAP)
                    ? RouterUtil(routerUtil).spotExchangeRate(pool, i, j)
                    : RouterUtil(routerUtil).spotExchangeRateSNG(
                        pool,
                        int128(int256(i)),
                        int128(int256(j))
                    );
                exchangeRate = rate.toRay(CurvePoolUtil.CURVE_DECIMALS);
            } else {
                amountIn = _decreasePreviewTokenValue(
                    amountIn,
                    ICurvePool(pool).coins(i),
                    _balances
                );
                uint256 dy;
                if (command == Commands.CURVE_SWAP_SNG) {
                    dy = IStableSwapNG(pool).get_dy(int128(int256(i)), int128(int256(j)), amountIn);
                } else {
                    dy = ICurvePool(pool).get_dy(i, j, amountIn);
                }
                recipient = _resolveAddress(recipient);
                if (recipient == address(this)) {
                    _increasePreviewTokenValue(dy, ICurvePool(pool).coins(j), _balances);
                }
                // rate : dy * rayUnit / amountIn
                exchangeRate = dy.mulDiv(RayMath.RAY_UNIT, amountIn);
            }
            return exchangeRate;
        } else if (command == Commands.WRAP_VAULT_IN_4626_ADAPTER) {
            (address wrapper, uint256 vaultShares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            address vault = ISpectra4626Wrapper(wrapper).vaultShare();
            if (_spot) {
                vaultShares = RouterUtil(routerUtil).getUnit(vault);
            } else {
                vaultShares = _decreasePreviewTokenValue(vaultShares, vault, _balances);
            }
            uint256 _expectedWrapperShares = ISpectra4626Wrapper(wrapper).previewWrap(vaultShares);
            recipient = _resolveAddress(recipient);
            if (recipient == address(this)) {
                _increasePreviewTokenValue(_expectedWrapperShares, wrapper, _balances);
            }
            // rate : expectedWrapperShares * rayUnit / vaultShares
            return _expectedWrapperShares.mulDiv(RayMath.RAY_UNIT, vaultShares);
        } else if (command == Commands.UNWRAP_VAULT_FROM_4626_ADAPTER) {
            (address wrapper, uint256 wrapperShares, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            if (_spot) {
                wrapperShares = RouterUtil(routerUtil).getUnit(wrapper);
            } else {
                wrapperShares = _decreasePreviewTokenValue(wrapperShares, wrapper, _balances);
            }
            uint256 _expectedVaultShares = ISpectra4626Wrapper(wrapper).previewUnwrap(
                wrapperShares
            );
            recipient = _resolveAddress(recipient);
            if (recipient == address(this)) {
                _increasePreviewTokenValue(
                    _expectedVaultShares,
                    ISpectra4626Wrapper(wrapper).vaultShare(),
                    _balances
                );
            }
            // rate : expectedVaultShares * rayUnit / wrapperShares
            return _expectedVaultShares.mulDiv(RayMath.RAY_UNIT, wrapperShares);
        } else if (command == Commands.DEPOSIT_ASSET_IN_IBT) {
            (address ibt, uint256 assets, address recipient) = abi.decode(
                _inputs,
                (address, uint256, address)
            );
            address asset = IERC4626(ibt).asset();
            if (_spot) {
                assets = RouterUtil(routerUtil).getUnit(asset);
            } else {
                assets = _decreasePreviewTokenValue(assets, asset, _balances);
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
                assets = RouterUtil(routerUtil).getPTUnderlyingUnit(pt);
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
        } else if (command == Commands.KYBER_SWAP) {
            if (kyberRouter == address(0)) {
                revert KyberRouterNotSet();
            }
            (address tokenIn, uint256 amountIn, address tokenOut, uint256 expectedAmountOut) = abi
                .decode(_inputs, (address, uint256, address, uint256));
            if (tokenOut == Constants.ETH) {
                revert AddressError();
            }
            if (tokenIn != Constants.ETH) {
                amountIn = _decreasePreviewTokenValue(amountIn, tokenIn, _balances);
            }
            _increasePreviewTokenValue(expectedAmountOut, tokenOut, _balances);

            // rate : expectedAmountOut * rayUnit / amountIn
            return expectedAmountOut.mulDiv(RayMath.RAY_UNIT, amountIn);
        } else if (command == Commands.ASSERT_MIN_BALANCE) {
            return (RayMath.RAY_UNIT);
        } else {
            revert InvalidCommandType(command);
        }
    }

    /**
     * @dev Decrease balance for given token by given value in provided balances array
     * @param _value The value to subtract from token balance
     * @param _token The token address
     * @param _balances The TokenBalance array
     * @return The actual value to subtract from token balance
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
                if (_value == Constants.CONTRACT_BALANCE) {
                    uint256 _res = _balances[i].balance;
                    _balances[i].balance = 0;
                    return _res;
                } else {
                    if (_balances[i].balance < _value) {
                        break;
                    }
                    _balances[i].balance -= _value;
                    return _value;
                }
            }
        }
        revert BalanceUnderflow();
    }

    /**
     * @dev Increase balance for given token by given value in provided balances array
     * @param _value The value to subtract from token balance
     * @param _token The token address
     * @param _balances The TokenBalance array
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

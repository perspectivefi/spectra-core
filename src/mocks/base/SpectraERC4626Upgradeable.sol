// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts/interfaces/IERC4626.sol";
import "openzeppelin-math/Math.sol";

/**
 * @dev Implementation of the ERC4626 "Tokenized Vault Standard" as defined in
 * https://eips.ethereum.org/EIPS/eip-4626[EIP-4626].
 *
 * This extension allows the minting and burning of "shares" (represented using the ERC20 inheritance) in exchange for
 * underlying "assets" through standardized {deposit}, {mint}, {redeem} and {burn} workflows. This contract extends
 * the ERC20 standard. Any additional extensions included along it would affect the "shares" token represented by this
 * contract and not the "assets" token which is an independent contract.
 *
 * CAUTION: Deposits and withdrawals may incur unexpected slippage. Users should verify that the amount received of
 * shares or assets is as expected. EOAs should operate through a wrapper that performs these checks such as
 * https://github.com/fei-protocol/ERC4626#erc4626router-and-base[ERC4626Router].
 *
 * _Available since v4.7._
 */
abstract contract SpectraERC4626Upgradeable is Initializable, ERC20Upgradeable, IERC4626 {
    using Math for uint256;

    IERC20Metadata internal _asset;

    error SharesMoreThanMaxValue();

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    function __SpectraERC4626_init(IERC20Metadata asset_) internal onlyInitializing {
        __SpectraERC4626_init_unchained(asset_);
    }

    function __SpectraERC4626_init_unchained(IERC20Metadata asset_) internal onlyInitializing {
        _asset = asset_;
    }

    /** @dev See {IERC4626-asset}. */
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4626-maxWithdraw}. */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    /** @dev See {IERC4626-previewMint}. */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /** @dev See {IERC4626-previewRedeem}. */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-mint}. */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        if (shares > maxMint(receiver)) {
            revert SharesMoreThanMaxValue();
        }
        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        if (shares > maxRedeem(owner)) {
            revert SharesMoreThanMaxValue();
        }
        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? shares.mulDiv(10 ** _asset.decimals(), 10 ** decimals(), rounding)
                : shares.mulDiv(totalAssets(), supply, rounding);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the pt contract, which is assumed not malicious.
        //
        // Conclusion: The transfer should occur before minting so that any reentrancy happens before
        // the assets are transferred and before shares are minted, maintaining a valid state.
        // slither-disable-next-line reentrancy-no-eth
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the pt contract, which is assumed not malicious.
        //
        // Conclusion: The transfer should occur after the burn to ensure that any reentrancy happens after the
        // shares are burned and the assets are transferred, maintaining a valid state.
        _burn(owner, shares);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting Floor storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

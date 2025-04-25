// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-math/Math.sol";
import "../interfaces/IMockToken.sol";

abstract contract MockERC4626Custom is ERC4626 {
    using Math for uint256;

    uint8 private _decimals;
    uint16 private rateChange;
    uint256 private unit;

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        uint8 decimals_,
        uint16 rateChange_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        _decimals = decimals_;
        rateChange = rateChange_;
        unit = 10 ** decimals_;
    }

    /** @dev Similar to {IERC4626-deposit} except the rate increases by 50% after deposit. */
    function depositRateIncreasesConstant(
        uint256 assets,
        address receiver
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        changeRate(rateChange, true);

        return shares;
    }

    /** @dev Similar to {IERC4626-withdraw} except a fee taken on deposit that is piecewise linear. */
    function depositFeeThreshold(
        uint256 threshold,
        uint256 lowFee,
        uint256 highFee,
        uint256 assets,
        address receiver
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);

        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDepositFeeThreshold(threshold, lowFee, highFee, assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /** @dev Similar to {IERC4626-previewRedeem} except a fee taken on deposit that is piecewise linear. */
    function previewDepositFeeThreshold(
        uint256 threshold,
        uint256 lowFee,
        uint256 highFee,
        uint256 assets
    ) public view virtual returns (uint256) {
        uint256 _assets = assets <= threshold
            ? assets.mulDiv(unit - lowFee, unit)
            : assets.mulDiv(unit - highFee, unit);
        return _convertToShares(_assets, Math.Rounding.Floor);
    }

    /** @dev Similar to {IERC4626-redeem} except a fee taken on redeeming that is piecewise linear. */
    function redeemFeeThreshold(
        uint256 threshold,
        uint256 lowFee,
        uint256 highFee,
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        uint256 assets = previewRedeemFeeThreshold(threshold, lowFee, highFee, shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    /** @dev Similar to {IERC4626-previewRedeem} except a fee taken on redeeming that is piecewise linear. */
    function previewRedeemFeeThreshold(
        uint256 threshold,
        uint256 lowFee,
        uint256 highFee,
        uint256 shares
    ) public view virtual returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        if (shares <= threshold) {
            return assets.mulDiv(unit - lowFee, unit);
        } else {
            return assets.mulDiv(unit - highFee, unit);
        }
    }

    /** @dev Similar to {IERC4626-deposit} except the rate increases depending on the deposited assets after deposit. */
    function depositRateIncreasesProportionally(
        uint256 assets,
        address receiver
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        uint256 _rateChange = assets.mulDiv(100, totalAssets());
        changeRate(uint16(_rateChange), true);

        return shares;
    }

    /** @dev Similar to {IERC4626-deposit} except the rate decreases by 50% after deposit. */
    function depositRateDecreasesConstant(
        uint256 assets,
        address receiver
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        changeRate(rateChange, false);

        return shares;
    }

    /** @dev Similar to {IERC4626-deposit} except the rate decreases depending on the deposited assets after deposit. */
    function depositRateDecreasesProportionally(
        uint256 assets,
        address receiver
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        uint256 _rateChange = assets.mulDiv(100, totalAssets());
        if (_rateChange > 100) {
            _rateChange = 100;
        }
        changeRate(uint16(_rateChange), false);

        return shares;
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return _decimals - IERC20Metadata(asset()).decimals();
    }

    /**
     * @notice Allows anyone to change the price per full share of this IBT vault (price of IBT in underlying)
     * @param _rateChange The percentage change in the rate
     * @param isIncrease Whether the rate change is an increase or decrease
     */
    function changeRate(uint16 _rateChange, bool isIncrease) public {
        uint256 amount = totalAssets().mulDiv(_rateChange, 100);
        if (isIncrease) {
            IMockToken(asset()).mint(address(this), amount);
        } else {
            IMockToken(asset()).burn(address(this), amount);
        }
    }
}

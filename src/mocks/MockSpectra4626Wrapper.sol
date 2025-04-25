// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "./base/Spectra4626Wrapper.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @dev This contract is primarly used to test Router commands related to Spectra4626Wrapper.
 * The wrapper is instantiated on top of an already ERC4626-compliant vault, for testing purpose.
 */
contract MockSpectra4626Wrapper is Spectra4626Wrapper {
    using Math for uint256;
    using SafeERC20 for IERC20;

    function initialize(address _mockVault, address _initialAuthority) external initializer {
        address _mockAsset = IERC4626(_mockVault).asset();
        __Spectra4626Wrapper_init(_mockAsset, _mockVault, _initialAuthority);
        IERC20(_mockAsset).forceApprove(_mockVault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @dev See {IERC4626-totalAssets}.
    function totalAssets() public view override(IERC4626, ERC4626Upgradeable) returns (uint256) {
        return _convertToAssets(totalSupply(), Math.Rounding.Floor);
    }

    /*//////////////////////////////////////////////////////////////
                    ERC4626 INTERNAL OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override(ERC4626Upgradeable) {
        super._deposit(caller, receiver, assets, shares);
        IERC4626(vaultShare()).deposit(assets, receiver);
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
    ) internal override(ERC4626Upgradeable) {
        IERC4626(vaultShare()).withdraw(assets, receiver, owner);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Internal conversion function (from assets to shares) with support for rounding direction.
    /// @param assets The amount of assets to convert.
    /// @param rounding The rounding direction to use.
    /// @return The amount of shares.
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view override(ERC4626Upgradeable) returns (uint256) {
        if (assets == 0) {
            return 0;
        }
        uint256 vaultAmount = IERC4626(vaultShare()).convertToShares(assets);
        return _previewWrap(vaultAmount, rounding);
    }

    /// @dev Internal conversion function (from shares to assets) with support for rounding direction.
    /// @param shares The amount of shares to convert.
    /// @param rounding The rounding direction to use.
    /// @return The amount of assets.
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view override(ERC4626Upgradeable) returns (uint256) {
        if (shares == 0) {
            return 0;
        }
        uint256 vaultAmount = _previewUnwrap(shares, rounding);
        return IERC4626(vaultShare()).convertToAssets(vaultAmount);
    }
}

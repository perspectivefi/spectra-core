// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRewardsProxy} from "../../interfaces/IRewardsProxy.sol";
import {ISpectra4626Wrapper} from "../../interfaces/ISpectra4626Wrapper.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

/// @dev This contract implements a wrapper to facilitate compliance of an interest-bearing vault with the ERC-4626 standard,
/// making it compatible for deploying a Spectra Principal Token.
abstract contract Spectra4626Wrapper is
    ERC4626Upgradeable,
    AccessManagedUpgradeable,
    ISpectra4626Wrapper
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:spectra.storage.Spectra4626Wrapper
    struct Spectra4626WrapperStorage {
        address _vaultShare;
        address _rewardsProxy;
    }

    // keccak256(abi.encode(uint256(keccak256("spectra.storage.Spectra4626Wrapper")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant Spectra4626WrapperStorageLocation =
        0x59ff202e9c72f33fbb7c107cbf037f949ff0624b6b8b7e53ab05f0c445903000;

    function _getSpectra4626WrapperStorage()
        private
        pure
        returns (Spectra4626WrapperStorage storage $)
    {
        assembly {
            $.slot := Spectra4626WrapperStorageLocation
        }
    }

    /// @dev Set the vault share contract to wrap, and calls parent initializers.
    function __Spectra4626Wrapper_init(
        address asset_,
        address vaultShare_,
        address initialAuthority_
    ) internal onlyInitializing {
        __Spectra4626Wrapper_init_unchained(vaultShare_);
        __ERC4626_init(IERC20(asset_));
        __ERC20_init(_wrapperName(), _wrapperSymbol());
        __AccessManaged_init(initialAuthority_);
    }

    function __Spectra4626Wrapper_init_unchained(address _vaultShare) internal onlyInitializing {
        Spectra4626WrapperStorage storage $ = _getSpectra4626WrapperStorage();
        $._vaultShare = _vaultShare;
    }

    /// @dev See {ISpectra4626Wrapper-vaultShare}.
    function vaultShare() public view virtual returns (address) {
        Spectra4626WrapperStorage storage $ = _getSpectra4626WrapperStorage();
        return $._vaultShare;
    }

    /// @dev See {ISpectra4626Wrapper-totalVaultShares}.
    function totalVaultShares() public view virtual returns (uint256) {
        Spectra4626WrapperStorage storage $ = _getSpectra4626WrapperStorage();
        return IERC20($._vaultShare).balanceOf(address(this));
    }

    /// @dev See {ISpectra4626Wrapper-rewardsProxy}.
    function rewardsProxy() public view returns (address) {
        Spectra4626WrapperStorage storage $ = _getSpectra4626WrapperStorage();
        return $._rewardsProxy;
    }

    /// @dev See {IERC20Metadata-decimals}.
    function decimals()
        public
        view
        virtual
        override(IERC20Metadata, ERC4626Upgradeable)
        returns (uint8)
    {
        return IERC20Metadata(vaultShare()).decimals() + _decimalsOffset();
    }

    /// @dev See {ISpectra4626Wrapper-previewWrap}.
    function previewWrap(uint256 vaultShares) public view virtual returns (uint256) {
        return _previewWrap(vaultShares, Math.Rounding.Floor);
    }

    /// @dev See {ISpectra4626Wrapper-previewUnwrap}.
    function previewUnwrap(uint256 shares) public view virtual returns (uint256) {
        return _previewUnwrap(shares, Math.Rounding.Floor);
    }

    /// @dev See {ISpectra4626Wrapper-wrap}.
    function wrap(uint256 vaultShares, address receiver) public virtual returns (uint256) {
        address caller = _msgSender();
        uint256 sharesToMint = previewWrap(vaultShares);
        IERC20(vaultShare()).safeTransferFrom(caller, address(this), vaultShares);
        _mint(receiver, sharesToMint);
        emit Wrap(caller, receiver, vaultShares, sharesToMint);
        return sharesToMint;
    }

    /// @dev See {ISpectra4626Wrapper-wrap}.
    function wrap(
        uint256 vaultShares,
        address receiver,
        uint256 minShares
    ) public virtual returns (uint256) {
        uint256 sharesToMint = wrap(vaultShares, receiver);
        if (sharesToMint < minShares) {
            revert ERC5143SlippageProtectionFailed();
        }
        return sharesToMint;
    }

    /// @dev See {ISpectra4626Wrapper-unwrap}.
    function unwrap(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256) {
        address caller = _msgSender();
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        uint256 vaultSharesToTransfer = previewUnwrap(shares);
        _burn(owner, shares);
        IERC20(vaultShare()).safeTransfer(receiver, vaultSharesToTransfer);
        emit Unwrap(caller, receiver, owner, shares, vaultSharesToTransfer);
        return vaultSharesToTransfer;
    }

    /// @dev See {ISpectra4626Wrapper-unwrap}.
    function unwrap(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minVaultShares
    ) public virtual returns (uint256) {
        uint256 vaultSharesToTransfer = unwrap(shares, receiver, owner);
        if (vaultSharesToTransfer < minVaultShares) {
            revert ERC5143SlippageProtectionFailed();
        }
        return vaultSharesToTransfer;
    }

    /// @dev See {ISpectra4626Wrapper-claimRewards}. */
    function claimRewards(bytes memory data) external virtual restricted {
        address _rewardsProxy = rewardsProxy();
        if (_rewardsProxy == address(0) || _rewardsProxy.code.length == 0) {
            revert NoRewardsProxy();
        }
        bytes memory data2 = abi.encodeCall(IRewardsProxy(address(0)).claimRewards, (data));
        (bool success, ) = _rewardsProxy.delegatecall(data2);
        if (!success) {
            revert ClaimRewardsFailed();
        }
    }

    /// @dev See {ISpectra4626Wrapper-setRewardsProxy}.
    function setRewardsProxy(address newRewardsProxy) public virtual restricted {
        // Note: address zero is allowed in order to disable the claim proxy
        _setRewardsProxy(newRewardsProxy);
    }

    /// @dev Internal conversion function (from vault shares to wrapper shares) with support for rounding direction.
    function _previewWrap(
        uint256 vaultShares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        return
            vaultShares.mulDiv(
                totalSupply() + 10 ** _decimalsOffset(),
                totalVaultShares() + 1,
                rounding
            );
    }

    /// @dev Internal conversion function (from wrapper shares to vault shares) with support for rounding direction.
    function _previewUnwrap(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        return
            shares.mulDiv(
                totalVaultShares() + 1,
                totalSupply() + 10 ** _decimalsOffset(),
                rounding
            );
    }

    /// @dev Internal getter to build wrapper name
    function _wrapperName() internal view virtual returns (string memory wrapperName) {
        wrapperName = string.concat(
            "Spectra ERC4626 Wrapper: ",
            IERC20Metadata(vaultShare()).name()
        );
    }

    /// @dev Internal getter to build wrapper symbol
    function _wrapperSymbol() internal view virtual returns (string memory wrapperSymbol) {
        wrapperSymbol = string.concat("sw-", IERC20Metadata(vaultShare()).symbol());
    }

    /// @dev Updates the rewards proxy. Internal function with no access restriction.
    function _setRewardsProxy(address newRewardsProxy) internal virtual {
        Spectra4626WrapperStorage storage $ = _getSpectra4626WrapperStorage();
        address oldRewardsProxy = $._rewardsProxy;
        $._rewardsProxy = newRewardsProxy;
        emit RewardsProxyUpdated(oldRewardsProxy, newRewardsProxy);
    }
}

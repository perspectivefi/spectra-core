// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @dev Interface of Spectra4626Wrapper.
interface ISpectra4626Wrapper is IERC4626 {
    /// @dev Emitted when vault shares are deposited in the wrapper.
    event Wrap(
        address indexed caller,
        address indexed receiver,
        uint256 vaultShares,
        uint256 shares
    );

    /// @dev Emitted when vault shares are withdrawn from the wrapper.
    event Unwrap(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 shares,
        uint256 vaultShares
    );

    /// @dev Emitted when rewards proxy is updated.
    event RewardsProxyUpdated(address oldRewardsProxy, address newRewardsProxy);

    error ERC5143SlippageProtectionFailed();
    error NoRewardsProxy();
    error ClaimRewardsFailed();

    /// @dev Returns the address of the wrapped vault share.
    function vaultShare() external view returns (address);

    /// @dev Returns the vault share balance of the wrapper.
    function totalVaultShares() external view returns (uint256);

    /// @dev Returns the rewards proxy of the wrapper.
    function rewardsProxy() external view returns (address);

    /// @dev Allows to preview the amount of minted wrapper shares for a given amount of deposited vault shares.
    /// @param vaultShares The amount of vault shares to deposit.
    /// @return The amount of minted vault shares.
    function previewWrap(uint256 vaultShares) external view returns (uint256);

    /// @dev Allows to preview the amount of withdrawn vault shares for a given amount of redeemed wrapper shares.
    /// @param shares The amount of wrapper shares to redeem.
    /// @return The amount of withdrawn vault shares.
    function previewUnwrap(uint256 shares) external view returns (uint256);

    /// @dev Allows the owner to deposit vault shares into the wrapper.
    /// @param vaultShares The amount of vault shares to deposit.
    /// @param receiver The address to receive the wrapper shares.
    /// @return The amount of minted wrapper shares.
    function wrap(uint256 vaultShares, address receiver) external returns (uint256);

    /// @dev Allows the owner to deposit vault shares into the wrapper, with support for slippage protection.
    /// @param vaultShares The amount of vault shares to deposit.
    /// @param receiver The address to receive the wrapper shares.
    /// @param minShares The minimum allowed wrapper shares from this deposit.
    /// @return The amount of minted wrapper shares.
    function wrap(
        uint256 vaultShares,
        address receiver,
        uint256 minShares
    ) external returns (uint256);

    /// @dev Allows the owner to withdraw vault shares from the wrapper.
    /// @param shares The amount of wrapper shares to redeem.
    /// @param receiver The address to receive the vault shares.
    /// @param owner The address of the owner of the wrapper shares.
    /// @return The amount of withdrawn vault shares.
    function unwrap(uint256 shares, address receiver, address owner) external returns (uint256);

    /// @dev Allows the owner to withdraw vault shares from the wrapper, with support for slippage protection.
    /// @param shares The amount of wrapper shares to redeem.
    /// @param receiver The address to receive the vault shares.
    /// @param owner The address of the owner of the wrapper shares.
    /// @param minVaultShares The minimum vault shares that should be returned.
    /// @return The amount of withdrawn vault shares.
    function unwrap(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minVaultShares
    ) external returns (uint256);

    /// @dev Setter for the rewards proxy.
    /// @param newRewardsProxy The address of the new rewards proxy.
    function setRewardsProxy(address newRewardsProxy) external;

    /// @dev Claims rewards for the wrapped vault.
    /// @param data The optional data used for claiming rewards.
    function claimRewards(bytes calldata data) external;
}

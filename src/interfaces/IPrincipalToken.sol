// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "openzeppelin-contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";

interface IPrincipalToken is IERC20, IERC20Metadata, IERC3156FlashLender {
    /* ERRORS
     *****************************************************************************************************************/

    error InvalidDecimals();
    error BeaconNotSet();
    error PTExpired();
    error PTNotExpired();
    error RateError();
    error AddressError();
    error UnauthorizedCaller();
    error RatesAtExpiryAlreadyStored();
    error ERC5143SlippageProtectionFailed();
    error InsufficientBalance();
    error FlashLoanExceedsMaxAmount();
    error FlashLoanCallbackFailed();
    error NoRewardsProxy();
    error ClaimRewardsFailed();

    /* Functions
     *****************************************************************************************************************/

    function initialize(address _ibt, uint256 _duration, address initialAuthority) external;

    /**
     * @notice Toggle Pause
     * @dev Should only be called in extraordinary situations by the admin of the contract
     */
    function pause() external;

    /**
     * @notice Toggle UnPause
     * @dev Should only be called in extraordinary situations by the admin of the contract
     */
    function unPause() external;

    /**
     * @notice Deposits amount of assets in the PT vault
     * @param assets The amount of assets being deposited
     * @param receiver The receiver address of the shares
     * @return shares The amount of shares minted (same amount for PT & yt)
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Deposits amount of assets in the PT vault
     * @param assets The amount of assets being deposited
     * @param ptReceiver The receiver address of the PTs
     * @param ytReceiver the receiver address of the YTs
     * @return shares The amount of shares minted (same amount for PT & yt)
     */
    function deposit(
        uint256 assets,
        address ptReceiver,
        address ytReceiver
    ) external returns (uint256 shares);

    /**
     * @notice Deposits amount of assets with a lower bound on shares received
     * @param assets The amount of assets being deposited
     * @param ptReceiver The receiver address of the PTs
     * @param ytReceiver The receiver address of the YTs
     * @param minShares The minimum allowed shares from this deposit
     * @return shares The amount of shares actually minted to the receiver
     */
    function deposit(
        uint256 assets,
        address ptReceiver,
        address ytReceiver,
        uint256 minShares
    ) external returns (uint256 shares);

    /**
     * @notice Same as normal deposit but with IBTs
     * @param ibts The amount of IBT being deposited
     * @param receiver The receiver address of the shares
     * @return shares The amount of shares minted to the receiver
     */
    function depositIBT(uint256 ibts, address receiver) external returns (uint256 shares);

    /**
     * @notice Same as normal deposit but with IBTs
     * @param ibts The amount of IBT being deposited
     * @param ptReceiver The receiver address of the PTs
     * @param ytReceiver the receiver address of the YTs
     * @return shares The amount of shares minted to the receiver
     */
    function depositIBT(
        uint256 ibts,
        address ptReceiver,
        address ytReceiver
    ) external returns (uint256 shares);

    /**
     * @notice Same as normal deposit but with IBTs
     * @param ibts The amount of IBT being deposited
     * @param ptReceiver The receiver address of the PTs
     * @param ytReceiver The receiver address of the YTs
     * @param minShares The minimum allowed shares from this deposit
     * @return shares The amount of shares minted to the receiver
     */
    function depositIBT(
        uint256 ibts,
        address ptReceiver,
        address ytReceiver,
        uint256 minShares
    ) external returns (uint256 shares);

    /**
     * @notice Burns owner's shares (PTs and YTs before expiry, PTs after expiry)
     * and sends assets to receiver
     * @param shares The amount of shares to burn
     * @param receiver The address that will receive the assets
     * @param owner The owner of the shares
     * @return assets The actual amount of assets received for burning the shares
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    /**
     * @notice Burns owner's shares (PTs and YTs before expiry, PTs after expiry)
     * and sends assets to receiver
     * @param shares The amount of shares to burn
     * @param receiver The address that will receive the assets
     * @param owner The owner of the shares
     * @param minAssets The minimum assets that should be returned to user
     * @return assets The actual amount of assets received for burning the shares
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAssets
    ) external returns (uint256 assets);

    /**
     * @notice Burns owner's shares (PTs and YTs before expiry, PTs after expiry)
     * and sends IBTs to receiver
     * @param shares The amount of shares to burn
     * @param receiver The address that will receive the IBTs
     * @param owner The owner of the shares
     * @return ibts The actual amount of IBT received for burning the shares
     */
    function redeemForIBT(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 ibts);

    /**
     * @notice Burns owner's shares (PTs and YTs before expiry, PTs after expiry)
     * and sends IBTs to receiver
     * @param shares The amount of shares to burn
     * @param receiver The address that will receive the IBTs
     * @param owner The owner of the shares
     * @param minIbts The minimum IBTs that should be returned to user
     * @return ibts The actual amount of IBT received for burning the shares
     */
    function redeemForIBT(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minIbts
    ) external returns (uint256 ibts);

    /**
     * @notice Burns owner's shares (before expiry : PTs and YTs) and sends assets to receiver
     * @param assets The amount of assets to be received
     * @param receiver The address that will receive the assets
     * @param owner The owner of the shares (PTs and YTs)
     * @return shares The actual amount of shares burnt for receiving the assets
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    /**
     * @notice Burns owner's shares (before expiry : PTs and YTs) and sends assets to receiver
     * @param assets The amount of assets to be received
     * @param receiver The address that will receive the assets
     * @param owner The owner of the shares (PTs and YTs)
     * @param maxShares The maximum shares allowed to be burnt
     * @return shares The actual amount of shares burnt for receiving the assets
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxShares
    ) external returns (uint256 shares);

    /**
     * @notice Burns owner's shares (before expiry : PTs and YTs) and sends IBTs to receiver
     * @param ibts The amount of IBT to be received
     * @param receiver The address that will receive the IBTs
     * @param owner The owner of the shares (PTs and YTs)
     * @return shares The actual amount of shares burnt for receiving the IBTs
     */
    function withdrawIBT(
        uint256 ibts,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    /**
     * @notice Burns owner's shares (before expiry : PTs and YTs) and sends IBTs to receiver
     * @param ibts The amount of IBT to be received
     * @param receiver The address that will receive the IBTs
     * @param owner The owner of the shares (PTs and YTs)
     * @param maxShares The maximum shares allowed to be burnt
     * @return shares The actual amount of shares burnt for receiving the IBTs
     */
    function withdrawIBT(
        uint256 ibts,
        address receiver,
        address owner,
        uint256 maxShares
    ) external returns (uint256 shares);

    /**
     * @notice Updates _user's yield since last update
     * @param _user The user whose yield will be updated
     * @return updatedUserYieldInIBT The unclaimed yield of the user in IBT (not just the updated yield)
     */
    function updateYield(address _user) external returns (uint256 updatedUserYieldInIBT);

    /**
     * @notice Claims caller's unclaimed yield in asset
     * @param _receiver The receiver of yield
     * @param _minAssets The minimum amount of assets that should be received
     * @return yieldInAsset The amount of yield claimed in asset
     */
    function claimYield(
        address _receiver,
        uint256 _minAssets
    ) external returns (uint256 yieldInAsset);

    /**
     * @notice Claims caller's unclaimed yield in IBT
     * @param _receiver The receiver of yield
     * @param _minIBT The minimum amount of IBT that should be received
     * @return yieldInIBT The amount of yield claimed in IBT
     */
    function claimYieldInIBT(
        address _receiver,
        uint256 _minIBT
    ) external returns (uint256 yieldInIBT);

    /**
     * @notice Claims the collected ibt fees and redeems them to the fee collector
     * @param _minAssets The minimum amount of assets that should be received
     * @return assets The amount of assets sent to the fee collector
     */
    function claimFees(uint256 _minAssets) external returns (uint256 assets);

    /**
     * @notice Updates yield of both sender and receiver of YTs
     * @param _from the sender of YTs
     * @param _to the receiver of YTs
     */
    function beforeYtTransfer(address _from, address _to) external;

    /**
     * Call the claimRewards function of the rewards contract
     * @param data The optional data to be passed to the rewards contract
     */
    function claimRewards(bytes memory data) external;

    /* SETTERS
     *****************************************************************************************************************/

    /**
     * @notice Stores PT and IBT rates at expiry. Ideally, it should be called the day of expiry
     */
    function storeRatesAtExpiry() external;

    /** Set a new Rewards Proxy
     * @param _rewardsProxy The address of the new reward proxy
     */
    function setRewardsProxy(address _rewardsProxy) external;

    /* GETTERS
     *****************************************************************************************************************/

    /**
     * @notice Returns the amount of shares minted for the theorical deposited amount of assets
     * @param assets The amount of assets deposited
     * @return The amount of shares minted
     */
    function previewDeposit(uint256 assets) external view returns (uint256);

    /**
     * @notice Returns the amount of shares minted for the theorical deposited amount of IBT
     * @param ibts The amount of IBT deposited
     * @return The amount of shares minted
     */
    function previewDepositIBT(uint256 ibts) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
     * through a deposit call.
     * @param receiver The receiver of the shares
     * @return The maximum amount of assets that can be deposited
     */
    function maxDeposit(address receiver) external view returns (uint256);

    /**
     * @notice Returns the theorical amount of shares that need to be burnt to receive assets of underlying
     * @param assets The amount of assets to receive
     * @return The amount of shares burnt
     */
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /**
     * @notice Returns the theorical amount of shares that need to be burnt to receive amount of IBT
     * @param ibts The amount of IBT to receive
     * @return The amount of shares burnt
     */
    function previewWithdrawIBT(uint256 ibts) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
     * Vault, through a withdraw call.
     * @param owner The owner of the Vault shares
     * @return The maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address owner) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of the IBT that can be withdrawn from the owner balance in the
     * Vault, through a withdraw call.
     * @param owner The owner of the Vault shares
     * @return The maximum amount of IBT that can be withdrawn
     */
    function maxWithdrawIBT(address owner) external view returns (uint256);

    /**
     * @notice Returns the amount of assets received for the theorical amount of burnt shares
     * @param shares The amount of shares to burn
     * @return The amount of assets received
     */
    function previewRedeem(uint256 shares) external view returns (uint256);

    /**
     * @notice Returns the amount of IBT received for the theorical amount of burnt shares
     * @param shares The amount of shares to burn
     * @return The amount of IBT received
     */
    function previewRedeemForIBT(uint256 shares) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of Vault shares that can be redeemed by the owner
     * @notice This function behaves differently before and after expiry. Before expiry an equal amount of PT and YT
     * needs to be burnt, while after expiry only PTs are burnt.
     * @param owner The owner of the shares
     * @return The maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) external view returns (uint256);

    /**
     * Returns the total amount of the underlying asset that is owned by the Vault in the form of IBT.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Converts an underlying amount in principal. Equivalent to ERC-4626's convertToShares method.
     * @param underlyingAmount The amount of underlying (or assets) to convert
     * @return The resulting amount of principal (or shares)
     */
    function convertToPrincipal(uint256 underlyingAmount) external view returns (uint256);

    /**
     * @notice Converts a principal amount in underlying. Equivalent to ERC-4626's convertToAssets method.
     * @param principalAmount The amount of principal (or shares) to convert
     * @return The resulting amount of underlying (or assets)
     */
    function convertToUnderlying(uint256 principalAmount) external view returns (uint256);

    /**
     * @notice Returns whether or not the contract is paused.
     * @return true if the contract is paused, and false otherwise
     */
    function paused() external view returns (bool);

    /**
     * @notice Returns the unix timestamp (uint256) at which the PT contract expires
     * @return The unix timestamp (uint256) when PTs become redeemable
     */
    function maturity() external view returns (uint256);

    /**
     * @notice Returns the duration of the PT contract
     * @return The duration (in s) to expiry/maturity of the PT contract
     */
    function getDuration() external view returns (uint256);

    /**
     * @notice Returns the address of the underlying token (or asset). Equivalent to ERC-4626's asset method.
     * @return The address of the underlying token (or asset)
     */
    function underlying() external view returns (address);

    /**
     * @notice Returns the IBT address of the PT contract
     * @return ibt The address of the IBT
     */
    function getIBT() external view returns (address ibt);

    /**
     * @notice Returns the yt address of the PT contract
     * @return yt The address of the yt
     */
    function getYT() external view returns (address yt);

    /**
     * @notice Returns the current ibtRate
     * @return The current ibtRate
     */
    function getIBTRate() external view returns (uint256);

    /**
     * @notice Returns the current ptRate
     * @return The current ptRate
     */
    function getPTRate() external view returns (uint256);

    /**
     * @notice Returns 1 unit of IBT
     * @return The IBT unit
     */
    function getIBTUnit() external view returns (uint256);

    /**
     * @notice Get the unclaimed fees in IBT
     * @return The unclaimed fees in IBT
     */
    function getUnclaimedFeesInIBT() external view returns (uint256);

    /**
     * @notice Get the total collected fees in IBT (claimed and unclaimed)
     * @return The total fees in IBT
     */
    function getTotalFeesInIBT() external view returns (uint256);

    /**
     * @notice Get the tokenization fee of the PT
     * @return The tokenization fee
     */
    function getTokenizationFee() external view returns (uint256);

    /**
     * @notice Get the current IBT yield of the user
     * @param _user The address of the user to get the current yield from
     * @return The yield of the user in IBT
     */
    function getCurrentYieldOfUserInIBT(address _user) external view returns (uint256);
}

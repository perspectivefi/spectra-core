// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "openzeppelin-erc20/ERC20Upgradeable.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./base/SpectraERC4626Upgradeable.sol";
import "src/interfaces/IMockToken.sol";

contract MockIBTBeta is ERC20Upgradeable, SpectraERC4626Upgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private pricePerFullShare;
    uint256 private ASSET_UNIT;
    uint256 private IBT_UNIT;
    IMockToken private underlying;

    error MockIBTBetaUnauthorizedCall();

    /**
     * @notice Initializer of the contract.
     * @param _name The name of the mock ibt token.
     * @param _symbol The symbol of the mock ibt token.
     * @param _asset The asset of the mock ibt token.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        IERC20Metadata _asset
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __SpectraERC4626_init(_asset);
        __Ownable_init(_msgSender());
        underlying = IMockToken(address(_asset));
        ASSET_UNIT = 10 ** _asset.decimals();
        IBT_UNIT = 10 ** decimals();
        pricePerFullShare = ASSET_UNIT;
    }

    /**
     * @notice Function to deposit the provided amount in assets.
     * @param amount The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return shares The amount of shares received.
     */
    function deposit(uint256 amount, address receiver) public override returns (uint256 shares) {
        updatePricePerFullShare();
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        shares = convertToShares(amount);
        _mint(receiver, shares);
    }

    /**
     * @notice Function to withdraw the provided no of assets.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address that will receive the assets.
     * @param owner the address of the owner of the shares.
     * @return shares The burned amount of shares to withdraw assets.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(IERC4626) returns (uint256 shares) {
        if (msg.sender != owner) {
            revert MockIBTBetaUnauthorizedCall();
        }
        updatePricePerFullShare();
        shares = convertToShares(assets);
        _burn(owner, shares);
        IERC20(underlying).safeTransfer(receiver, assets);
    }

    /**
     * @notice Function to redeem the provided no of shares.
     * @param shares The amount of shares to redeem.
     * @param receiver The address that will receive the assets.
     * @param owner the address of the owner of the shares.
     * @return assets The amount of assets received for redeeming shares.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override(SpectraERC4626Upgradeable) returns (uint256 assets) {
        if (msg.sender != owner) {
            revert MockIBTBetaUnauthorizedCall();
        }
        updatePricePerFullShare();
        assets = convertToAssets(shares);
        _burn(owner, shares);
        IERC20(underlying).safeTransfer(receiver, assets);
    }

    /**
     * @notice Function to mint the provided no of shares.
     * @param shares The amount of shares to redeem.
     * @param receiver The address that will receive the assets.
     * @return assets The amount of assets used for minting shares.
     */
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = convertToAssets(shares);
        deposit(assets, receiver);
    }

    /**
     * @notice Function to update the price of IBT in its underlying token.
     */
    function updatePricePerFullShare() public {
        if (totalSupply() == 0) {
            pricePerFullShare = ASSET_UNIT;
            return;
        } else {
            pricePerFullShare = (underlying.balanceOf(address(this)) * IBT_UNIT) / totalSupply();
            return;
        }
    }

    /**
     * @notice Allows admin to burn underlying assets present in the contract, to decrease the IBT rate.
     */
    function burnUnderlying(uint256 amount) external {
        _checkOwner();
        underlying.burn(address(this), amount);
    }

    /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 _amount) public view override returns (uint256) {
        return convertToShares(_amount);
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @notice Function to get the price of IBT in its underlying token.
     * @return _price The new price of the ibt.
     */
    function getPricePerFullShare() external view returns (uint256 _price) {
        return pricePerFullShare;
    }

    /**
     * @notice Function to convert the no of shares to it's amount in assets.
     * @param shares The no of shares to convert.
     * @return The amount of assets from the specified shares.
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return (shares * pricePerFullShare) / IBT_UNIT;
    }

    /**
     * @notice Function to convert the no of assets to it's amount in shares.
     * @param assets The no of assets to convert.
     * @return The amount of shares from the specified assets.
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        if (pricePerFullShare == 0) {
            return 0;
        }
        return (assets * IBT_UNIT) / pricePerFullShare;
    }
}

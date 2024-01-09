// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "openzeppelin-erc20/ERC20Upgradeable.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/interfaces/IERC4626.sol";
import "./base/SpectraERC4626Upgradeable.sol";

contract MockIBT is ERC20Upgradeable, SpectraERC4626Upgradeable {
    using SafeERC20 for IERC20;

    uint256 private pricePerFullShare;
    uint256 private IBT_UNIT;

    /**
     * @notice Initializer of the contract.
     * @param _name The name of the mock ibt token.
     * @param _symbol The symbol of the mock ibt token.
     * @param mockAsset The mock asset of the mock ibt token.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        IERC20Metadata mockAsset
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __SpectraERC4626_init(mockAsset);
        pricePerFullShare = 1e18;
        IBT_UNIT = 10 ** mockAsset.decimals();
    }

    /**
     * @notice Function to update the price of IBT to its underlying token.
     * @param _price The new price of the ibt.
     */
    function setPricePerFullShare(uint256 _price) public {
        pricePerFullShare = _price;
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

    /**
     * @notice Function to deposit the provided amount in assets.
     * @param amount The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return shares The amount of shares received.
     */
    function deposit(uint256 amount, address receiver) public override returns (uint256 shares) {
        IERC20(address(_asset)).safeTransferFrom(msg.sender, address(this), amount);
        shares = convertToShares(amount);
        _mint(receiver, shares);
    }

    /**
     * @notice Function to withdraw the provided no of shares.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @return shares The amount of shares to burn to withdraw assets.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(IERC4626) returns (uint256 shares) {
        shares = convertToShares(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        IERC20(address(_asset)).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 _amount) public view override returns (uint256) {
        return convertToShares(_amount);
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    /** @dev See {IERC4626-previewRedeem}. */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return convertToAssets(shares);
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

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        IERC20(address(_asset)).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }
}

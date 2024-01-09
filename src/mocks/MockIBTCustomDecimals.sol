// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import "../interfaces/IMockToken.sol";

contract MockIBTCustomDecimals is ERC4626 {
    using Math for uint256;

    uint8 private _decimals;

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        uint8 decimals_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        _decimals = decimals_;
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return _decimals - IERC20Metadata(asset()).decimals();
    }

    /**
     * @notice Allows anyone to change the price per full share of this IBT vault (price of IBT in underlying)
     * @param rateChange The percentage change in the rate
     * @param isIncrease Whether the rate change is an increase or decrease
     */
    function changeRate(uint16 rateChange, bool isIncrease) external {
        uint256 amount = totalAssets().mulDiv(rateChange, 100);
        if (isIncrease) {
            IMockToken(asset()).mint(address(this), amount);
        } else {
            IMockToken(asset()).burn(address(this), amount);
        }
    }
}

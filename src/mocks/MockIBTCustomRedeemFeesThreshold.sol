// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "./MockERC4626Custom.sol";
import "../interfaces/IMockToken.sol";

contract MockIBTCustomFeesThreshold is MockERC4626Custom {
    uint256 private threshold;
    uint256 private lowFee;
    uint256 private highFee;

    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        uint8 decimals_,
        uint16 rateChange_,
        uint256 threshold_,
        uint256 lowFee_,
        uint256 highFee_
    ) MockERC4626Custom(name_, symbol_, asset_, decimals_, rateChange_) {
        threshold = threshold_;
        lowFee = lowFee_;
        highFee = highFee_;
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        assets = redeemFeeThreshold(threshold, lowFee, highFee, shares, receiver, owner);
    }

    /** @dev See {IERC4626-previewRedeem}. */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return previewRedeemFeeThreshold(threshold, lowFee, highFee, shares);
    }
}

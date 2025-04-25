// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "./MockERC4626Custom.sol";
import "../interfaces/IMockToken.sol";

contract MockIBTCustomDepositFeesThreshold is MockERC4626Custom {
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

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        return depositFeeThreshold(threshold, lowFee, highFee, assets, receiver);
    }

    /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return previewDepositFeeThreshold(threshold, lowFee, highFee, assets);
    }
}

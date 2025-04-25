// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "./MockERC4626Custom.sol";
import "../interfaces/IMockToken.sol";

contract MockIBTCustom1 is MockERC4626Custom {
    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        uint8 decimals_,
        uint16 rateChange_
    ) MockERC4626Custom(name_, symbol_, asset_, decimals_, rateChange_) {}

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = depositRateIncreasesConstant(assets, receiver);
    }
}

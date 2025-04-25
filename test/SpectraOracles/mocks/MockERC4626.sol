// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract MockERC4626 is ERC4626 {
    using Math for uint256;

    uint8 private decimalsOffset_;

    constructor(
        address underlying,
        uint8 decimalsOffset
    ) ERC20("ERC4626Mock", "E4626M") ERC4626(IERC20(underlying)) {
        decimalsOffset_ = decimalsOffset;
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max / 1e15;
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view override returns (uint256) {
        return previewDeposit(maxDeposit(address(0)));
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return decimalsOffset_;
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

contract MockRateAdjustmentOracle1 {
    uint256 public constant VALUE = 1e18;

    function value() external pure returns (uint256) {
        return VALUE;
    }
}

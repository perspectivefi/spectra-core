// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

interface ICurveAddressProvider {
    function get_address(uint256 _id) external view returns (address);
}

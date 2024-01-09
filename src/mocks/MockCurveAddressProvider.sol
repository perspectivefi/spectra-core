// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "./MockCurvePoolFactory.sol";

contract MockCurveAddressProvider {
    MockCurvePoolFactory public factory;

    error MockCurveAddressProviderError();

    constructor() {
        factory = new MockCurvePoolFactory();
    }

    function get_address(uint256 /*id*/) public view returns (address) {
        if (address(factory) == address(0)) {
            revert MockCurveAddressProviderError();
        }
        return address(factory);
    }
}

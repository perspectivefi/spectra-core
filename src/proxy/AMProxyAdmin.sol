// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/transparent/ProxyAdmin.sol)
// Modified by Spectra to use AccessManager instead of Ownable for access control

pragma solidity 0.8.20;

import {IAMTransparentUpgradeableProxy} from "./AMTransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/access/manager/AccessManaged.sol";

/**
 * @dev This is an auxiliary contract meant to be assigned as the admin of a {TransparentUpgradeableProxy}. For an
 * explanation of why you would want to use this see the documentation for {TransparentUpgradeableProxy}.
 */
contract AMProxyAdmin is AccessManaged {
    /**
     * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgrade(address)`
     * and `upgradeAndCall(address,bytes)` are present, and `upgradeTo` must be used if no function should be called,
     * while `upgradeAndCall` will invoke the `receive` function if the second argument is the empty byte string.
     * If the getter returns `"5.0.0"`, only `upgradeAndCall(address,bytes)` is present, and the second argument must
     * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
     * during an upgrade.
     */
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /**
     * @dev Sets the initial authority (the access manager) who control upgrader roles.
     */
    constructor(address initialAuthority) AccessManaged(initialAuthority) {}

    /**
     * @dev Upgrades `proxy` to `implementation` and calls a function on the new implementation.
     * See {TransparentUpgradeableProxy-_dispatchUpgradeToAndCall}.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     * - If `data` is empty, `msg.value` must be zero.
     * - msg.sender must have a role that allows them to upgrade the proxy.
     */
    function upgradeAndCall(
        IAMTransparentUpgradeableProxy proxy,
        address implementation,
        bytes memory data
    ) public payable virtual restricted {
        proxy.upgradeToAndCall{value: msg.value}(implementation, data);
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/beacon/UpgradeableBeacon.sol)
// Modified by Spectra to use AccessManager instead of Ownable for access control

pragma solidity 0.8.20;

import {IBeacon} from "openzeppelin-contracts/proxy/beacon/IBeacon.sol";
import "openzeppelin-contracts/access/manager/AccessManaged.sol";

/**
 * @title AMBeacon
 * @dev This contract is used in conjunction with one or more instances of {BeaconProxy} to determine their
 * implementation contract, which is where they will delegate all function calls.
 *
 * Previously, the contract relied on the Ownable pattern from OpenZeppelin.
 * It has been modified by Spectra to use the AccessManaged for access control instead.
 *
 * The authority can change the implementation the beacon points to, thus upgrading the proxies that use this beacon.
 */
contract AMBeacon is IBeacon, AccessManaged {
    address private _implementation;

    /**
     * @dev The `implementation` of the beacon is invalid.
     */
    error BeaconInvalidImplementation(address implementation);

    /**
     * @dev Emitted when the implementation returned by the beacon is changed.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Initializes the contract setting the address of the initial implementation and the initial authority (Access Manager contract).
     *
     * @param implementation_ Address of the initial implementation.
     * @param initialAuthority Address of the initial authority (Access Manager contract).
     */
    constructor(address implementation_, address initialAuthority) AccessManaged(initialAuthority) {
        _setImplementation(implementation_);
    }

    /**
     * @dev Returns the current implementation address.
     */
    function implementation() public view virtual returns (address) {
        return _implementation;
    }

    /**
     * @dev Upgrades the beacon to a new implementation.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must have the appropriate role in the authority.
     *   By default it is the ADMIN_ROLE of the AccessManager contract.
     *   Other roles can be used see setTargetFunctionRole(target, selectors, roleId)
     *   in AccessManager.sol (OpenZeppelin 5.0)
     * - `newImplementation` must be a contract.
     */
    function upgradeTo(address newImplementation) public virtual restricted {
        _setImplementation(newImplementation);
    }

    /**
     * @dev Sets the implementation contract address for this beacon
     *
     * Requirements:
     *
     * - `newImplementation` must be a contract.
     *
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert BeaconInvalidImplementation(newImplementation);
        }
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }
}

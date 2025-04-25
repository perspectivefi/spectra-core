// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

/**
 * @title Roles library
 * @author Spectra Finance
 * @notice Identifiers for roles used in Spectra protocol.
 */
library Roles {
    uint64 internal constant ADMIN_ROLE = 0;
    uint64 internal constant UPGRADE_ROLE = 1;
    uint64 internal constant PAUSER_ROLE = 2;
    uint64 internal constant FEE_SETTER_ROLE = 3;
    uint64 internal constant REGISTRY_ROLE = 4;
    uint64 internal constant REWARDS_HARVESTER_ROLE = 5;
    uint64 internal constant REWARDS_PROXY_SETTER_ROLE = 6;
    uint64 internal constant VOTER_GOVERNOR_ROLE = 7;
    uint64 internal constant VOTER_EMERGENCY_COUNCIL_ROLE = 8;
    uint64 internal constant VOTER_ROLE = 9;
    uint64 internal constant FEES_VOTING_REWARDS_DISTRIBUTOR_ROLE = 10;
    uint64 internal constant MINTER_ROLE = 11;
    uint64 internal constant MANAGED_DEPOSITS_ROLE = 12;
    uint64 internal constant VOTING_ESCROW_MANAGER_ROLE = 13;
    uint64 internal constant RATE_ADJUSTMENT_ORACLE_SETTER_ROLE = 14;
}

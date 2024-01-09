// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

library Roles {
    uint64 internal constant ADMIN_ROLE = 0;
    uint64 internal constant UPGRADE_ROLE = 1;
    uint64 internal constant PAUSER_ROLE = 2;
    uint64 internal constant FEE_SETTER_ROLE = 3;
    uint64 internal constant REGISTRY_ROLE = 4;
    uint64 internal constant REWARDS_HARVESTER_ROLE = 5;
    uint64 internal constant REWARDS_PROXY_SETTER_ROLE = 6;
}

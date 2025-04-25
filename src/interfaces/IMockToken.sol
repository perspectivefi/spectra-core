// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "openzeppelin-contracts/interfaces/IERC20.sol";

interface IMockToken is IERC20 {
    function mint(address receiver, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}

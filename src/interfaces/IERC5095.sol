// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";

interface IERC5095 is IERC20Metadata {
    event Redeem(address indexed from, address indexed to, uint256 amount);

    function underlying() external view returns (address underlyingAddress);

    function maturity() external view returns (uint256 timestamp);

    function convertToUnderlying(
        uint256 principalAmount
    ) external view returns (uint256 underlyingAmount);

    function convertToPrincipal(
        uint256 underlyingAmount
    ) external view returns (uint256 principalAmount);

    function maxRedeem(address holder) external view returns (uint256 maxPrincipalAmount);

    function previewRedeem(
        uint256 principalAmount
    ) external view returns (uint256 underlyingAmount);

    function redeem(
        uint256 principalAmount,
        address to,
        address from
    ) external returns (uint256 underlyingAmount);

    function maxWithdraw(address holder) external view returns (uint256 maxUnderlyingAmount);

    function previewWithdraw(
        uint256 underlyingAmount
    ) external view returns (uint256 principalAmount);

    function withdraw(
        uint256 underlyingAmount,
        address receiver,
        address holder
    ) external returns (uint256 principalAmount);
}

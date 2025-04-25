// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract MockFaucet is Initializable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    address private asset;
    address private ibt;

    error MockFaucetInvalidTokenAddress();

    /**
     * @notice Initializer of the contract.
     * @param _asset The address of the underlying token.
     * @param _ibt The address of the ibt token.
     */
    function initialize(address _asset, address _ibt) public initializer {
        __Ownable_init(_msgSender());
        asset = _asset;
        ibt = _ibt;
    }

    function setAddresses(address _asset, address _ibt) external {
        _checkOwner();
        if (_asset == address(0) || _ibt == address(0)) {
            revert MockFaucetInvalidTokenAddress();
        }
        asset = _asset;
        ibt = _ibt;
    }

    /**
     * @notice Transfer 100 asset and ibt tokens to the caller.
     */
    function faucet() external {
        IERC20(address(asset)).safeTransfer(msg.sender, 100e18);
        IERC20(address(ibt)).safeTransfer(msg.sender, 100e18);
    }
}

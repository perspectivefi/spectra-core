// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../script/10_deployAll.s.sol";
import "../../src/libraries/RayMath.sol";
import "../../src/mocks/MockUnderlyingCustomDecimals.sol";
import "../../src/mocks/MockIBTCustomDecimals.sol";
import {ERC5095Checker} from "./ERC5095Checker.t.sol";

contract TestPT5095AndDeposit is ERC5095Checker {
    // maxDeposit
    // "MUST NOT revert."
    function prop_maxDeposit(address caller, address receiver) public {
        vm.prank(caller);
        IPrincipalToken(_pt_).maxDeposit(receiver);
    }

    // previewDeposit
    // "MUST return as close to and no more than the exact amount of Vault
    // shares that would be minted in a deposit call in the same transaction.
    // I.e. deposit should return the same or more shares as previewDeposit if
    // called in the same transaction."
    function prop_previewDeposit(
        address caller,
        address receiver,
        address other,
        uint assets
    ) public {
        vm.prank(other);
        uint sharesPreview = IPrincipalToken(_pt_).previewDeposit(assets); // "MAY revert due to other conditions that would also cause deposit to revert."
        vm.prank(caller);
        uint sharesActual = IPrincipalToken(_pt_).deposit(assets, receiver);
        assertApproxGeAbs(sharesActual, sharesPreview, _delta_);
    }

    // deposit
    function prop_deposit(address caller, address receiver, uint assets) public {
        uint oldCallerAsset = IERC20(_underlying_).balanceOf(caller);
        uint oldReceiverShare = IERC20(_pt_).balanceOf(receiver);
        uint oldAllowance = IERC20(_underlying_).allowance(caller, _pt_);

        vm.prank(caller);
        uint shares = IPrincipalToken(_pt_).deposit(assets, receiver);

        uint newCallerAsset = IERC20(_underlying_).balanceOf(caller);
        uint newReceiverShare = IERC20(_pt_).balanceOf(receiver);
        uint newAllowance = IERC20(_underlying_).allowance(caller, _pt_);

        assertApproxEqAbs(newCallerAsset, oldCallerAsset - assets, _delta_, "asset"); // NOTE: this may fail if the caller is a contract in which the asset is stored
        assertApproxEqAbs(newReceiverShare, oldReceiverShare + shares, _delta_, "share");
        if (oldAllowance != type(uint).max)
            assertApproxEqAbs(newAllowance, oldAllowance - assets, _delta_, "allowance");
    }
}

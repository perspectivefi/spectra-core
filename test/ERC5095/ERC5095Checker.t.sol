// SPDX-License-Identifier: AGPL-3.0
// Modified from https://github.com/a16z/erc4626-tests

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC5095} from "../../src/interfaces/IERC5095.sol";
import "openzeppelin-contracts/interfaces/IERC20Metadata.sol";

// All Principal Tokens (PTs) MUST implement EIP-20 to represent ownership of future underlying redemption. If a PT is to be non-transferrable, it MAY revert on calls to transfer or transferFrom. The EIP-20 operations balanceOf, transfer, totalSupply, etc. operate on the Principal Token balance.

// All Principal Tokens MUST implement EIP-20’s optional metadata extensions. The name and symbol functions SHOULD reflect the underlying token’s name and symbol in some way, as well as the origination protocol, and in the case of yield tokenization protocols, the origination money-market.

abstract contract ERC5095Checker is Test {
    uint internal _delta_;

    address internal _underlying_; // The address of the underlying token used by the Principal Token for accounting, and redeeming. MUST be an EIP-20 token contract.
    address internal _pt_; // The principal token address

    event Redeem(address indexed from, address indexed to, uint256 amount);

    // underlying
    // The address of the underlying token used by the Principal Token for accounting, and redeeming.
    // "MUST NOT revert."
    function check_underlying_5095(address caller) public {
        vm.prank(caller);
        IERC5095(_pt_).underlying();
    }

    // maturity
    // The unix timestamp (uint256) at or after which Principal Tokens can be redeemed for their underlying deposit.
    // "MUST NOT revert."
    function check_maturity_5095(address caller) public returns (uint256) {
        vm.prank(caller);
        uint256 timestamp = IERC5095(_pt_).maturity();
        return timestamp;
    }

    // //
    // // convert
    // //

    // convertToPrincipal
    // "MUST NOT show any variations depending on the caller."
    function check_convertToPrincipal_5095(
        address caller1,
        address caller2,
        uint256 assets
    ) public {
        vm.prank(caller1);
        uint res1 = IERC5095(_pt_).convertToPrincipal(assets); // "MAY revert due to integer overflow caused by an unreasonably large input."
        vm.prank(caller2);
        uint res2 = IERC5095(_pt_).convertToPrincipal(assets); // "MAY revert due to integer overflow caused by an unreasonably large input."
        assertEq(res1, res2);
    }

    // // convertToAssets
    // // "MUST NOT show any variations depending on the caller."
    function check_convertToUnderlying_5095(address caller1, address caller2, uint shares) public {
        vm.prank(caller1);
        uint res1 = IERC5095(_pt_).convertToUnderlying(shares); // "MAY revert due to integer overflow caused by an unreasonably large input."
        vm.prank(caller2);
        uint res2 = IERC5095(_pt_).convertToUnderlying(shares); // "MAY revert due to integer overflow caused by an unreasonably large input."
        assertEq(res1, res2);
    }

    // //
    // // withdraw
    // //

    // maxWithdraw
    // "MUST NOT revert."
    // NOTE: some implementations failed due to arithmetic overflow
    function prop_maxWithdraw_5095(address caller, address owner) public returns (uint256) {
        vm.prank(caller);
        return IERC5095(_pt_).maxWithdraw(owner);
    }

    // previewWithdraw
    // "MUST return as close to and no fewer than the exact amount of Vault
    // shares that would be burned in a withdraw call in the same transaction.
    // I.e. withdraw should return the same or fewer shares as previewWithdraw
    // if called in the same transaction."
    function prop_previewWithdraw_5095(
        address caller,
        address receiver,
        address owner,
        address other,
        uint assets
    ) public {
        vm.prank(other);
        uint preview = IERC5095(_pt_).previewWithdraw(assets);
        vm.prank(caller);
        uint actual = IERC5095(_pt_).withdraw(assets, receiver, owner);
        assertApproxLeAbs(actual, preview, _delta_);
    }

    // // withdraw
    function prop_withdraw_5095(
        address caller,
        address receiver,
        address owner,
        uint assets
    ) public {
        uint oldReceiverAsset = IERC20(_underlying_).balanceOf(receiver);
        uint oldOwnerShare = IERC20(_pt_).balanceOf(owner);
        uint oldAllowance = IERC20(_pt_).allowance(owner, caller);

        vm.prank(caller);
        vm.expectEmit(true, true, false, false);
        emit Redeem(owner, receiver, assets);
        uint shares = IERC5095(_pt_).withdraw(assets, receiver, owner);

        uint newReceiverAsset = IERC20(_underlying_).balanceOf(receiver);
        uint newOwnerShare = IERC20(_pt_).balanceOf(owner);
        uint newAllowance = IERC20(_pt_).allowance(owner, caller);

        assertApproxEqAbs(newOwnerShare, oldOwnerShare - shares, _delta_, "share");
        assertApproxEqAbs(newReceiverAsset, oldReceiverAsset + assets, _delta_, "asset"); // NOTE: this may fail if the receiver is a contract in which the asset is stored
        if (caller != owner && oldAllowance != type(uint).max)
            assertApproxEqAbs(newAllowance, oldAllowance - shares, _delta_, "allowance");

        assertTrue(
            caller == owner || oldAllowance != 0 || (shares == 0 && assets == 0),
            "access control"
        );
    }

    // //
    // // redeem
    // //

    // maxRedeem
    // "MUST NOT revert."
    function prop_maxRedeem_5095(address caller, address owner) public returns (uint256) {
        vm.prank(caller);
        return IERC5095(_pt_).maxRedeem(owner);
    }

    // previewRedeem
    // "MUST return as close to and no more than the exact amount of assets that
    // would be withdrawn in a redeem call in the same transaction. I.e. redeem
    // should return the same or more assets as previewRedeem if called in the
    // same transaction."
    function prop_previewRedeem_5095(
        address caller,
        address receiver,
        address owner,
        address other,
        uint shares
    ) public {
        vm.prank(other);
        uint preview = IERC5095(_pt_).previewRedeem(shares);
        vm.prank(caller);
        uint actual = IERC5095(_pt_).redeem(shares, receiver, owner);
        assertApproxGeAbs(actual, preview, _delta_);
    }

    // redeem
    function prop_redeem_5095(address caller, address receiver, address owner, uint shares) public {
        uint oldReceiverAsset = IERC20(_underlying_).balanceOf(receiver);
        uint oldOwnerShare = IERC20(_pt_).balanceOf(owner);
        uint oldAllowance = IERC20(_pt_).allowance(owner, caller);

        vm.prank(caller);
        vm.expectEmit(true, true, false, true);
        emit Redeem(owner, receiver, shares);
        uint assets = IERC5095(_pt_).redeem(shares, receiver, owner);

        uint newReceiverAsset = IERC20(_underlying_).balanceOf(receiver);
        uint newOwnerShare = IERC20(_pt_).balanceOf(owner);
        uint newAllowance = IERC20(_pt_).allowance(owner, caller);

        assertApproxEqAbs(newOwnerShare, oldOwnerShare - shares, _delta_, "share");
        assertApproxEqAbs(newReceiverAsset, oldReceiverAsset + assets, _delta_, "asset"); // NOTE: this may fail if the receiver is a contract in which the asset is stored
        if (caller != owner && oldAllowance != type(uint).max)
            assertApproxEqAbs(newAllowance, oldAllowance - shares, _delta_, "allowance");

        assertTrue(
            caller == owner || oldAllowance != 0 || (shares == 0 && assets == 0),
            "access control"
        );
    }

    // utils

    function assertApproxGeAbs(uint a, uint b, uint maxDelta) internal virtual {
        if (!(a >= b)) {
            uint dt = b - a;
            if (dt > maxDelta) {
                emit log("Error: a >=~ b not satisfied [uint]");
                emit log_named_uint("   Value a", a);
                emit log_named_uint("   Value b", b);
                emit log_named_uint(" Max Delta", maxDelta);
                emit log_named_uint("     Delta", dt);
                fail();
            }
        }
    }

    function assertApproxLeAbs(uint a, uint b, uint maxDelta) internal virtual {
        if (!(a <= b)) {
            uint dt = a - b;
            if (dt > maxDelta) {
                emit log("Error: a <=~ b not satisfied [uint]");
                emit log_named_uint("   Value a", a);
                emit log_named_uint("   Value b", b);
                emit log_named_uint(" Max Delta", maxDelta);
                emit log_named_uint("     Delta", dt);
                fail();
            }
        }
    }
}

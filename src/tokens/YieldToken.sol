// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-math/Math.sol";
import "openzeppelin-erc20-extensions/ERC20PermitUpgradeable.sol";
import "openzeppelin-erc20-basic/extensions/IERC20Metadata.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IYieldToken.sol";

/**
 * @title Yield Token contract
 * @notice A YieldToken (YT) is a Spectra token that keeps track of users' yield ownership. It is minted at same times and amounts as a PT.
 */
contract YieldToken is IYieldToken, ERC20PermitUpgradeable {
    using Math for uint256;

    address private pt;

    // constructor
    constructor() {
        _disableInitializers(); // using this so that the deployed logic contract later cannot be initialized.
    }

    /**
     * @notice Initializer of the contract.
     * @param _name The name of the yt token.
     * @param _symbol The symbol of the yt token.
     * @param _pt The address of the pt associated with this yt token.
     */
    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _pt
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        pt = _pt;
    }

    /** @dev See {IYieldToken-burnWithoutUpdate} */
    function burnWithoutUpdate(address from, uint256 amount) external override {
        if (msg.sender != pt) {
            revert CallerIsNotPtContract();
        }
        _burn(from, amount);
    }

    /** @dev See {IYieldToken-mint} */
    function mint(address to, uint256 amount) external override {
        if (msg.sender != pt) {
            revert CallerIsNotPtContract();
        }
        _mint(to, amount);
    }

    /** @dev See {IYieldToken-burn} */
    function burn(uint256 amount) public override {
        IPrincipalToken(pt).updateYield(msg.sender);
        _burn(msg.sender, amount);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(
        address to,
        uint256 amount
    ) public virtual override(IYieldToken, ERC20Upgradeable) returns (bool success) {
        IPrincipalToken(pt).beforeYtTransfer(msg.sender, to);
        return super.transfer(to, amount);
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(IYieldToken, ERC20Upgradeable) returns (bool success) {
        IPrincipalToken(pt).beforeYtTransfer(from, to);
        return super.transferFrom(from, to, amount);
    }

    /** @dev See {IERC20Upgradeable-decimals} */
    function decimals()
        public
        view
        virtual
        override(IYieldToken, ERC20Upgradeable)
        returns (uint8)
    {
        return IERC20Metadata(pt).decimals();
    }

    /** @dev See {IYieldToken-getPT} */
    function getPT() public view virtual override returns (address) {
        return pt;
    }

    /** @dev See {IYieldToken-balanceOf} */
    function balanceOf(
        address account
    ) public view override(IYieldToken, ERC20Upgradeable) returns (uint256) {
        return (block.timestamp < IPrincipalToken(pt).maturity()) ? super.balanceOf(account) : 0;
    }

    /** @dev See {IYieldToken-actualBalanceOf} */
    function actualBalanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }
}

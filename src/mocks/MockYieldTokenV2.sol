// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-math/Math.sol";
import "openzeppelin-erc20-extensions/ERC20PermitUpgradeable.sol";
import "openzeppelin-erc20-basic/extensions/IERC20Metadata.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IYieldToken.sol";

/**
 * @dev This contract is used to test upgradeability of YieldToken.sol.
 * Only differences with YieldToken.sol are the additions of the getPT2,
 * getTestUpgradeability and setTestUpgradeability methods.
 */
contract MockYieldTokenV2 is IYieldToken, ERC20PermitUpgradeable {
    using Math for uint256;

    /** @notice PT associated with this yt */
    address private pt;

    uint256 private testUpgradeability;

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

    /** @dev See {IYieldToken-burnWithoutYieldUpdate} */
    function burnWithoutYieldUpdate(
        address owner,
        address caller,
        uint256 amount
    ) external override {
        if (msg.sender != pt) {
            revert UnauthorizedCaller();
        }
        if (owner != caller) {
            _spendAllowance(owner, caller, amount);
        }
        _burn(owner, amount);
    }

    /** @dev See {IYieldToken-mint} */
    function mint(address to, uint256 amount) external override {
        if (msg.sender != pt) {
            revert UnauthorizedCaller();
        }
        _mint(to, amount);
    }

    /** @dev See {IYieldToken-burn} */
    function burn(uint256 amount) public override {
        if (block.timestamp >= IPrincipalToken(pt).maturity() && amount != 0) {
            revert ERC20InsufficientBalance(msg.sender, 0, amount);
        }
        IPrincipalToken(pt).updateYield(msg.sender);
        _burn(msg.sender, amount);
    }

    /** @dev See {IYieldToken-transfer}. */
    function transfer(
        address to,
        uint256 amount
    ) public virtual override(IYieldToken, ERC20Upgradeable) returns (bool) {
        if (block.timestamp >= IPrincipalToken(pt).maturity() && amount != 0) {
            revert ERC20InsufficientBalance(msg.sender, 0, amount);
        }
        IPrincipalToken(pt).beforeYtTransfer(msg.sender, to);
        return super.transfer(to, amount);
    }

    /** @dev See {IYieldToken-transferFrom}. */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(IYieldToken, ERC20Upgradeable) returns (bool) {
        if (block.timestamp >= IPrincipalToken(pt).maturity() && amount != 0) {
            revert ERC20InsufficientBalance(from, 0, amount);
        }
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

    /** @dev Used for upgradeability testing */
    function getPT2() public view virtual returns (address) {
        return address(0);
    }

    /** @dev Used for upgradeability testing */
    function setTestUpgradeability(uint256 _testUpgradeability) public {
        testUpgradeability = _testUpgradeability;
    }

    /** @dev Used for upgradeability testing */
    function getTestUpgradeability() public view virtual returns (uint256) {
        return testUpgradeability;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override(IYieldToken, ERC20Upgradeable) returns (uint256) {
        return (block.timestamp < IPrincipalToken(pt).maturity()) ? super.totalSupply() : 0;
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

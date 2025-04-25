// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "openzeppelin-erc20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract MockUnderlying is ERC20Upgradeable, Ownable2StepUpgradeable {
    error MockUnderlyingUnauthorizedCall();

    /**
     * @notice Initializer of the contract.
     * @param _name The name of the mock token.
     * @param _symbol The symbol of the mock token.
     */
    function initialize(string memory _name, string memory _symbol) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init(_msgSender());
    }

    /**
     * @notice Function for admin to directly call _mint of ERC20Upgradeable for minting "amount" number of mock underlying tokens.
     * See {ERC20Upgradeable- _mint}.
     */
    function mint(address receiver, uint256 amount) public {
        _checkOwner();
        _mint(receiver, amount);
    }

    /**
     * @notice Function for admin to directly call _burn of ERC20Upgradeable for burning "amount" number of mock underlying tokens.
     * See {ERC20Upgradeable- _burn}.
     */
    function burn(address receiver, uint256 amount) public {
        if (msg.sender != receiver) {
            revert MockUnderlyingUnauthorizedCall();
        }
        _burn(receiver, amount);
    }
}

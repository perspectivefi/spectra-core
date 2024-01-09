// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import "openzeppelin-erc20/ERC20Upgradeable.sol";

contract MockERC20 is ERC20Upgradeable {
    /**
     * @notice Initializer of the contract.
     * @param _name The name of the mock token.
     * @param _symbol The symbol of the mock token.
     */
    function initialize(string memory _name, string memory _symbol) public initializer {
        __ERC20_init(_name, _symbol);
        _mint(msg.sender, 1_000_000_000e18);
    }

    /**
    * @notice Function to directly call _mint of ERC20Upgradeable for minting "amount" number of mock tokens.
      See {ERC20Upgradeable-_mint}.
     */
    function mint(address receiver, uint256 amount) public {
        _mint(receiver, amount);
    }

    /**
    * @notice Function to directly call _burn of ERC20Upgradeable for burning "amount" number of mock tokens.
      See {ERC20Upgradeable-_burn}.
     */
    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {IRewardsProxy} from "../interfaces/IRewardsProxy.sol";
import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "forge-std/console.sol";

/**
 * The MockIncentivesContract simulates the behavior of a basic Incentives Contract that distributes rewards to users
 * based on their balance of the incentivized token (IBT in the context of the tests).
 * This contract is utilized to test the Principal Token contract's capability to claim rewards from the Incentives Contract via a Rewards Proxy.
 */
contract MockIncentivesContract is Ownable {
    address public rewardToken;
    address public incentivizedToken;
    uint256 public totalClaimable;
    event Claimed(address indexed account, uint256 amount);
    event RewardsDistributed(uint256 amount);

    constructor(address _incentivizedToken) Ownable(msg.sender) {
        rewardToken = address(new MockERC20());
        MockERC20(rewardToken).initialize("MOCK REWARDS TOKEN", "RTKN");
        incentivizedToken = _incentivizedToken;
    }

    /**
     * @notice Add claimable rewards to the contract
     * @notice This function is only used for testing purposes representing reward accumalation over time
     * @param _claimable The amount of rewards to add
     * @dev Only callable by the owner of the contract
     */
    function testAddClaimable(uint256 _claimable) external onlyOwner {
        totalClaimable += _claimable;
        emit RewardsDistributed(_claimable);
    }

    /**
     * @notice Get the amount of rewards claimable by a user
     * @param user The user to check
     * @return claimable The amount of rewards claimable by the user
     */
    function claimableByUser(address user) external view returns (uint256 claimable) {
        uint256 balance = MockERC20(incentivizedToken).balanceOf(user);
        if (balance == 0) {
            return 0;
        }
        uint256 totalSupply = MockERC20(incentivizedToken).totalSupply();
        claimable = (totalClaimable * balance) / totalSupply;
        return claimable;
    }

    /**
     * @notice Claim rewards from the contract
     * @param amountToClaim The amount of rewards to claim
     * @dev Only callable by users with a balance of the incentivized token
     */
    function claim(uint256 amountToClaim) external {
        uint256 balance = MockERC20(incentivizedToken).balanceOf(msg.sender);
        if (balance == 0) {
            return;
        }
        uint256 totalSupply = MockERC20(incentivizedToken).totalSupply();
        uint256 claimable = (totalClaimable * balance) / totalSupply;
        require(amountToClaim <= claimable, "Not enough claimable");
        totalClaimable -= amountToClaim;
        MockERC20(rewardToken).mint(msg.sender, amountToClaim);
        emit Claimed(msg.sender, amountToClaim);
    }
}

/**
 * Example of a reward proxy contract that can be used to claim incentives rewards from a rewards contract.
 * The claimRewards function is meant to be called by the principal token contract and hold the logic for claiming the rewards
 * @notice This mock implementation is meant to be used for testing purposes only.
 */
contract MockRewardsProxy is IRewardsProxy {
    /** @dev See {IRewardsProxy-claim}. */
    function claimRewards(bytes memory data) external override {
        (
            address rewardsContract,
            uint256 amountToClaim,
            address rewardsReceiver,
            address tokenAddress
        ) = abi.decode(data, (address, uint256, address, address));
        (bool success, ) = rewardsContract.call(
            abi.encodeWithSignature("claim(uint256)", amountToClaim)
        );
        require(success, "Claim rewards failed");
        IERC20(tokenAddress).transfer(rewardsReceiver, amountToClaim);
    }
}

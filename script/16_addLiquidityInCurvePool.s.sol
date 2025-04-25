// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/interfaces/IERC4626.sol";
import "../src/interfaces/ICurvePool.sol";
import "../src/interfaces/IPrincipalToken.sol";
import "src/mocks/MockUnderlying.sol";

contract AddLiquidityInCurvePoolScript is Script {
    function run() public {
        vm.startBroadcast();
        string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("Deployment network is not set in .env file");
        }

        if (bytes(vm.envString(string.concat("CURVE_POOL_ADDR_", deploymentNetwork))).length == 0) {
            revert("Curve Pool address is not set in .env file");
        }
        address pool = vm.envAddress(string.concat("CURVE_POOL_ADDR_", deploymentNetwork));

        if (
            bytes(vm.envString(string.concat("DEPLOYER_ADDRESS_", deploymentNetwork))).length == 0
        ) {
            revert("Deployer address is not set in .env file");
        }
        address deployer = vm.envAddress(string.concat("DEPLOYER_ADDRESS_", deploymentNetwork));

        if (bytes(vm.envString(string.concat("ASSET_ADDR_", deploymentNetwork))).length == 0) {
            revert("Asset address is not set in .env file");
        }
        address asset = vm.envAddress(string.concat("ASSET_ADDR_", deploymentNetwork));

        if (bytes(vm.envString(string.concat("IBT_ADDR_", deploymentNetwork))).length == 0) {
            revert("IBT address is not set in .env file");
        }
        address ibt = vm.envAddress(string.concat("IBT_ADDR_", deploymentNetwork));

        if (
            bytes(vm.envString(string.concat("PT_BEACON_PROXY_ADDR_", deploymentNetwork))).length ==
            0
        ) {
            revert("PT_BEACON_PROXY_ADDR_ is not set in .env file");
        }

        address pt = vm.envAddress(string.concat("PT_BEACON_PROXY_ADDR_", deploymentNetwork));

        uint256 ibtAmount = vm.envUint(
            string.concat("IBT_AMOUNT_ADD_LIQUIDITY_", deploymentNetwork)
        );

        uint256 ptAmount = vm.envUint(string.concat("PT_AMOUNT_ADD_LIQUIDITY_", deploymentNetwork));

        // minting assets to deployer
        MockUnderlying assetInstance = MockUnderlying(asset);
        assetInstance.mint(deployer, 1000000e18);

        // deposit in ibt
        IERC20(asset).approve(ibt, ibtAmount);
        IERC4626(ibt).deposit(ibtAmount, deployer);

        // deposit in pt
        IERC20(asset).approve(pt, 2 * ptAmount);
        IPrincipalToken(pt).deposit(2 * ptAmount, deployer);

        IERC20(ibt).approve(pool, ibtAmount);
        IERC20(pt).approve(pool, ptAmount);

        ICurvePool(pool).add_liquidity([ibtAmount, ptAmount], 0);

        vm.stopBroadcast();
    }
}

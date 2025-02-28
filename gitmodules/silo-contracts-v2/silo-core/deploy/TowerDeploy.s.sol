// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";

import {Tower} from "silo-core/contracts/utils/Tower.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";

/**
    FOUNDRY_PROFILE=core \
    forge script silo-core/deploy/TowerDeploy.s.sol:TowerDeploy \
    --ffi --broadcast --rpc-url $RPC_ARBITRUM \
    --verify

    in case verification fail, set `ETHERSCAN_API_KEY` in env and run:
    FOUNDRY_PROFILE=core forge verify-contract \
    0x22fBF354f7E8A99673559352c63Ae022E58460dd silo-core/contracts/utils/Tower.sol:Tower \
    --chain 42161 --watch
 */
contract TowerDeploy is CommonDeploy {
    function run() public returns (Tower tower) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        string memory chainAlias = ChainsLib.chainAlias();

        address siloFactory = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, chainAlias);
        address liquidationHelper = SiloCoreDeployments.get(SiloCoreContracts.LIQUIDATION_HELPER, chainAlias);
        address siloLens = SiloCoreDeployments.get(SiloCoreContracts.SILO_LENS, chainAlias);

        vm.startBroadcast(deployerPrivateKey);

        tower = new Tower();
        tower.register("SiloFactory", siloFactory);
        tower.register("LiquidationHelper", liquidationHelper);
        tower.register("SiloLens", siloLens);

        vm.stopBroadcast();

        _registerDeployment(address(tower), SiloCoreContracts.TOWER);
    }
}

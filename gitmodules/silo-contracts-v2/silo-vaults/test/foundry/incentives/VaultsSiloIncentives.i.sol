// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {SiloIncentivesController} from "silo-core/contracts/incentives/SiloIncentivesController.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";
import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";

import {INotificationReceiver} from "../../../contracts/interfaces/INotificationReceiver.sol";
import {IVaultIncentivesModule} from "../../../contracts/interfaces/IVaultIncentivesModule.sol";
import {IntegrationTest} from "../helpers/IntegrationTest.sol";
import {CAP} from "../helpers/BaseTest.sol";


/*
 FOUNDRY_PROFILE=vaults-tests forge test --ffi --mc VaultsSiloIncentivesTest -vvv
*/
contract VaultsSiloIncentivesTest is IntegrationTest {
    MintableToken reward1 = new MintableToken(18);

    SiloIncentivesController vaultIncentivesController;

    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP);
        _setCap(allMarkets[1], CAP);
        _setCap(allMarkets[2], CAP);

        reward1.setOnDemand(true);

        // TODO add test when notifier will be wrong and expect no rewards (or revert?)
        vaultIncentivesController = new SiloIncentivesController(address(this), address(vault));
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt test_vaults_incentives_deposit_noRewardsSetup -vv
    */
    function test_vaults_incentives_deposit_noRewardsSetup() public {
        assertTrue(address(vault.INCENTIVES_MODULE()) != address(0), "INCENTIVES_MODULE");

        vm.expectCall(
            address(vault.INCENTIVES_MODULE()),
            abi.encodeWithSelector(IVaultIncentivesModule.getAllIncentivesClaimingLogics.selector)
        );

        vm.expectCall(
            address(vault.INCENTIVES_MODULE()),
            abi.encodeWithSelector(IVaultIncentivesModule.getNotificationReceivers.selector)
        );

        // does not revert without incentives setup
        vault.deposit(1, address(this));

        // does not revert without incentives setup
        vault.claimRewards();
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt test_vaults_incentives_standardRewards -vv
    */
    function test_vaults_incentives_standardRewards() public {
        address user = makeAddr("user");

        uint256 rewardsPerSec = 3;
        uint256 depositAmount = 1;

        // standard program for vault users
        vaultIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "x",
            rewardToken: address(reward1),
            emissionPerSecond: uint104(rewardsPerSec),
            distributionEnd: uint40(block.timestamp + 10)
        }));

        vm.prank(OWNER);
        vaultIncentivesModule.addNotificationReceiver(INotificationReceiver(address(vaultIncentivesController)));

        // this call is expected on depositing
        vm.expectCall(
            address(vaultIncentivesController),
            abi.encodeWithSelector(
                INotificationReceiver.afterTokenTransfer.selector,
                address(0),
                0,
                user,
                depositAmount,
                depositAmount,
                depositAmount
            )
        );

        // does not revert without incentives setup
        vm.prank(user);
        vault.deposit(depositAmount, user);

        vm.warp(block.timestamp + 1);

        assertEq(vaultIncentivesController.getRewardsBalance(user, "x"), rewardsPerSec, "expected reward after 1s");

        vm.prank(user);
        vaultIncentivesController.claimRewards(user);

        assertEq(reward1.balanceOf(user), rewardsPerSec, "user can claim standard reward");
    }
}

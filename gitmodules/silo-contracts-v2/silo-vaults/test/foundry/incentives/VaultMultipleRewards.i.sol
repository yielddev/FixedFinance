// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {Hook} from "silo-core/contracts/lib/Hook.sol";

import {SiloIncentivesControllerGaugeLike} from "silo-core/contracts/incentives/SiloIncentivesControllerGaugeLike.sol";
import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";
import {SiloIncentivesController} from "silo-core/contracts/incentives/SiloIncentivesController.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IGaugeLike} from "silo-core/contracts/interfaces/IGaugeLike.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {SiloIncentivesControllerCL} from "../../../contracts/incentives/claiming-logics/SiloIncentivesControllerCL.sol";

import {INotificationReceiver} from "../../../contracts/interfaces/INotificationReceiver.sol";
import {IntegrationTest} from "../helpers/IntegrationTest.sol";

import {CAP} from "../helpers/BaseTest.sol";

/*
 FOUNDRY_PROFILE=vaults-tests forge test --ffi --mc VaultMultipleRewardsTest -vvv
*/
contract VaultMultipleRewardsTest is IntegrationTest {
    ISiloConfig siloConfig;

    MintableToken reward1 = new MintableToken(18);
    MintableToken reward2 = new MintableToken(18);

    SiloIncentivesControllerGaugeLike siloIncentivesController;
    SiloIncentivesController vaultIncentivesController;

    address siloWithIncentives;

    function setUp() public virtual override {
        super.setUp();

        _setCap(allMarkets[0], _cap());
        _setCap(allMarkets[1], _cap());
        _setCap(allMarkets[2], _cap());

        reward1.setOnDemand(true);
        reward2.setOnDemand(true);

        siloWithIncentives = _overrideTestAddresses();

        vaultIncentivesController = new SiloIncentivesController(address(this), address(vault));
        vm.label(address(vaultIncentivesController), "VaultIncentivesController");

        // SiloIncentivesController is per silo
        siloIncentivesController = new SiloIncentivesControllerGaugeLike(
            address(this), address(partialLiquidation), siloWithIncentives
        );

        // set SiloIncentivesController as gauge for hook
        vm.prank(Ownable(address(partialLiquidation)).owner());
        IGaugeHookReceiver(address(partialLiquidation)).setGauge(
            IGaugeLike(address(siloIncentivesController)), IShareToken(siloWithIncentives)
        );

        _sortSupplyQueueIdleLast();

        // hook is autoconfigured on setGauge
        (, uint24 hooksAfter) = IGaugeHookReceiver(address(partialLiquidation)).hookReceiverConfig(siloWithIncentives);
        assertEq(hooksAfter, Hook.COLLATERAL_TOKEN | Hook.SHARE_TOKEN_TRANSFER, "hook after");

        _setupIncentivesContracts();
    }

    function _overrideTestAddresses() internal returns (address incentiviseSilo) {
        incentiviseSilo = address(allMarkets[2]);
        silo1 = ISilo(incentiviseSilo);
        silo0 = ISilo(address(collateralMarkets[IERC4626(incentiviseSilo)]));

        siloConfig = ISilo(incentiviseSilo).config();
        ISiloConfig.ConfigData memory cfg = siloConfig.getConfig(incentiviseSilo);
        partialLiquidation = IPartialLiquidation(cfg.hookReceiver);
    }

    function _setupIncentivesContracts() internal {
        vm.prank(OWNER);
        vaultIncentivesModule.addNotificationReceiver(INotificationReceiver(address(vaultIncentivesController)));

        SiloIncentivesControllerCL cl = new SiloIncentivesControllerCL(
            address(vaultIncentivesController), address(siloIncentivesController)
        );

        vm.prank(OWNER);
        vaultIncentivesModule.addIncentivesClaimingLogic(siloWithIncentives, cl);
    }

    function _cap() internal view virtual returns (uint256) {
        return 1e18;
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt test_vaults_noRewardsWhenVaultWasNotAbleToDepositToIncentiviseSilo -vv
    */
    function test_vaults_noRewardsWhenVaultWasNotAbleToDepositToIncentiviseSilo() public {
        uint256 rewardsPerSec = 1e18;

        uint256 depositAmount = 2e18;
        uint256 shares = depositAmount * SiloMathLib._DECIMALS_OFFSET_POW;
        uint256 sharesCapped = depositAmount > _cap() ? _cap() * SiloMathLib._DECIMALS_OFFSET_POW : shares;

        vm.prank(address(1));
        vault.deposit(depositAmount, address(1));

        assertEq(allMarkets[0].totalSupply(), sharesCapped, "silo#0 got deposit");
        assertEq(allMarkets[1].totalSupply(), sharesCapped, "silo#1 got deposit");
        assertEq(IShareToken(siloWithIncentives).totalSupply(), 0, "deposit did not reached silo");

        // standard program for silo users
        siloIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "x",
            rewardToken: address(reward1),
            emissionPerSecond: uint104(rewardsPerSec),
            distributionEnd: uint40(block.timestamp + 10)
        }));

        vm.warp(block.timestamp + 1);
        string memory programName = Strings.toHexString(address(reward1));

        assertEq(
            siloIncentivesController.getRewardsBalance(address(vault), "x"),
            0,
            "expected NO rewards for silo, because siloWithIncentives did not get any deposit"
        );

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "expected ZERO rewards, because no incentives were generated"
        );

        // do another deposit, this one will go to silo with incentives

        vault.deposit(1e18, address(this));

        assertEq(IShareToken(siloWithIncentives).totalSupply(), sharesCapped, "siloWithIncentives got deposit");

        assertEq(
            siloIncentivesController.getRewardsBalance(address(vault), "x"),
            0,
            "expected NO silo rewards yet, because time did not pass"
        );

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "expected ZERO vault rewards"
        );

        vm.warp(block.timestamp + 1);

        assertEq(
            siloIncentivesController.getRewardsBalance(address(vault), "x"),
            rewardsPerSec,
            "expected rewards for silo after 1s"
        );

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            0,
            "expected NO rewards, because they are not claimed yet"
        );

        vault.claimRewards();

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName),
            rewardsPerSec / 3,
            "expected rewards, because they are claimed"
        );

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(1), programName),
            rewardsPerSec * 2 / 3,
            "expected rewards for other depositor"
        );
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt test_vaults_claimFromMultiplePrograms -vv
    */
    function test_vaults_claimFromMultiplePrograms() public {
        uint256 rewardsPerSec = 12345678e8;
        uint256 depositAmount = _cap() * 30; // must be enough to get to incentivise silo as #2

        vault.deposit(depositAmount, address(this));

        siloIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "program1",
            rewardToken: address(reward1),
            emissionPerSecond: uint104(rewardsPerSec),
            distributionEnd: uint40(block.timestamp + 3)
        }));

        siloIncentivesController.createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput({
            name: "program2",
            rewardToken: address(reward2),
            emissionPerSecond: uint104(rewardsPerSec),
            distributionEnd: uint40(block.timestamp + 3)
        }));

        vm.warp(block.timestamp + 1);

        assertEq(
            siloIncentivesController.getRewardsBalance(address(vault), "program1"),
            rewardsPerSec,
            "[program1] expected rewards for silo after 1s"
        );

        assertEq(
            siloIncentivesController.getRewardsBalance(address(vault), "program2"),
            rewardsPerSec,
            "[program2] expected rewards for silo after 1s"
        );

        vault.claimRewards();

        string memory programName1 = Strings.toHexString(address(reward1));
        string memory programName2 = Strings.toHexString(address(reward2));

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName1),
            rewardsPerSec,
            "expected rewards1"
        );

        assertEq(
            vaultIncentivesController.getRewardsBalance(address(this), programName2),
            rewardsPerSec,
            "expected rewards2"
        );

        vaultIncentivesController.claimRewards(address(this));

        assertEq(reward1.balanceOf(address(this)), rewardsPerSec, "rewards1 transferred");
        assertEq(reward2.balanceOf(address(this)), rewardsPerSec, "rewards2 transferred");
    }
}

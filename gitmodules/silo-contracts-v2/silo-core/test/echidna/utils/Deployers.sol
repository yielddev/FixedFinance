// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Utilities
import {VyperDeployer} from "./VyperDeployer.sol";
import {Data} from "../data/Data.sol";

// External dependencies
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {TimelockController} from "openzeppelin5/governance/TimelockController.sol";
import {IVotingEscrow} from "balancer-labs/v2-interfaces/liquidity-mining/IVotingEscrow.sol";

// ve-silo dependencies
import {ISiloTimelockController} from "ve-silo/contracts/governance/interfaces/ISiloTimelockController.sol";

// silo-core dependencies
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {ISiloDeployer, SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {PartialLiquidation} from "silo-core/contracts/utils/hook-receivers/liquidation/PartialLiquidation.sol";
import {SiloHookV1} from "silo-core/contracts/utils/hook-receivers/SiloHookV1.sol";
import {SiloInternal} from "../internal_testing/SiloInternal.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {IInterestRateModelV2Factory, InterestRateModelV2Factory} from "silo-core/contracts/interestRateModel/InterestRateModelV2Factory.sol";
import {IInterestRateModelV2, InterestRateModelV2} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {IInterestRateModelV2Config, InterestRateModelV2Config} from "silo-core/contracts/interestRateModel/InterestRateModelV2Config.sol";
import {IGaugeHookReceiver, GaugeHookReceiver} from "silo-core/contracts/utils/hook-receivers/gauge/GaugeHookReceiver.sol";
import {ISiloConfig, SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {CloneDeterministic} from "silo-core/contracts/lib/CloneDeterministic.sol";
import {Views} from "silo-core/contracts/lib/Views.sol";

contract Deployers is VyperDeployer, Data {
    address timelockAdmin = address(0xb4b3);

    /* ================================================================
                            State
       ================================================================ */

    // silo-core
    ISiloFactory siloFactory;
    IInterestRateModelV2Factory interestRateModelV2ConfigFactory;
    IInterestRateModelV2 interestRateModelV2;
    IGaugeHookReceiver hookReceiver;
    ISiloDeployer siloDeployer;
    PartialLiquidation liquidationModule;

    // ve-silo
    ISiloTimelockController timelockController;
    //IVeSilo votingEscrow;
    //IFeeDistributor feeDistributor;
    address SILO80_WETH20_TOKEN = 0x9CC64EE4CB672Bc04C54B00a37E1Ed75b2Cc19Dd;
    address SILO_TOKEN = 0x6f80310CA7F2C654691D1383149Fa1A57d8AB1f8;

    constructor() {}

    /* ================================================================
                            data setup
       ================================================================ */
    /// @notice used to set up addresses that can be used as oracles/receivers
    function _setupBasicData() internal {
        // set oracles
        oracles["DIA"] = address(0);
        oracles["CHAINLINK"] = address(0);
        oracles["UniV3-ETH-USDC-0.3"] = address(0);

        // hook receivers
        hookReceivers["GaugeHookReceiver"] = address(0);
    }

    function _initData(address mock0, address mock1) internal {
        // The FULL data relies on addresses set in _setupBasicData()
        siloData["FULL"] = ISiloConfig.InitData({
            deployer: timelockAdmin,
            daoFee: 0.15e18,
            deployerFee: 0.1000e18,
            token0: _tokens["WETH"],
            solvencyOracle0: oracles["DIA"],
            maxLtvOracle0: oracles["CHAINLINK"],
            interestRateModel0: address(interestRateModelV2),
            maxLtv0: 0.7500e18,
            lt0: 0.8500e18,
            liquidationTargetLtv0: 0.8500e18 * 0.9e19 / 1e18,
            liquidationFee0: 0.0500e18,
            flashloanFee0: 0.0100e18,
            callBeforeQuote0: true,
            hookReceiver: address(liquidationModule),
            token1: _tokens["USDC"],
            solvencyOracle1: oracles["UniV3-ETH-USDC-0.3"],
            maxLtvOracle1: oracles[""],
            interestRateModel1: address(interestRateModelV2),
            maxLtv1: 0.8500e18,
            lt1: 0.9500e18,
            liquidationTargetLtv1: 0.9500e18 * 0.9e18 / 1e18,
            liquidationFee1: 0.0250e18,
            flashloanFee1: 0.0100e18,
            callBeforeQuote1: true
        });

        // We set up the mock data, without oracles and receivers
        ISiloConfig.InitData memory mocks = siloData["FULL"];
        mocks.token0 = mock0;
        mocks.token1 = mock1;
        mocks.solvencyOracle0 = address(0);
        mocks.solvencyOracle1 = address(0);
        mocks.maxLtvOracle0 = address(0);
        mocks.callBeforeQuote0 = false;
        mocks.callBeforeQuote1 = false;
        mocks.hookReceiver = address(0);

        siloData["MOCK"] = mocks;
    }

    /* ================================================================
                            ve-silo deployments
       ================================================================ */
    function ve_setUp(uint256 feeDistributorStartTime) internal {
        ve_deployTimelockController();

        // note: The below deployments are not required to test most of the system,
        // but could be beneficial to set up in the future. The implementations are commented out due to
        // Echidna throwing an error on deploying the VotingEscrow.vy contract.

        ve_deployVotingEscrow();
        ve_deployFeeDistributor(feeDistributorStartTime);
    }

    function ve_deployTimelockController() internal {
        uint256 minDelay = 1;
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        timelockController = ISiloTimelockController(
            address(
                new TimelockController(
                    minDelay,
                    proposers,
                    executors,
                    timelockAdmin
                )
            )
        );
    }

    // Vyper deployment causes Echidna to throw an error, hence this is commented out for now
    function ve_deployFeeDistributor(uint256 startTime) internal {
        /* feeDistributor = IFeeDistributor(
            address(
                new FeeDistributor(
                    IVotingEscrow(address(votingEscrow)),
                    startTime
                )
            )
        ); */
    }

    function ve_deployVotingEscrow() internal {
        /* address votingEscrowAddr = deployVotingEscrow(
            abi.encode(
                SILO80_WETH20_TOKEN,
                "Voting Escrow (Silo)",
                "veSILO",
                address(timelockController)
            )
        );

        votingEscrow = IVeSilo(votingEscrowAddr); */
    }

    /* ================================================================
                            silo-core deployments
       ================================================================ */

    function core_setUp(address feeReceiver) internal {
        core_deploySiloLiquidation();
        core_deploySiloFactory(feeReceiver);
        core_deployInterestRateConfigFactory();
        core_deployInterestRateModel();
        core_deployGaugeHookReceiver();
        core_deploySiloDeployer();
    }

    function core_deploySiloFactory(address feeReceiver) internal {
        address daoFeeReceiver = feeReceiver == address(0)
            ? address(0)
            : feeReceiver;

        siloFactory = ISiloFactory(address(new SiloFactory(daoFeeReceiver)));

        address timelock = address(timelockController);
        Ownable(address(siloFactory)).transferOwnership(timelock);
    }

    function core_deployInterestRateConfigFactory() internal {
        interestRateModelV2ConfigFactory = IInterestRateModelV2Factory(
            address(new InterestRateModelV2Factory())
        );
    }

    function core_deployInterestRateModel() internal {
        (, interestRateModelV2) = interestRateModelV2ConfigFactory.create(presetIRMConfigs[0]);
    }

    function core_deployGaugeHookReceiver() internal {
        hookReceiver = IGaugeHookReceiver(address(new SiloHookV1()));
    }

    function core_deploySiloLiquidation() internal {
        liquidationModule = PartialLiquidation(address(new SiloHookV1()));
    }

    function core_deploySiloDeployer() internal {
        address siloImpl = address(new Silo(siloFactory));
        address shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        address shareDebtTokenImpl = address(new ShareDebtToken());

        siloDeployer = ISiloDeployer(address(new SiloDeployer(
            interestRateModelV2ConfigFactory,
            siloFactory,
            siloImpl,
            shareProtectedCollateralTokenImpl,
            shareDebtTokenImpl
        )));
    }

    function _deploySiloConfig(
        ISiloConfig.InitData memory _siloInitData,
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl
    ) internal returns (ISiloConfig siloConfig) {
        uint256 nextSiloId = siloFactory.getNextSiloId();

        ISiloConfig.ConfigData memory configData0;
        ISiloConfig.ConfigData memory configData1;

        (configData0, configData1) = Views.copySiloConfig(
            _siloInitData,
            siloFactory.daoFeeRange(),
            siloFactory.maxDeployerFee(),
            siloFactory.maxFlashloanFee(),
            siloFactory.maxLiquidationFee()
        );

        configData0.silo = CloneDeterministic.predictSilo0Addr(_siloImpl, nextSiloId, address(siloFactory));
        configData1.silo = CloneDeterministic.predictSilo1Addr(_siloImpl, nextSiloId, address(siloFactory));

        configData0.collateralShareToken = configData0.silo;
        configData1.collateralShareToken = configData1.silo;

        configData0.protectedShareToken = CloneDeterministic.predictShareProtectedCollateralToken0Addr(
            _shareProtectedCollateralTokenImpl,
            nextSiloId,
            address(siloFactory)
        );

        configData1.protectedShareToken = CloneDeterministic.predictShareProtectedCollateralToken1Addr(
            _shareProtectedCollateralTokenImpl,
            nextSiloId,
            address(siloFactory)
        );

        configData0.debtShareToken = CloneDeterministic.predictShareDebtToken0Addr(
            _shareDebtTokenImpl,
            nextSiloId,
            address(siloFactory)
        );

        configData1.debtShareToken = CloneDeterministic.predictShareDebtToken1Addr(
            _shareDebtTokenImpl,
            nextSiloId,
            address(siloFactory)
        );

        siloConfig = ISiloConfig(address(new SiloConfig(nextSiloId, configData0, configData1)));
    }
}

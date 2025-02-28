// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Utils
import {Actor} from "./utils/Actor.sol";

// Contracts
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {SiloInternal} from "../echidna/internal_testing/SiloInternal.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {
    IInterestRateModelV2, InterestRateModelV2
} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {
    IGaugeHookReceiver,
    GaugeHookReceiver
} from "silo-core/contracts/utils/hook-receivers/gauge/GaugeHookReceiver.sol";
import {PartialLiquidation} from "silo-core/contracts/utils/hook-receivers/liquidation/PartialLiquidation.sol";
import {SiloHookV1} from "silo-core/contracts/utils/hook-receivers/SiloHookV1.sol";
import {ISiloDeployer, SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {CloneDeterministic} from "silo-core/contracts/lib/CloneDeterministic.sol";
import {Views} from "silo-core/contracts/lib/Views.sol";

// Test Contracts
import {BaseTest} from "./base/BaseTest.t.sol";
import {MockFlashLoanReceiver} from "./helpers/FlashLoanReceiver.sol";

// Mock Contracts
import {TestERC20} from "./utils/mocks/TestERC20.sol";
import {MockSiloOracle} from "./utils/mocks/MockSiloOracle.sol";

// Interfaces
import {ISiloConfig, SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {
    IInterestRateModelV2Factory,
    InterestRateModelV2Factory
} from "silo-core/contracts/interestRateModel/InterestRateModelV2Factory.sol";
import {
    IInterestRateModelV2Config,
    InterestRateModelV2Config
} from "silo-core/contracts/interestRateModel/InterestRateModelV2Config.sol";
import {ISilo} from "silo-core/contracts/Silo.sol";

import "forge-std/console.sol";

/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract Setup is BaseTest {
    function _setUp() internal {
        // Deploy protocol contracts and protocol actors
        _deployProtocolCore();
    }

    /// @notice Deploy protocol core contracts
    function _deployProtocolCore() internal {
        // Deploy protocol core contracts
        core_setUp(address(this));

        // Deploy assets
        _deployAssets();
        // Deploy Oracles
        _deployOracles();

        // Create silos
        _initData(address(_asset0), address(_asset1));

        address siloImpl = address(new Silo(siloFactory));
        address siloImplInternal = address(new SiloInternal(siloFactoryInternal));

        address shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        address shareDebtTokenImpl = address(new ShareDebtToken());

        // deploy silo config
        siloConfig =
            _deploySiloConfig(siloData["MOCK"], siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl);

        // deploy silo
        siloFactory.createSilo(
            siloData["MOCK"], siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl
        );

        (_vault0, _vault1) = siloConfig.getSilos();
        vault0 = Silo(payable(_vault0));
        vault1 = Silo(payable(_vault1));
        silos.push(_vault0);
        silos.push(_vault1);

        // Store all collateral (silos) & debt shareTokens in helper arrays
        shareTokens.push(_vault0);
        shareTokens.push(_vault1);

        (address debtToken0,) = siloConfig.getDebtShareTokenAndAsset(address(vault0));
        shareTokens.push(debtToken0);
        (address debtToken1,) = siloConfig.getDebtShareTokenAndAsset(address(vault1));
        shareTokens.push(debtToken1);

        debtTokens.push(debtToken0);
        debtTokens.push(debtToken1);

        // Store the protected collateral tokens in an array
        (, address protectedCollateralToken0) =
            siloConfig.getCollateralShareTokenAndAsset(address(vault0), ISilo.CollateralType.Protected);

        (, address protectedCollateralToken1) =
            siloConfig.getCollateralShareTokenAndAsset(address(vault1), ISilo.CollateralType.Protected);

        protectedTokens.push(protectedCollateralToken0);
        protectedTokens.push(protectedCollateralToken1);

        // Deploy and initialize the liquidation module & mock flashloan receiver
        liquidationModule = PartialLiquidation(vault0.config().getConfig(_vault0).hookReceiver);

        flashLoanReceiver = address(new MockFlashLoanReceiver());
    }

    function core_setUp(address feeReceiver) internal {
        core_deploySiloLiquidation();
        core_deploySiloFactory(feeReceiver);
        core_deployInterestRateConfigFactory();
        core_deployInterestRateModel();
        core_deployGaugeHookReceiver();
        core_deploySiloDeployer();
    }

    /// @notice Deploy protocol actors and initialize their balances
    function _setUpActors() internal {
        // Initialize the three actors of the fuzzers
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        // Initialize the tokens array
        address[] memory tokens = new address[](2);
        tokens[0] = address(_asset0);
        tokens[1] = address(_asset1);

        address[] memory contracts = new address[](3);
        contracts[0] = address(_vault0);
        contracts[1] = address(_vault1);
        contracts[2] = address(liquidationModule);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deploy actor proxies and approve system contracts
            address _actor = _setUpActor(addresses[i], tokens, contracts);

            // Mint initial balances to actors
            for (uint256 j = 0; j < tokens.length; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }
            actorAddresses.push(_actor);
        }
    }

    /// @notice Deploy an actor proxy contract for a user address
    /// @param userAddress Address of the user
    /// @param tokens Array of token addresses
    /// @param contracts Array of contract addresses to aprove tokens to
    /// @return actorAddress Address of the deployed actor
    function _setUpActor(address userAddress, address[] memory tokens, address[] memory contracts)
        internal
        returns (address actorAddress)
    {
        bool success;
        Actor _actor = new Actor(tokens, contracts);
        actors[userAddress] = _actor;
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  SILO CUSTOM SETUP FUNCTIONS                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function core_deploySiloFactory(address feeReceiver) internal {
        uint256 daoFee = 0.15e18;
        address daoFeeReceiver = feeReceiver == address(0) ? address(0) : feeReceiver;

        siloFactory = ISiloFactory(address(new SiloFactory(daoFeeReceiver)));
        siloFactoryInternal = ISiloFactory(address(new SiloFactory(daoFeeReceiver)));
    }

    function core_deployInterestRateConfigFactory() internal {
        interestRateModelV2ConfigFactory = IInterestRateModelV2Factory(address(new InterestRateModelV2Factory()));
        // set preset IRM configs
        presetIRMConfigs.push(
            IInterestRateModelV2.Config({
                uopt: 500000000000000000,
                ucrit: 900000000000000000,
                ulow: 300000000000000000,
                ki: 146805,
                kcrit: 317097919838,
                klow: 105699306613,
                klin: 4439370878,
                beta: 69444444444444,
                ri: 0,
                Tcrit: 0
            })
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

        siloDeployer = ISiloDeployer(
            address(
                new SiloDeployer(
                    interestRateModelV2ConfigFactory,
                    siloFactory,
                    siloImpl,
                    shareProtectedCollateralTokenImpl,
                    shareDebtTokenImpl
                )
            )
        );
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
            _shareProtectedCollateralTokenImpl, nextSiloId, address(siloFactory)
        );

        configData1.protectedShareToken = CloneDeterministic.predictShareProtectedCollateralToken1Addr(
            _shareProtectedCollateralTokenImpl, nextSiloId, address(siloFactory)
        );

        configData0.debtShareToken =
            CloneDeterministic.predictShareDebtToken0Addr(_shareDebtTokenImpl, nextSiloId, address(siloFactory));

        configData1.debtShareToken =
            CloneDeterministic.predictShareDebtToken1Addr(_shareDebtTokenImpl, nextSiloId, address(siloFactory));

        siloConfig = ISiloConfig(address(new SiloConfig(nextSiloId, configData0, configData1)));
    }

    function _deployAssets() internal {
        _asset0 = new TestERC20("Test Token0", "TT0", 18);
        _asset1 = new TestERC20("Test Token1", "TT1", 6);
        baseAssets.push(address(_asset0));
        baseAssets.push(address(_asset1));
    }

    function _deployOracles() internal {
        oracle0 = address(new MockSiloOracle(address(_asset0), 1 ether, QUOTE_TOKEN_ADDRESS, 18));
        oracle1 = address(new MockSiloOracle(address(_asset1), 1 ether, QUOTE_TOKEN_ADDRESS, 18));
    }

    function _initData(address mock0, address mock1) internal {
        // The FULL data relies on addresses set in _setupBasicData()
        siloData["FULL"] = ISiloConfig.InitData({
            deployer: address(this),
            daoFee: 0.15e18,
            deployerFee: 0.1000e18,
            token0: address(_asset0),
            solvencyOracle0: oracle0,
            maxLtvOracle0: oracle0,
            interestRateModel0: address(interestRateModelV2),
            maxLtv0: 0.7500e18,
            lt0: 0.8500e18,
            liquidationTargetLtv0: 0.8500e18 * 0.9e18 / 1e18,
            liquidationFee0: 0.0500e18,
            flashloanFee0: 0.0100e18,
            callBeforeQuote0: true,
            hookReceiver: address(liquidationModule),
            token1: address(_asset1),
            solvencyOracle1: oracle1,
            maxLtvOracle1: oracle1,
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
        mocks.maxLtvOracle0 = address(0);
        mocks.maxLtvOracle1 = address(0);
        mocks.callBeforeQuote0 = false;
        mocks.callBeforeQuote1 = false;

        siloData["MOCK"] = mocks;
    }
}

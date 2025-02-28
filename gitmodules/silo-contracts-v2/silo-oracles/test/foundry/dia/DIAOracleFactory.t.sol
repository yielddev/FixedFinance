// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "../../../constants/Arbitrum.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {TokensGenerator} from "../_common/TokensGenerator.sol";
import {DIAOracleConfig} from "../../../contracts/dia/DIAOracleConfig.sol";
import {DIAOracleFactory, DIAOracle, IDIAOracle} from "../../../contracts/dia/DIAOracleFactory.sol";
import {IDIAOracleV2} from "../../../contracts/external/dia/IDIAOracleV2.sol";
import {DIAConfigDefault} from "../_common/DIAConfigDefault.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract DIAOracleFactoryTest
*/
contract DIAOracleFactoryTest is DIAConfigDefault {
    uint256 constant TEST_BLOCK = 124884940;

    DIAOracleFactory public immutable ORACLE_FACTORY;

    constructor() TokensGenerator(BlockChain.ARBITRUM) {
        initFork(TEST_BLOCK);

        ORACLE_FACTORY = new DIAOracleFactory();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracleFactory_DIA_DECIMALS
    */
    function test_DIAOracleFactory_DIA_DECIMALS() public {
        assertEq(ORACLE_FACTORY.DIA_DECIMALS(), 8);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracleFactory_verifyConfig
    */
    function test_DIAOracleFactory_verifyConfig() public view {
        ORACLE_FACTORY.verifyConfig(_defaultDIAConfig());
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracleFactory_quote_RDPXinUSDT
    */
    function test_DIAOracleFactory_quote_RDPXinUSDT() public {
        DIAOracle oracle = ORACLE_FACTORY.create(_defaultDIAConfig(1e20, 0));

        uint256 price = oracle.quote(1e18, address(tokens["RDPX"]));
        emit log_named_decimal_uint("RDPX/USD", price, 18);
        assertEq(price, 16_676184, ", RDPX/USD price is ~$16");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracleFactory_quote_RDPXinTUSD
    */
    function test_DIAOracleFactory_quote_RDPXinTUSD() public {
        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfig(1e8, 0);
        cfg.quoteToken = IERC20Metadata(address(tokens["TUSD"]));

        DIAOracle oracle = ORACLE_FACTORY.create(cfg);

        uint256 gasStart = gasleft();
        uint256 price = oracle.quote(1e18, address(tokens["RDPX"]));
        uint256 gasEnd = gasleft();

        emit log_named_decimal_uint("RDPX/USD", price, 18);
        emit log_named_uint("gas used", gasStart - gasEnd);
        assertEq(price, 16_676184950000000000, ", RDPX/USD price is ~$16");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_DIAOracleFactory_quote_RDPXinETH
    */
    function test_DIAOracleFactory_quote_RDPXinETH() public {
        IDIAOracle.DIADeploymentConfig memory cfg = _defaultDIAConfig();
        cfg.quoteToken = IERC20Metadata(address(tokens["WETH"]));
        cfg.secondaryKey = "ETH/USD";
        cfg.invertSecondPrice = true;

        uint256 gasStart = gasleft();
        DIAOracle oracle = ORACLE_FACTORY.create(cfg);
        uint256 gasEnd = gasleft();

        emit log_named_uint("gas for creation", gasStart - gasEnd);

        gasStart = gasleft();
        uint256 price = oracle.quote(1e18, address(tokens["RDPX"]));
        gasEnd = gasleft();

        // RDPX/USD => 0x6365d6bf = 16_67618495n
        // ETH/USD => 0x266c832ff2 = 1650_29294066n
        // so RDPX/ETH ~ 0.01ETH

        // _printDIASetup(oracle.oracleConfig().getQuoteData());

        emit log_named_decimal_uint("RDPX/ETH", price, 18);
        emit log_named_uint("gas used", gasStart - gasEnd);
        assertEq(price, 10104984720670688, "RDPX/ETH price 0.01ETH");
    }
}

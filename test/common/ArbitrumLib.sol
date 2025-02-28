// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IInterestRateModelV2Factory} from "silo-core-v2/interfaces/IInterestRateModelV2Factory.sol";
import {SiloDeployer} from "silo-core-v2/SiloDeployer.sol";


library ArbitrumLib {
    SiloDeployer constant SILO_DEPLOYER = SiloDeployer(0xB30Ee27f6e19A24Df12dba5Ab4124B6dCE9beeE5);

    address constant CHAINLINK_ETH_USD_AGREGATOR = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address constant CHAINLINK_ETH_USD = 0xed4399235f377AFB48dA005607a0F52Ed7C3bC7F;

    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant WETH_WHALE = 0xC3E5607Cd4ca0D5Fe51e09B60Ed97a0Ae6F874dd;

    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDC_WHALE = 0x3931dAb967C3E2dbb492FE12460a66d0fe4cC857;
    address constant GUSDPT = 0x0b6121b4c00ca4FbBb6516C11eB4BF61722E0f8d;
    address constant GUSD_WHALE = 0x1B3984868782b69D1AaE816F437a13B4B674CB66;
    address constant GUSD_MARKET = 0x22e0F26320aCE985e3CB2434095F18Bfe114E28e;

//     address constant DUSDCPT = 0x137f793505e7884CB70Ee5933c83447E85B1BD17;
// //    address constant DUSDCPT_WHALE 
//     address constant DUSDC_MARKET = 0x0bd6890b3bb15f16430546147734b254d0b;
//     address constant GUSDPT = 
//     address constant GUSD_MARKET = 


}
// }

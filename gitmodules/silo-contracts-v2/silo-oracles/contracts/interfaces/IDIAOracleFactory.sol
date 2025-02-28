// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IDIAOracle} from "./IDIAOracle.sol";

interface IDIAOracleFactory {
    function create(IDIAOracle.DIADeploymentConfig calldata _config)
        external
        returns (address oracle);
}

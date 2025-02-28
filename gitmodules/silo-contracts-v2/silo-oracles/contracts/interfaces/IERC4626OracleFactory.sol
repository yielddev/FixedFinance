// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

interface IERC4626OracleFactory {
    event ERC4626OracleCreated(ISiloOracle indexed oracle);

    function createERC4626Oracle(IERC4626 _vault) external returns (ISiloOracle oracle);
}

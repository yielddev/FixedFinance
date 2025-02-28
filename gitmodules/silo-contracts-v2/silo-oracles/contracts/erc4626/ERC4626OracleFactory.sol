// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IERC4626OracleFactory} from "silo-oracles/contracts/interfaces/IERC4626OracleFactory.sol";
import {ERC4626Oracle} from "silo-oracles/contracts/erc4626/ERC4626Oracle.sol";

contract ERC4626OracleFactory is IERC4626OracleFactory {
    mapping(address => bool) public createdInFactory;

    function createERC4626Oracle(IERC4626 _vault) external returns (ISiloOracle oracle) {
        oracle = ISiloOracle(address(new ERC4626Oracle(_vault)));

        createdInFactory[address(oracle)] = true;

        emit ERC4626OracleCreated(oracle);
    }
}

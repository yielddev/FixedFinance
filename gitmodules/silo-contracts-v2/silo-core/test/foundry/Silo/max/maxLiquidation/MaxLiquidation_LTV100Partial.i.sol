// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MaxLiquidationCommon} from "./MaxLiquidationCommon.sol";

/*
    forge test -vv --ffi --mc MaxLiquidationLTV100PartialTest

    cases where we go from solvent to 100% and we can do partial liquidation
    at the end turns out, there is no such cases for this setup, but I keep file to show this was considered
*/
contract MaxLiquidationLTV100PartialTest is MaxLiquidationCommon {
    /*
    forge test -vv --ffi --mt test_maxLiquidation_LTV100_partial_1token_sTokens_fuzz
    */
    /// forge-config: core-test.fuzz.runs = 100
    function test_maxLiquidation_LTV100_partial_1token_sTokens() public {
        // I did not found cases for this scenario
    }

    /*
    forge test -vv --ffi --mt test_maxLiquidation_LTV100_partial_1token_tokens_fuzz
    */
    /// forge-config: core-test.fuzz.runs = 100
    function test_maxLiquidation_LTV100_partial_1token_tokens() public {
        // I did not found cases for this scenario
    }

    /*
    forge test -vv --ffi --mt test_maxLiquidation_LTV100_partial_2tokens_sToken_fuzz
    */
    /// forge-config: core-test.fuzz.runs = 100
    function test_maxLiquidation_LTV100_partial_2tokens_sToken() public {
        // I did not found cases for this scenario
    }

    /*
    forge test -vv --ffi --mt test_maxLiquidation_LTV100_partial_2tokens_token_fuzz
    */
    /// forge-config: core-test.fuzz.runs = 100
    function test_maxLiquidation_LTV100_partial_2tokens_token() public {
        // I did not found cases for this scenario
    }

    function _executeLiquidation(bool, bool) internal pure override returns (uint256, uint256) {
        // not in use
        return (0, 0);
    }

    function _withChunks() internal pure override returns (bool) {
        return false;
    }
}

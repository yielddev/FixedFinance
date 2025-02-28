// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {SiloLendingLib} from "silo-core/contracts/lib/SiloLendingLib.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {TokenMock} from "silo-core/test/foundry/_mocks/TokenMock.sol";
import {OracleMock} from "silo-core/test/foundry/_mocks/OracleMock.sol";
import {MaxBorrowValueToAssetsAndSharesTestData} from "../../data-readers/MaxBorrowValueToAssetsAndSharesTestData.sol";

/*
    forge test -vv --mc MaxBorrowValueToAssetsAndSharesTest
*/
contract MaxBorrowValueToAssetsAndSharesTest is Test {
    address constant ORACLE_ADDRESS = address(0xabcd);

    TokenMock immutable debtToken;
    OracleMock immutable oracle;

    MaxBorrowValueToAssetsAndSharesTestData immutable tests;

    constructor() {
        debtToken = new TokenMock(address(0xDDDDDDDDDDDDDD));
        oracle = new OracleMock(ORACLE_ADDRESS);
        tests = new MaxBorrowValueToAssetsAndSharesTestData(debtToken.ADDRESS());
    }

    /*
    forge test -vv --mt test_maxBorrowValueToAssetsAndShares_loop
    */
    function test_maxBorrowValueToAssetsAndShares_loop() public {
        MaxBorrowValueToAssetsAndSharesTestData.MBVData[] memory testDatas = tests.getData();

        for (uint256 i; i < testDatas.length; i++) {
            vm.clearMockedCalls();
            emit log_string(testDatas[i].name);

            if (testDatas[i].input.oracleSet) {
                oracle.quoteMock(1e18, testDatas[i].input.debtToken, testDatas[i].input.debtOracleQuote);
            }

            (uint256 maxAssets, uint256 maxShares) = SiloLendingLib.maxBorrowValueToAssetsAndShares(
                testDatas[i].input.maxBorrowValue,
                testDatas[i].input.debtToken,
                testDatas[i].input.oracleSet ? ISiloOracle(ORACLE_ADDRESS) : ISiloOracle(address(0)),
                testDatas[i].input.totalDebtAssets,
                testDatas[i].input.totalDebtShares
            );

            assertEq(maxAssets, testDatas[i].output.assets, string(abi.encodePacked(testDatas[i].name, " > assets")));
            assertEq(maxShares, testDatas[i].output.shares, string(abi.encodePacked(testDatas[i].name, " > shares")));
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IMethodReentrancyTest} from "../interfaces/IMethodReentrancyTest.sol";

abstract contract MethodReentrancyTest is Test, IMethodReentrancyTest {
    function methodSignature() external view returns (bytes4 sig) {
        sig = bytes4(bytes32(keccak256(bytes(IMethodReentrancyTest(address(this)).methodDescription()))));
    }
}

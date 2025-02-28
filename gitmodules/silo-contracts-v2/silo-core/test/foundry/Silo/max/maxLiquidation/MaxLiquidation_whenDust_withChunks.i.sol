// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

import {MaxLiquidationDustTest} from "./MaxLiquidation_whenDust.i.sol";

/*
    forge test -vv --ffi --mc MaxLiquidationDustWithChunksTest

    this tests are MaxLiquidationDustTest cases, difference is, we splitting max liquidation in chunks
*/
contract MaxLiquidationDustWithChunksTest is MaxLiquidationDustTest {
    using SiloLensLib for ISilo;

    function _executeLiquidation(bool _sameToken, bool _receiveSToken)
        internal
        override
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        uint256 collateralToLiquidate;
        uint256 maxDebtToCover;

        { // too deep
            bool sTokenRequired;
            (collateralToLiquidate, maxDebtToCover, sTokenRequired) = partialLiquidation.maxLiquidation(borrower);
            assertTrue(!sTokenRequired, "sTokenRequired not required");
        }

        emit log_named_decimal_uint("[DustWithChunks] collateralToLiquidate", collateralToLiquidate, 18);
        emit log_named_decimal_uint("[DustWithChunks] maxDebtToCover", maxDebtToCover, 18);
        emit log_named_decimal_uint("[DustWithChunks] ltv before", silo0.getLtv(borrower), 16);

        for (uint256 i; i < 5; i++) {
            emit log_named_uint("[DustWithChunks] case ------------------------", i);
            bool isSolvent = silo0.isSolvent(borrower);

            if (isSolvent) revert("it should be NOT possible to liquidate with chunk, so why user solvent?");

            uint256 testDebtToCover = _calculateChunk(maxDebtToCover, i);
            emit log_named_uint("[DustWithChunks] testDebtToCover", testDebtToCover);

            _liquidationCallReverts(testDebtToCover, _sameToken, _receiveSToken);
        }

        // only full is possible
        return _liquidationCall(maxDebtToCover, _sameToken, _receiveSToken);
    }

    function _liquidationCallReverts(uint256 _maxDebtToCover, bool _sameToken, bool _receiveSToken) private {
        vm.expectRevert(IPartialLiquidation.FullLiquidationRequired.selector);

        partialLiquidation.liquidationCall(
            address(_sameToken ? token1 : token0),
            address(token1),
            borrower,
            _maxDebtToCover,
            _receiveSToken
        );
    }

    function _withChunks() internal pure override returns (bool) {
        return true;
    }
}

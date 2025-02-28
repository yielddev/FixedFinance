// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin5/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";

import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";
import {RevertLib} from "silo-core/contracts/lib/RevertLib.sol";
import {CallBeforeQuoteLib} from "silo-core/contracts/lib/CallBeforeQuoteLib.sol";

import {PartialLiquidationExecLib} from "./lib/PartialLiquidationExecLib.sol";
import {BaseHookReceiver} from "../_common/BaseHookReceiver.sol";

/// @title PartialLiquidation module for executing liquidations
/// @dev if we need additional hook functionality, this contract should be included as parent
abstract contract PartialLiquidation is BaseHookReceiver, IPartialLiquidation {
    using SafeERC20 for IERC20;
    using Hook for uint24;
    using CallBeforeQuoteLib for ISiloConfig.ConfigData;

    struct LiquidationCallParams {
        uint256 collateralShares;
        uint256 protectedShares;
        uint256 withdrawAssetsFromCollateral;
        uint256 withdrawAssetsFromProtected;
        bytes4 customError;
    }

    /// @inheritdoc IPartialLiquidation
    function liquidationCall( // solhint-disable-line function-max-lines, code-complexity
        address _collateralAsset,
        address _debtAsset,
        address _borrower,
        uint256 _maxDebtToCover,
        bool _receiveSToken
    )
        external
        virtual
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {
        ISiloConfig siloConfigCached = siloConfig;

        require(address(siloConfigCached) != address(0), EmptySiloConfig());
        require(_maxDebtToCover != 0, NoDebtToCover());

        siloConfigCached.turnOnReentrancyProtection();

        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _fetchConfigs(siloConfigCached, _collateralAsset, _debtAsset, _borrower);

        LiquidationCallParams memory params;

        (
            params.withdrawAssetsFromCollateral, params.withdrawAssetsFromProtected, repayDebtAssets, params.customError
        ) = PartialLiquidationExecLib.getExactLiquidationAmounts(
            collateralConfig,
            debtConfig,
            _borrower,
            _maxDebtToCover,
            collateralConfig.liquidationFee
        );

        RevertLib.revertIfError(params.customError);

        // we do not allow dust so full liquidation is required
        require(repayDebtAssets <= _maxDebtToCover, FullLiquidationRequired());

        IERC20(debtConfig.token).safeTransferFrom(msg.sender, address(this), repayDebtAssets);
        IERC20(debtConfig.token).safeIncreaseAllowance(debtConfig.silo, repayDebtAssets);

        address shareTokenReceiver = _receiveSToken ? msg.sender : address(this);

        params.collateralShares = _callShareTokenForwardTransferNoChecks(
            collateralConfig.silo,
            _borrower,
            shareTokenReceiver,
            params.withdrawAssetsFromCollateral,
            collateralConfig.collateralShareToken,
            ISilo.AssetType.Collateral
        );

        params.protectedShares = _callShareTokenForwardTransferNoChecks(
            collateralConfig.silo,
            _borrower,
            shareTokenReceiver,
            params.withdrawAssetsFromProtected,
            collateralConfig.protectedShareToken,
            ISilo.AssetType.Protected
        );

        siloConfigCached.turnOffReentrancyProtection();

        ISilo(debtConfig.silo).repay(repayDebtAssets, _borrower);

        if (_receiveSToken) {
            if (params.collateralShares != 0) {
                withdrawCollateral = ISilo(collateralConfig.silo).previewRedeem(
                    params.collateralShares,
                    ISilo.CollateralType.Collateral
                );
            }

            if (params.protectedShares != 0) {
                unchecked {
                    // protected and collateral values were split from total collateral to withdraw,
                    // so we will not overflow when we sum them back, especially that on redeem, we rounding down
                    withdrawCollateral += ISilo(collateralConfig.silo).previewRedeem(
                        params.protectedShares,
                        ISilo.CollateralType.Protected
                    );
                }
            }
        } else {
            // in case of liquidation redeem, hook transfers sTokens to itself and it has no debt
            // so solvency will not be checked in silo on redeem action

            // if share token offset is more than 0, positive number of shares can generate 0 assets
            // so there is a need to check assets before we withdraw collateral/protected

            if (params.collateralShares != 0) {
                withdrawCollateral = ISilo(collateralConfig.silo).redeem({
                    _shares: params.collateralShares,
                    _receiver: msg.sender,
                    _owner: address(this),
                    _collateralType: ISilo.CollateralType.Collateral
                });
            }

            if (params.protectedShares != 0) {
                unchecked {
                    // protected and collateral values were split from total collateral to withdraw,
                    // so we will not overflow when we sum them back, especially that on redeem, we rounding down
                    withdrawCollateral += ISilo(collateralConfig.silo).redeem({
                        _shares: params.protectedShares,
                        _receiver: msg.sender,
                        _owner: address(this),
                        _collateralType: ISilo.CollateralType.Protected
                    });
                }
            }
        }

        emit LiquidationCall(
            msg.sender,
            debtConfig.silo,
            _borrower,
            repayDebtAssets,
            withdrawCollateral,
            _receiveSToken
        );
    }

    /// @inheritdoc IPartialLiquidation
    function maxLiquidation(address _borrower)
        external
        view
        virtual
        returns (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired)
    {
        return PartialLiquidationExecLib.maxLiquidation(siloConfig, _borrower);
    }

    function _fetchConfigs(
        ISiloConfig _siloConfigCached,
        address _collateralAsset,
        address _debtAsset,
        address _borrower
    )
        internal
        virtual
        returns (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        )
    {
        (collateralConfig, debtConfig) = _siloConfigCached.getConfigsForSolvency(_borrower);

        require(debtConfig.silo != address(0), UserIsSolvent());
        require(_collateralAsset == collateralConfig.token, UnexpectedCollateralToken());
        require(_debtAsset == debtConfig.token, UnexpectedDebtToken());

        ISilo(debtConfig.silo).accrueInterest();

        if (collateralConfig.silo != debtConfig.silo) {
            ISilo(collateralConfig.silo).accrueInterest();
            collateralConfig.callSolvencyOracleBeforeQuote();
            debtConfig.callSolvencyOracleBeforeQuote();
        }
    }

    function _callShareTokenForwardTransferNoChecks(
        address _silo,
        address _borrower,
        address _receiver,
        uint256 _withdrawAssets,
        address _shareToken,
        ISilo.AssetType _assetType
    ) internal virtual returns (uint256 shares) {
        if (_withdrawAssets == 0) return 0;
        
        shares = SiloMathLib.convertToShares(
            _withdrawAssets,
            ISilo(_silo).getTotalAssetsStorage(_assetType),
            IShareToken(_shareToken).totalSupply(),
            Rounding.LIQUIDATE_TO_SHARES,
            ISilo.AssetType(_assetType)
        );

        if (shares == 0) return 0;

        IShareToken(_shareToken).forwardTransferFromNoChecks(_borrower, _receiver, shares);
    }
}

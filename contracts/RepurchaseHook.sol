// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IHookReceiver} from "silo-core-v2/interfaces/IHookReceiver.sol";
import {ISiloConfig} from "silo-core-v2/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core-v2/interfaces/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Hook} from "silo-core-v2/lib/Hook.sol";
import {BaseHookReceiver} from "silo-core-v2/utils/hook-receivers/_common/BaseHookReceiver.sol";
import {IShareToken} from "silo-core-v2/interfaces/IShareToken.sol";
import {SiloMathLib} from "silo-core-v2/lib/SiloMathLib.sol";
import {Rounding} from "silo-core-v2/lib/Rounding.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RepurchaseHook is BaseHookReceiver {
    using SafeERC20 for IERC20;
    error RepurchaseHook_WrongAssetForMarket();
    error UnexpectedCollateralToken();
    error UnexpectedDebtToken();
    error NoDebtToCover();
    error UserIsSolvent();
    error UnknownRatio();
    error NoRepayAssets();
    address ptAssetSilo;
    address underlyingAssetSilo;
    mapping(address => Loan) public loans;
    struct Loan {
        uint256 price; // total price to repurchase
        uint256 term; // term of the loan
        uint256 collateral; // collateral amount
    }

    function initialize(ISiloConfig _siloConfig, bytes calldata _data) external initializer override {
        (address owner, address _ptAsset) = abi.decode(_data, (address, address));

        __BaseHookReceiver_init(_siloConfig);
        __RepurchaseHook_init(_siloConfig, _ptAsset);
    }

    function __RepurchaseHook_init(ISiloConfig _siloConfig, address _ptAsset) internal {
        (address silo0, address silo1) = _siloConfig.getSilos();

        if(ISilo(silo0).asset() == _ptAsset) {
            ptAssetSilo = silo0;
            underlyingAssetSilo = silo1;
        } else if (ISilo(silo1).asset() == _ptAsset) {
            ptAssetSilo = silo1;
            underlyingAssetSilo = silo0;
        } else {
            revert RepurchaseHook_WrongAssetForMarket();
        }

        (uint256 hooksBefore0, uint256 hooksAfter0) = _hookReceiverConfig(underlyingAssetSilo);
        hooksBefore0 = Hook.addAction(hooksBefore0, Hook.BORROW);

        hooksAfter0 = Hook.addAction(hooksAfter0, Hook.BORROW);
        hooksAfter0 = Hook.addAction(hooksAfter0, Hook.REPAY);
        hooksAfter0 = Hook.addAction(hooksAfter0, Hook.shareTokenTransfer(Hook.DEBT_TOKEN));

        _setHookConfig(underlyingAssetSilo, hooksBefore0, hooksAfter0);

    }

    function beforeAction(address _silo, uint256 _action, bytes calldata _inputAndOutput) external {
        if (Hook.matchAction(_action, Hook.BORROW)) {
            Hook.BeforeBorrowInput memory borrow = Hook.beforeBorrowDecode(_inputAndOutput);
            uint256 haircut = ((loans[borrow.borrower].price + borrow.assets) * 500) / 10_000;
            if(IERC20(ISilo(_silo).asset()).allowance(borrow.receiver, address(this)) < haircut) {
                revert("Insufficient Approval");
            }

            loans[borrow.borrower] = Loan({
                price: (loans[borrow.borrower].price + borrow.assets), // the total effective debt
                term: block.timestamp + 30 days,
                collateral: (loans[borrow.borrower].collateral + borrow.assets) //(borrow.assets + haircut) worth of collateral // total underlying 
            });
        } 
    }

    function afterAction(address _silo, uint256 _action, bytes calldata _inputAndOutput) external {
        if(Hook.matchAction(_action, Hook.BORROW)) {
                /// @notice The data structure for the after borrow hook
                /// @param assets The amount of assets borrowed
                /// @param shares The amount of shares borrowed
                /// @param receiver The receiver of the borrow
                /// @param borrower The borrower of the assets
                /// @param spender Address which initiates the borrowing action on behalf of the borrower
                /// @param borrowedAssets The exact amount of assets being borrowed
                /// @param borrowedShares The exact amount of shares being borrowed
            Hook.AfterBorrowInput memory borrow = Hook.afterBorrowDecode(_inputAndOutput);
            Loan memory loan = loans[borrow.borrower];
            uint256 haircut = ((loan.price) * 500) / 10_000;
            if (haircut > 0) { // mint extra debt to represent the haircut. IE repayment is 100usd but 97usd was delivered, 3 usd haircut
                IERC20(ISilo(_silo).asset()).safeTransferFrom(borrow.receiver, address(this), haircut);
                IERC20(ISilo(_silo).asset()).approve(_silo, haircut);
                uint256 shares = ISilo(_silo).deposit(haircut, address(this));
                (bool success, bytes memory data) = ISilo(_silo).callOnBehalfOfSilo(_silo,
                    uint256(0), ISilo.CallType.Call,
                    abi.encodeWithSelector(IShareToken.burn.selector, address(this), address(this), shares));
                if (!success) {
                    revert("Haircut debt issuance failed");
                    // handle unloan
                } 
            }
            //
        } else if (Hook.matchAction(_action, Hook.REPAY)) {

            /// @notice The data structure for the after repay hook
            /// @param assets The amount of assets to repay
            /// @param shares The amount of shares to repay
            /// @param borrower The borrower of the assets
            /// @param repayer The repayer of the assets
            /// @param repaidAssets The exact amount of assets being repaid
            /// @param repaidShares The exact amount of shares being repaid

            Hook.AfterRepayInput memory repay = Hook.afterRepayDecode(_inputAndOutput);
            loans[repay.borrower].price -= repay.repaidAssets;
            loans[repay.borrower].collateral -= repay.repaidAssets; // collateral to debt ratio 1:1
            if (loans[repay.borrower].price == 0) {
                closeOutLoan(repay.borrower);
            }
        } else if (Hook.matchAction(_action, Hook.shareTokenTransfer(Hook.DEBT_TOKEN))) {
            /// @notice The data structure for the share token transfer hook
            /// @param sender The sender of the transfer (address(0) on mint)
            /// @param recipient The recipient of the transfer (address(0) on burn)
            /// @param amount The amount of tokens transferred/minted/burned
            /// @param senderBalance The balance of the sender after the transfer (empty on mint)
            /// @param recipientBalance The balance of the recipient after the transfer (empty on burn)
            /// @param totalSupply The total supply of the share token

            Hook.AfterTokenTransfer memory input = Hook.afterTokenTransferDecode(_inputAndOutput);
            if (input.sender != address(0) && input.recipient != address(0)) {
                uint256 debtTransfered = ISilo(_silo).convertToAssets(input.amount, ISilo.AssetType.Debt);
                loans[input.sender].price -= debtTransfered;
                loans[input.sender].collateral -= debtTransfered; // collateral to debt ratio 1:1, collateral released


                loans[input.recipient].price += debtTransfered;
                loans[input.recipient].collateral += debtTransfered;

                // subject to the shortest term
                if (loans[input.recipient].term == 0) {
                    loans[input.recipient].term = loans[input.sender].term;
                } else if (loans[input.sender].term < loans[input.recipient].term) {
                    loans[input.recipient].term = loans[input.sender].term;
                } else {
                    loans[input.recipient].term = loans[input.recipient].term;
                }

                if (loans[input.sender].price == 0) {
                    closeOutLoan(input.sender);
                }
            }
        }
    }
    function liquidationCall( // solhint-disable-line function-max-lines, code-complexity
        address _collateralAsset,
        address _debtAsset,
        address _borrower
    )
        external
        virtual
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets)
    {

        Loan memory loan = loans[_borrower];
        require(loan.term < block.timestamp, "Loan is still active");

        ISiloConfig siloConfigCached = siloConfig;
        require(address(siloConfigCached) != address(0), EmptySiloConfig());
        siloConfigCached.turnOnReentrancyProtection();

        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _fetchConfigs(siloConfigCached, _collateralAsset, _debtAsset, _borrower);

        IERC20(debtConfig.token).safeTransferFrom(msg.sender, address(this), loan.price);
        IERC20(debtConfig.token).safeIncreaseAllowance(debtConfig.silo, loan.price);

        siloConfigCached.turnOffReentrancyProtection();
        ISilo(debtConfig.silo).repay(loan.price, _borrower);

        address shareTokenReceiver = msg.sender; // or address(this) for redeem

        // sieze collateral 
        _callShareTokenForwardTransferNoChecks(
            collateralConfig.silo,
            _borrower,
            shareTokenReceiver,
            loan.collateral,
            collateralConfig.collateralShareToken,
            ISilo.AssetType.Collateral
        );

        closeOutLoan(_borrower);
    }

    function closeOutLoan(address _borrower) internal {
        loans[_borrower].price = 0;
        loans[_borrower].term = 0;
        loans[_borrower].collateral = 0;
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
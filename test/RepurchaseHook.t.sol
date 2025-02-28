// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

import {ISiloConfig} from "silo-core-v2/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core-v2/interfaces/ISilo.sol";
import {IShareToken, IERC20Metadata} from "silo-core-v2/interfaces/IShareToken.sol";
import {SiloDeployer} from "silo-core-v2/SiloDeployer.sol";
import {CollectedErrors} from "../contracts/errors/CollectedErrors.sol";
import {OZErrors} from "../contracts/errors/OZErrors.sol";

import {Labels} from "./common/Labels.sol";
import {DeploySilo} from "./common/DeploySilo.sol";
import {ArbitrumLib} from "./common/ArbitrumLib.sol";
import {RepurchaseHook} from "../contracts/RepurchaseHook.sol";
// import {ShareDebtToken} from "silo-core-v2/utils/ShareDebtToken.sol";


contract RepurchaseHookTest is Labels {
    ISiloConfig public siloConfig;
    RepurchaseHook public clonedHook;
    uint256 public FEE_BPS = 500;
    function setUp() public {
        uint256 blockToFork = 310307061;
        vm.createSelectFork(vm.envString("RPC_ARBITRUM"), blockToFork);

        DeploySilo deployer = new DeploySilo();
        siloConfig = deployer.deploySilo(
            ArbitrumLib.SILO_DEPLOYER,
            address(new RepurchaseHook()),
            abi.encode(address(this), ArbitrumLib.GUSDPT)
        );

        clonedHook = RepurchaseHook(_getHookAddress(siloConfig));
        _setLabels(siloConfig);
    }

    function seed_usdc_pool() public {
        address depositor = makeAddr("depositor");
        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos(); 
        _getUSDC(depositor, 10e6);
        _deposit(usdcSilo, depositor, 10e6);
    }

    function deposit_gusdpt_collateral(address _user) public {

        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();

        _getGUSDPT(_user, 10e6);
        vm.startPrank(_user);
        IERC20(ArbitrumLib.GUSDPT).approve(gusdptSilo, 10e6);
        ISilo(gusdptSilo).deposit(10e6, _user);
        vm.stopPrank();

    }

    function test_borrow() public {
        address borrower = makeAddr("borrower");
        address depositor = makeAddr("depositor");
        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();

        seed_usdc_pool();
        deposit_gusdpt_collateral(borrower);

        vm.startPrank(borrower);

        // SUBOPTIMAL UX requires approval of haircut before borrowing from receiver
        IERC20(ArbitrumLib.USDC).approve(address(clonedHook), (10e6 * FEE_BPS) / 10_000);
        // Deposited 10 PT, Borrows 10 USDC pays 10 * 300 / 10000 = 0.3 USDC haircut
        ISilo(usdcSilo).borrow(10e6, borrower, borrower);
        vm.stopPrank();


        // loan struct price should be 10 usdc
        (uint256 price, uint256 term, uint256 collateral) = clonedHook.loans(borrower);
        assertEq(price, 10e6);
        // should have debt of 10 USDC
        (address debtToken, ) = siloConfig.getDebtShareTokenAndAsset(usdcSilo);
        assertEq(IERC20(debtToken).balanceOf(borrower), price); // debt = pric
        // USDC balance should be 10 - 0.3 = 9.7
        assertEq(IERC20(ArbitrumLib.USDC).balanceOf(borrower), 9.5e6);
        // USDC silo value should be 10 + 0.3 = 10.3
        assertEq(IERC20(ArbitrumLib.USDC).balanceOf(usdcSilo), 0.5e6);

        //Lending pools share value increased via haircut
        assertEq(ISilo(usdcSilo).convertToAssets(IERC20(usdcSilo).totalSupply()), 10.5e6);
        // no extra shares created
        assertEq(IERC20(usdcSilo).totalSupply(), IERC20(usdcSilo).balanceOf(address(depositor)));
    }
    function test_borrow_multiple() public {
        address borrower = makeAddr("borrower");
        address depositor = makeAddr("depositor");
        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();

        test_borrow();

        seed_usdc_pool();
        deposit_gusdpt_collateral(borrower);

        vm.startPrank(borrower);
        // full amount of haircut calculation is previouis loan 10 + new loan 10
        // in a second loan the haircut is paid on the total debt 20 for the next term 
        uint256 haircut = (20e6 * FEE_BPS) / 10_000;
        IERC20(ArbitrumLib.USDC).approve(address(clonedHook), haircut);
        ISilo(usdcSilo).borrow(10e6, borrower, borrower); // borrow another 10
        vm.stopPrank();

        (uint256 price, uint256 term, uint256 collateral) = clonedHook.loans(borrower);
        assertEq(price, 20e6);
        assertEq(term, block.timestamp + 30 days);
        assertEq(collateral, 20e6);
        assertEq(IERC20(ArbitrumLib.USDC).balanceOf(borrower), 9.5e6 + (10e6 - haircut));
        
        assertEq(IERC20(ArbitrumLib.USDC).balanceOf(usdcSilo), 0.5e6 + haircut);

        //Lending pools share value increased via haircut
        // pool value is 20 in initial deposits + previous haircut of 0.5 + new haircut
        assertEq(ISilo(usdcSilo).convertToAssets(IERC20(usdcSilo).totalSupply()), 20.5e6+haircut);
        // no extra shares created
        assertEq(IERC20(usdcSilo).totalSupply(), IERC20(usdcSilo).balanceOf(address(depositor)));

    }
    function test_repay() public {
        test_borrow();
        address depositor = makeAddr("depositor");
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");

        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();
        (address debtToken, ) = siloConfig.getDebtShareTokenAndAsset(usdcSilo); 

        uint256 haircut = (10e6 * 500) / 10_000;

        _getUSDC(borrower, haircut);

        vm.startPrank(borrower);
        IERC20(ArbitrumLib.USDC).approve(usdcSilo, _getDebtBalance(borrower));
        ISilo(usdcSilo).repay(_getDebtBalance(borrower), borrower);
        vm.stopPrank();
        (uint256 price, uint256 term, uint256 collateral) = clonedHook.loans(borrower);
        console.log("price", price);
        console.log("term", term);
        console.log("collateral", collateral);
        assertEq(price, 0);
        assertEq(term, 0);
        assertEq(collateral, 0);

        assertEq(IERC20(debtToken).balanceOf(borrower), 0); // debt = price
        // USDC balance should be 10 - 0.3 = 9.7
        assertEq(IERC20(ArbitrumLib.USDC).balanceOf(borrower), 0);
        // USDC silo value should be 10 + 0.3 = 10.3
        assertEq(IERC20(ArbitrumLib.USDC).balanceOf(usdcSilo), 10.5e6);

        //Lending pools share value increased via haircut
        assertEq(ISilo(usdcSilo).convertToAssets(IERC20(usdcSilo).totalSupply()), 10.5e6);
        // no extra shares created
        assertEq(IERC20(usdcSilo).totalSupply(), IERC20(usdcSilo).balanceOf(address(depositor)));

    }
    function test_partial_repay() public {
        test_borrow();
        address depositor = makeAddr("depositor");
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");

        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();
        (address debtToken, ) = siloConfig.getDebtShareTokenAndAsset(usdcSilo); 

        uint256 haircut = (10e6 * FEE_BPS) / 10_000;

        _getUSDC(borrower, haircut);

        uint256 startingDebt = _getDebtBalance(borrower);
        vm.startPrank(borrower);
        IERC20(ArbitrumLib.USDC).approve(usdcSilo, startingDebt / 2);
        ISilo(usdcSilo).repay(startingDebt / 2, borrower);
        vm.stopPrank();
        (uint256 price, uint256 term, uint256 collateral) = clonedHook.loans(borrower);
        console.log("price", price);
        console.log("term", term);
        console.log("collateral", collateral);
        assertEq(collateral, startingDebt / 2);
        assertEq(price, startingDebt / 2);
        //assertEq(term, );
        //assertEq(collateral, 0);

        assertEq(IERC20(debtToken).balanceOf(borrower), startingDebt / 2); 
        // USDC balance should be 10 - 0.3 = 9.7
        // assertEq(IERC20(ArbitrumLib.USDC).balanceOf(borrowe, 0);
        // USDC silo value should be 10 + 0.3 = 10.3
        // assertEq(IERC20(ArbitrumLib.USDC).balanceOf(usdcSilo), 10.3e6);

        //Lending pools share value increased via haircut
        assertEq(ISilo(usdcSilo).convertToAssets(IERC20(usdcSilo).totalSupply()), 10.5e6);
        // no extra shares created
        assertEq(IERC20(usdcSilo).totalSupply(), IERC20(usdcSilo).balanceOf(address(depositor)));
        // half collateral withdraw should be possible
        vm.startPrank(borrower);
        ISilo(gusdptSilo).withdraw(startingDebt / 2, borrower, borrower);
        vm.stopPrank();

        assertEq(IERC20(gusdptSilo).balanceOf(borrower), (startingDebt / 2) * 1000);// share adds 1000 percision
        assertEq(IERC20(ArbitrumLib.GUSDPT).balanceOf(borrower), startingDebt / 2);
    }

    function test_transfer_debt() public {
        test_borrow();

        address borrower = makeAddr("borrower");

        address debtReceiver = makeAddr("debtReceiver");

        deposit_gusdpt_collateral(debtReceiver);
    

        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();
        (address debtToken, ) = siloConfig.getDebtShareTokenAndAsset(usdcSilo); 

        uint256 startingDebt = _getDebtBalance(borrower);
        vm.startPrank(borrower);
        IERC20(debtToken).approve(debtReceiver, startingDebt / 2);
        vm.stopPrank();

        vm.startPrank(debtReceiver);
        IShareDebtToken(debtToken).setReceiveApproval(borrower, _getDebtBalance(borrower) / 2);
        IERC20(debtToken).transferFrom(borrower, debtReceiver, _getDebtBalance(borrower) / 2);
        vm.stopPrank();

        (uint256 price, uint256 term, uint256 collateral) = clonedHook.loans(borrower);
        (uint256 price1, uint256 term1, uint256 collateral1) = clonedHook.loans(debtReceiver);
        assertEq(price, price1);
        assertEq(term, term1);
        assertEq(collateral, collateral1);

        assertEq(IERC20(debtToken).balanceOf(borrower), startingDebt / 2); 
        assertEq(IERC20(debtToken).balanceOf(debtReceiver), startingDebt / 2); 

        // initial borower can withdraw half
        vm.startPrank(borrower);
        ISilo(gusdptSilo).withdraw(startingDebt / 2, borrower, borrower);
        vm.stopPrank();

        assertEq(IERC20(gusdptSilo).balanceOf(borrower), (startingDebt / 2) * 1000);// share adds 1000 percision
        assertEq(IERC20(ArbitrumLib.GUSDPT).balanceOf(borrower), startingDebt / 2);
    }

    function test_withdraw_collateral() public {
        address depositor = makeAddr("depositor");
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");

        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();
        test_repay(); // Borrows than repays to zero
        vm.startPrank(borrower);
        ISilo(gusdptSilo).withdraw(10e6, borrower, borrower);
        vm.stopPrank();

        assertEq(IERC20(gusdptSilo).balanceOf(borrower), 0);
        assertEq(IERC20(ArbitrumLib.GUSDPT).balanceOf(borrower), 10e6);
    }
    function test_liquidation() public {
        test_borrow();
        address depositor = makeAddr("depositor");
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");

        // Advance time past the loan term (1 day + 1 second)
        vm.warp(block.timestamp + 30 days + 1);

        // load liquidator
        (uint256 price, uint256 term, uint256 collateral) = clonedHook.loans(borrower);
        _getUSDC(liquidator, price);

        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();
        (address debtToken, ) = siloConfig.getDebtShareTokenAndAsset(usdcSilo);
        console.log("debtToken", debtToken);
        console.log("debtBalance: ", IERC20(debtToken).balanceOf(borrower));

        // do liquidation
        vm.startPrank(liquidator);
        IERC20(ArbitrumLib.USDC).   approve(address(clonedHook), price);
        clonedHook.liquidationCall(ISilo(gusdptSilo).asset(), ISilo(usdcSilo).asset(), borrower);
        vm.stopPrank();

        assertEq(IERC20(gusdptSilo).balanceOf(liquidator), collateral*1000);
        console.log("debtBalance: ", IERC20(debtToken).balanceOf(borrower));

        assertEq(IERC20(debtToken).balanceOf(borrower), 0);
        // check loan closed out
        (price, term, collateral) = clonedHook.loans(borrower);
        assertEq(price, 0);
        assertEq(term, 0);
        assertEq(collateral, 0);
    }


    function _getUSDC(address _user, uint256 _amount) internal {
        vm.prank(ArbitrumLib.USDC_WHALE);
        IERC20(ArbitrumLib.USDC).transfer(_user, _amount);
    }

    function _getWETH(address _user, uint256 _amount) internal {
        vm.prank(ArbitrumLib.WETH_WHALE);
        IERC20(ArbitrumLib.WETH).transfer(_user, _amount);
    }
    function _getGUSDPT(address _user, uint256 _amount) internal {
        vm.prank(ArbitrumLib.GUSD_WHALE);
        IERC20(ArbitrumLib.GUSDPT).transfer(_user, _amount);
    }

    function _deposit(address _silo, address _user, uint256 _amount) internal {
        vm.startPrank(_user);
        IERC20(ISilo(_silo).asset()).approve(_silo, _amount);
        ISilo(_silo).deposit(_amount, _user);
        vm.stopPrank();
    }

    function _getHookAddress(ISiloConfig _siloConfig) internal view returns (address hook) {
        (address silo, ) = _siloConfig.getSilos();
        hook = _siloConfig.getConfig(silo).hookReceiver;
    } 
    function _getDebtBalance(address _borrower) internal view returns (uint256) {
        (address gusdptSilo, address usdcSilo) = siloConfig.getSilos();
        (address debtToken, ) = siloConfig.getDebtShareTokenAndAsset(usdcSilo);
        return IERC20(debtToken).balanceOf(_borrower);
    }
}

interface IShareDebtToken {
    function setReceiveApproval(address _spender, uint256 _amount) external;
}
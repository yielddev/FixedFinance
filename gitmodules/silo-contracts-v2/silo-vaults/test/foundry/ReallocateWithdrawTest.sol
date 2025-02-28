// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {MarketAllocation} from "../../contracts/interfaces/ISiloVault.sol";
import {EventsLib} from "../../contracts/libraries/EventsLib.sol";
import {ErrorsLib} from "../../contracts/libraries/ErrorsLib.sol";

import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";
import {MAX_TEST_ASSETS} from "./helpers/BaseTest.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

/*
 FOUNDRY_PROFILE=vaults-tests forge test --ffi --mc ReallocateWithdrawTest -vvv
*/
contract ReallocateWithdrawTest is IntegrationTest {
    MarketAllocation[] internal allocations;

    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP2);
        _setCap(allMarkets[1], CAP2);
        _setCap(allMarkets[2], CAP2);

        _sortSupplyQueueIdleLast();

        vm.prank(SUPPLIER);
        vault.deposit(INITIAL_DEPOSIT, ONBEHALF);
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt testReallocateWithdrawMax -vvv
    */
    function testReallocateWithdrawMax() public {
        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 0));
        allocations.push(MarketAllocation(idleMarket, type(uint256).max));

        vm.expectEmit();

        emit EventsLib.ReallocateWithdraw(
            ALLOCATOR, allMarkets[0], CAP2, allMarkets[0].balanceOf(address(vault))
        );
        emit EventsLib.ReallocateWithdraw(
            ALLOCATOR, allMarkets[1], CAP2, allMarkets[1].balanceOf(address(vault))
        );
        emit EventsLib.ReallocateWithdraw(
            ALLOCATOR, allMarkets[2], CAP2, allMarkets[2].balanceOf(address(vault))
        );

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].balanceOf(address(vault)), 0, "morpho.supplyShares(0)");
        assertEq(allMarkets[1].balanceOf(address(vault)), 0, "morpho.supplyShares(1)");
        assertEq(allMarkets[2].balanceOf(address(vault)), 0, "morpho.supplyShares(2)");
        assertEq(_idle(), INITIAL_DEPOSIT, "idle");
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt testReallocateWithdrawMarketNotEnabled -vvv
    */
    function testReallocateWithdrawMarketNotEnabled() public {
        MintableToken loanToken2 = new MintableToken(18);
        loanToken2.setOnDemand(true);

        allMarkets[0] = _createNewMarket(address(collateralToken), address(loanToken2));

        vm.startPrank(SUPPLIER);
        allMarkets[0].deposit(1, address(vault));
        vm.stopPrank();

        allocations.push(MarketAllocation(allMarkets[0], 0));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MarketNotEnabled.selector, allMarkets[0]));
        vault.reallocate(allocations);
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt testReallocateWithdrawSupply -vvv
    */
    function testReallocateWithdrawSupply(uint256[3] memory newAssets) public {
        uint256[3] memory totalSupplyAssets;
        uint256[3] memory totalSupplyShares;
        (totalSupplyAssets[0], totalSupplyShares[0]) = _expectedMarketBalances(allMarkets[0]);
        (totalSupplyAssets[1], totalSupplyShares[1]) = _expectedMarketBalances(allMarkets[1]);
        (totalSupplyAssets[2], totalSupplyShares[2]) = _expectedMarketBalances(allMarkets[2]);

        newAssets[0] = bound(newAssets[0], 0, CAP2);
        newAssets[1] = bound(newAssets[1], 0, CAP2);
        newAssets[2] = bound(newAssets[2], 0, CAP2);

        uint256[3] memory assets;
        assets[0] = _expectedSupplyAssets(allMarkets[0], address(vault));
        assets[1] = _expectedSupplyAssets(allMarkets[1], address(vault));
        assets[2] = _expectedSupplyAssets(allMarkets[2], address(vault));

        allocations.push(MarketAllocation(idleMarket, 0));
        allocations.push(MarketAllocation(allMarkets[0], newAssets[0]));
        allocations.push(MarketAllocation(allMarkets[1], newAssets[1]));
        allocations.push(MarketAllocation(allMarkets[2], newAssets[2]));
        allocations.push(MarketAllocation(idleMarket, type(uint256).max));

        uint256 expectedIdle = _idle() + 3 * CAP2 - newAssets[0] - newAssets[1] - newAssets[2];

        emit EventsLib.ReallocateWithdraw(ALLOCATOR, idleMarket, 0, 0);

        if (newAssets[0] < assets[0]) emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[0], 0, 0);
        else if (newAssets[0] > assets[0]) emit EventsLib.ReallocateSupply(ALLOCATOR, allMarkets[0], 0, 0);

        if (newAssets[1] < assets[1]) emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[1], 0, 0);
        else if (newAssets[1] > assets[1]) emit EventsLib.ReallocateSupply(ALLOCATOR, allMarkets[1], 0, 0);

        if (newAssets[2] < assets[2]) emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[2], 0, 0);
        else if (newAssets[2] > assets[2]) emit EventsLib.ReallocateSupply(ALLOCATOR, allMarkets[2], 0, 0);

        emit EventsLib.ReallocateSupply(ALLOCATOR, idleMarket, 0, 0);

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(
            allMarkets[0].balanceOf(address(vault)),
            newAssets[0] * SiloMathLib._DECIMALS_OFFSET_POW,
            "morpho.supplyShares(0)"
        );
        assertApproxEqAbs(
            allMarkets[1].balanceOf(address(vault)),
            newAssets[1] * SiloMathLib._DECIMALS_OFFSET_POW,
            SiloMathLib._DECIMALS_OFFSET_POW,
            "morpho.supplyShares(1)"
        );
        assertEq(
            allMarkets[2].balanceOf(address(vault)),
            newAssets[2] * SiloMathLib._DECIMALS_OFFSET_POW,
            "morpho.supplyShares(2)"
        );
        assertApproxEqAbs(_idle(), expectedIdle, 1, "idle");
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt testReallocateWithdrawIncreaseSupply -vvv
    */
    function testReallocateWithdrawIncreaseSupply() public {
        _setCap(allMarkets[2], 3 * CAP2);

        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 3 * CAP2));

        vm.expectEmit();
        emit EventsLib.ReallocateWithdraw(
            ALLOCATOR, allMarkets[0], CAP2, allMarkets[0].balanceOf(address(vault))
        );
        emit EventsLib.ReallocateWithdraw(
            ALLOCATOR, allMarkets[1], CAP2, allMarkets[1].balanceOf(address(vault))
        );
        emit EventsLib.ReallocateSupply(
            ALLOCATOR, allMarkets[2], 3 * CAP2, 3 * allMarkets[2].balanceOf(address(vault))
        );

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].balanceOf(address(vault)), 0, "morpho.supplyShares(0)");
        assertEq(allMarkets[1].balanceOf(address(vault)), 0, "morpho.supplyShares(1)");
        assertEq(
            allMarkets[2].balanceOf(address(vault)),
            3 * CAP2 * SiloMathLib._DECIMALS_OFFSET_POW,
            "morpho.supplyShares(2)"
        );
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt testReallocateUnauthorizedMarket -vvv
    */
    function testReallocateUnauthorizedMarket(uint256[3] memory suppliedAssets) public {
        suppliedAssets[0] = bound(suppliedAssets[0], 1, CAP2);
        suppliedAssets[1] = bound(suppliedAssets[1], 1, CAP2);
        suppliedAssets[2] = bound(suppliedAssets[2], 1, CAP2);

        _setCap(allMarkets[1], 0);

        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 0));

        allocations.push(MarketAllocation(allMarkets[0], suppliedAssets[0]));
        allocations.push(MarketAllocation(allMarkets[1], suppliedAssets[1]));
        allocations.push(MarketAllocation(allMarkets[2], suppliedAssets[2]));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.UnauthorizedMarket.selector, allMarkets[1]));
        vault.reallocate(allocations);
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt testReallocateSupplyCapExceeded -vvv
    */
    function testReallocateSupplyCapExceeded() public {
        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 0));

        allocations.push(MarketAllocation(allMarkets[0], CAP2 + 1));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.SupplyCapExceeded.selector, allMarkets[0]));
        vault.reallocate(allocations);
    }

    /*
     FOUNDRY_PROFILE=vaults-tests forge test --ffi --mt testReallocateInconsistentReallocation -vvv
    */
    function testReallocateInconsistentReallocation(uint256 rewards) public {
        rewards = bound(rewards, 1, MAX_TEST_ASSETS);

        _setCap(allMarkets[0], type(uint184).max);

        allocations.push(MarketAllocation(idleMarket, 0));
        allocations.push(MarketAllocation(allMarkets[0], 2 * CAP2 + rewards));

        vm.prank(ALLOCATOR);
        vm.expectRevert(ErrorsLib.InconsistentReallocation.selector);
        vault.reallocate(allocations);
    }

    /// Returns the expected market balances of a market after having accrued interest.
    function _expectedMarketBalances(IERC4626 _market)
        internal
        view
        returns (uint256 totalSupplyAssets, uint256 totalSupplyShares)
    {
        totalSupplyAssets = _market.totalAssets();
        totalSupplyShares = _market.totalSupply();
    }
}

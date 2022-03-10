// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePool, FusePoolFactory} from "../FusePoolFactory.sol";

// TODO: I should not have to import ERC20 from here.
import {ERC20} from "solmate-next/utils/SafeTransferLib.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {Authority} from "solmate-next/auth/Auth.sol";
import {DSTest} from "ds-test/test.sol";

import {PriceOracle} from "../interface/PriceOracle.sol";
import {InterestRateModel} from "../interface/InterestRateModel.sol";
import {FlashBorrower} from "../interface/FlashBorrower.sol";

import {MockERC20} from "solmate-next/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {MockFlashBorrower} from "./mocks/MockFlashBorrower.sol";
import {MockInterestRateModel} from "./mocks/MockInterestRateModel.sol";

import "forge-std/console.sol";

/// @title Fuse Pool Factory Test Contract
contract FusePoolTest is DSTestPlus {
    /* Fuse Pool Contracts */
    FusePoolFactory factory;
    FusePool pool;

    /* Mocks */
    MockERC20 asset;
    MockERC4626 vault;
    MockPriceOracle oracle;
    MockFlashBorrower flashBorrower;
    MockInterestRateModel interestRateModel;

    function setUp() public {
        factory = new FusePoolFactory(address(this), Authority(address(0)));
        (pool, ) = factory.deployFusePool("Fuse Pool Test");

        asset = new MockERC20("Test Token", "TEST", 18);
        vault = new MockERC4626(ERC20(asset), "Test Token Vault", "TEST");
        pool.configureAsset(asset, vault, FusePool.Configuration(0, 0));

        pool.setInterestRateModel(asset, InterestRateModel(address(new MockInterestRateModel())));

        oracle = new MockPriceOracle();
        oracle.updatePrice(ERC20(asset), 1e18);
        pool.setOracle(PriceOracle(address(oracle)));
    }

    function testAddAsset() public {}

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeposit(uint256 amount) public {
        amount = bound(amount, 1e5, 1e27);

        // Mint, approve, and deposit the asset.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, false);

        // Checks. Note that the default exchange rate is 1,
        // so the values should be equal to the input amount.
        assertEq(pool.balanceOf(asset, address(this)), amount, "Incorrect Balance");
        assertEq(pool.totalUnderlying(asset), amount, "Incorrect Total Underlying");
    }

    function testWithdrawal(uint256 amount) public {
        amount = bound(amount, 1e5, 1e27);

        // Mint, approve, and deposit the asset.
        testDeposit(amount);

        // Withdraw the asset.
        pool.withdraw(asset, amount, false);

        // Checks.
        assertEq(asset.balanceOf(address(this)), amount, "Incorrect asset balance");
        assertEq(pool.balanceOf(asset, address(this)), 0, "Incorrect pool balance");
        assertEq(vault.balanceOf(address(pool)), 0, "Incorrect vault balance");
    }

    /*///////////////////////////////////////////////////////////////
                  DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                         BORROW/REPAYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                   BORROW/REPAYMENT SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                            FLASH LOAN TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                      FLASH LOAN SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                            LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                    LIQUIDATION SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                                 UTILS
    //////////////////////////////////////////////////////////////*/

    // Mint and approve assets.
    function mintAndApprove(MockERC20 asset, uint256 amount) internal {
        asset.mint(address(this), amount);
        asset.approve(address(pool), amount);
    }

    // Bound a value between a min and max.
    function bound(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256 result) {
        require(max >= min, "MAX_LESS_THAN_MIN");

        uint256 size = max - min;

        if (max != type(uint256).max) size++; // Make the max inclusive.
        if (size == 0) return min; // Using max would be equivalent as well.
        // Ensure max is inclusive in cases where x != 0 and max is at uint max.
        if (max == type(uint256).max && x != 0) x--; // Accounted for later.

        if (x < min) x += size * (((min - x) / size) + 1);
        result = min + ((x - min) % size);

        // Account for decrementing x to make max inclusive.
        if (max == type(uint256).max && x != 0) result++;
    }
}

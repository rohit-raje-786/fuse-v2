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

import {FixedPointMathLib} from "solmate-next/utils/FixedPointMathLib.sol";

import "forge-std/console.sol";

/// @title Fuse Pool Factory Test Contract
contract FusePoolTest is DSTestPlus {
    using FixedPointMathLib for uint256;

    /* Fuse Pool Contracts */
    FusePoolFactory factory;
    FusePool pool;

    /* Mocks */
    MockERC20 asset;
    MockERC4626 vault;

    MockERC20 borrowAsset;
    MockERC4626 borrowVault;

    MockPriceOracle oracle;
    MockFlashBorrower flashBorrower;
    MockInterestRateModel interestRateModel;

    function setUp() public {
        factory = new FusePoolFactory(address(this), Authority(address(0)));
        (pool, ) = factory.deployFusePool("Fuse Pool Test");

        asset = new MockERC20("Test Token", "TEST", 18);
        vault = new MockERC4626(ERC20(asset), "Test Token Vault", "TEST");
        interestRateModel = new MockInterestRateModel();

        pool.configureAsset(asset, vault, FusePool.Configuration(0.5e18, 0));
        pool.setInterestRateModel(asset, InterestRateModel(address(interestRateModel)));

        oracle = new MockPriceOracle();
        oracle.updatePrice(ERC20(asset), 1e18);
        pool.setOracle(PriceOracle(address(oracle)));

        borrowAsset = new MockERC20("Borrow Test Token", "TBT", 18);
        borrowVault = new MockERC4626(ERC20(borrowAsset), "Borrow Test Token Vault", "TBT");

        pool.configureAsset(borrowAsset, borrowVault, FusePool.Configuration(0, 1e18));
        pool.setInterestRateModel(borrowAsset, InterestRateModel(address(interestRateModel)));
    }

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

    function testDepositEnableCollateral() public {
        uint256 amount = 1e18;

        // Mint, approve, and deposit the asset.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Checks.
        assert(pool.enabledCollateral(address(this), asset));
    }

    function testWithdrawDisableCollateral() public {
        // Deposit and enable the asset as collateral.
        testDepositEnableCollateral();

        // Withdraw the asset and disable it as collateral.
        pool.withdraw(asset, 1e18, true);

        // Checks.
        assert(!pool.enabledCollateral(address(this), asset));
    }

    /*///////////////////////////////////////////////////////////////
                  DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function testFailDepositWithNotEnoughApproval() public {
        // Mint tokens.
        asset.mint(address(this), 1e18);

        // Approve the pool to spend half of the tokens.
        asset.approve(address(pool), 0.5e18);

        // Attempt to deposit the tokens.
        pool.deposit(asset, 1e18, false);
    }

    function testFailWithdrawWithNotEnoughBalance() public {
        // Mint tokens.
        testDeposit(1e18);

        // Attempt to withdraw the tokens.
        pool.withdraw(asset, 2e18, false);
    }

    function testFailWithdrawWithNoBalance() public {
        // Attempt to withdraw tokens.
        pool.withdraw(asset, 1e18, false);
    }

    function testFailWithNoApproval() public {
        // Attempt to deposit tokens.
        pool.deposit(asset, 1e18, false);
    }

    /*///////////////////////////////////////////////////////////////
                         BORROW/REPAYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testBorrow(uint256 amount) public {
        amount = bound(amount, 1e5, 1e27);

        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 4);
        pool.deposit(borrowAsset, amount / 4, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Borrow the asset.
        pool.borrow(borrowAsset, amount / 4);

        // Checks.
        assertEq(borrowAsset.balanceOf(address(this)), amount / 4);
        assertEq(pool.borrowBalance(borrowAsset, address(this)), amount / 4);
        assertEq(pool.totalBorrows(borrowAsset), amount / 4);
        assertEq(pool.totalUnderlying(borrowAsset), amount / 4);
    }

    function testRepay(uint256 amount) public {
        amount = bound(amount, 1e5, 1e27);

        // Borrow tokens.
        testBorrow(amount);

        // Repay the tokens.
        borrowAsset.approve(address(pool), amount / 4);
        pool.repay(borrowAsset, amount / 4);
    }

    function testInterestAccrual() public {
        uint256 amount = 1e18;

        // Warp block number to 1.
        HEVM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D).roll(block.number + 5);

        // Borrow tokens.
        testBorrow(amount);

        // Warp block number to 6.
        HEVM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D).roll(block.number + 5);

        // Calculate the expected amount (after interest).
        // The borrow rate is constant, so the interest is always 5% per block.
        // expected = borrowed * interest ^ (blockDelta)
        uint256 expected = (amount / 4).fmul(uint256(interestRateModel.getBorrowRate(0, 0, 0)).fpow(5, 1e18), 1e18);

        // Checks.
        assertEq(pool.borrowBalance(borrowAsset, address(this)), expected);
        assertEq(pool.totalBorrows(borrowAsset), expected);
        assertEq(pool.totalUnderlying(borrowAsset), expected);
        assertEq(pool.balanceOf(borrowAsset, address(this)), expected);
    }

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
    function mintAndApprove(MockERC20 underlying, uint256 amount) internal {
        underlying.mint(address(this), amount);
        underlying.approve(address(pool), amount);
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

interface HEVM {
    function roll(uint256) external;
}

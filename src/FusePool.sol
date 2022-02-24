// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePoolFactory} from "./FusePoolFactory.sol";

import {ERC4626} from "solmate-next/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate-next/auth/Auth.sol";

// TODO: Should not have to import ERC20 from here
import {ERC20, SafeTransferLib} from "solmate-next/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate-next/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate-next/utils/FixedPointMathLib.sol";

import {InterestRateModel} from "./interface/InterestRateModel.sol";
import {PriceOracle} from "./interface/PriceOracle.sol";
import {FlashBorrower} from "./interface/FlashBorrower.sol";

/// @title Fuse Pool
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Minimal, gas optimized lending market
contract FusePool is Auth {
    using SafeCastLib for uint256;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The name of the Fuse Pool.
    string public name;

    /// @notice The address of the FusePool oracle.
    PriceOracle public oracle;

    /// @notice Creates a new FusePool.
    /// @dev Retrieves the pool name from the FusePoolFactory state.
    /// This enables us to have a deterministic address that does not require
    /// the name to identify.
    constructor() Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        // Retrieve the name from the FusePoolFactory
        // and set it as the name of the FusePool.
        (name, oracle) = FusePoolFactory(msg.sender).deploymentInfo();
    }

    /*///////////////////////////////////////////////////////////////
                          ASSET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps underlying tokens to the ERC4626 Vaults where they are held.
    mapping(ERC20 => ERC4626) public vaults;

    /// @notice Maps underlying tokens to structs containing their lend/borrow factors.
    mapping(ERC20 => Asset) public configurations;

    /// @notice Maps underlying tokens to the base units that we use when interacting with them.
    /// @dev This is 10**asset.decimals().
    mapping(ERC20 => uint256) public baseUnits;

    /// @dev Asset configuration.
    struct Asset {
        /// @notice Multiplier representing the value that one can borrow against their collateral.
        /// A value of 0.5 means that the borrower can borrow up to 50% of the value of their collateral
        /// @dev Fixed point value scaled by 1e18.
        uint256 lendFactor;
        /// @notice Multiplier representing the value that one can borrow against their borrowable value.
        /// If the collateral factor of an asset is 0.8, and the borrow factor is 0.5,
        /// while the collateral factor dictates that one can borrow 80% of the value of their collateral,
        /// since the borrow factor is 0.5, the borrower can borrow up to 50% of the value of their borrowable value.
        /// Which is the equivalent of 40% of the value of their collateral.
        /// @dev Fixed point value scaled by 1e18.
        uint256 borrowFactor;
    }

    /// @notice Emitted when a new asset is added to the FusePool.
    /// @param asset The address of the underlying token.
    /// @param vault The address of the ERC4626 vault where the underlying token is held.
    event AssetAdded(ERC20 indexed asset, ERC4626 indexed vault);

    /// @notice Adds a new asset to the FusePool.
    /// @param asset The address of the underlying token.
    /// @param vault The address of the ERC4626 vault where the underlying token is held.
    /// @param parameters The parameters of the asset.
    function addAsset(
        ERC20 asset,
        ERC4626 vault,
        Asset memory parameters
    ) external {
        // Set storage variables.
        vaults[asset] = vault;
        configurations[asset] = parameters;
        baseUnits[asset] = 10**asset.decimals();

        // Emit the event.
        emit AssetAdded(asset, vault);
    }

    /*///////////////////////////////////////////////////////////////
                   INTEREST RATE MODEL CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Interest Rate Model.
    InterestRateModel public interestRateModel;

    /// @notice Set the address of the IRM
    function setInterestRateModel(InterestRateModel newInterestRateModel) external {
        interestRateModel = newInterestRateModel;
    }

    /*///////////////////////////////////////////////////////////////
                       DEPOSIT/WITHDRAW INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful deposit.
    /// @param from The address that triggered the deposit.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens deposited.
    event Deposit(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Emitted after a successful withdrawal.
    /// @param from The address that triggered the withdrawal.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens withdrew.
    event Withdraw(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Deposit underlying tokens into the Fuse Pool.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens deposited.
    function deposit(
        ERC20 asset,
        uint256 amount,
        bool enable
    ) public {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Calculate the amount to store.
        uint256 shares = amount.fdiv(exchangeRate(asset), baseUnits[asset]);

        // Modify the internal balance of the sender.
        balances[asset][msg.sender] += shares;

        // TODO: Better way to describe this.
        // Add to the total supply of the internal balance token of the asset.
        totalSupplies[asset] += shares;

        // Transfer tokens from the user to the fToken contract.
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit the asset into the vault.
        ERC4626 vault = vaults[asset];
        asset.approve(address(vault), amount);
        vault.deposit(address(this), amount);

        // Enable the asset as collateral if `enable` is set to true.
        if (enable) enableAsset(asset);
    }

    /// @notice Withdraw underlying tokens from the Fuse Pool.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens withdrawn.
    function withdraw(
        ERC20 asset,
        uint256 amount,
        bool disable
    ) public {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Modify the internal balance of the sender and the total supply of the balance token.
        // This code will fail if the sender does not have a large enough balance.
        uint256 shares = amount.fdiv(exchangeRate(asset), baseUnits[asset]);
        balances[asset][msg.sender] -= shares;
        totalSupplies[asset] -= shares;

        // Withdraw tokens from the vault.
        vaults[asset].withdraw(address(this), amount);

        // Transfer tokens to the user.
        asset.safeTransfer(msg.sender, amount);

        // Disable the asset as collateral if `disable` is set to true.
        if (disable) disableAsset(asset);
    }

    /*///////////////////////////////////////////////////////////////
                      BORROW/REPAYMENT INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful borrow.
    /// @param from The address that triggered the borrow.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens borrowed.
    event Borrow(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Emitted after a successful repayment.
    /// @param from The address that triggered the repayment.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens repaid.
    event Repay(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Borrow underlying tokens from the Fuse Pool.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens to borrow.
    function borrow(ERC20 asset, uint256 amount) external {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Ensure the borrow is able to execute the borrow.
        require(canBorrow(asset, msg.sender, amount));

        // Calculate the amount to borrow.
        uint256 debtShares = amount.fdiv(debtExchangeRate(asset), baseUnits[asset]);

        // Modify the internal balance of the sender.
        borrowBalances[asset][msg.sender] += debtShares;

        // Transfer tokens to the borrower.
        asset.transfer(msg.sender, amount);
    }

    /// @notice Borrow underlying tokens from the Fuse Pool.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens to borrow.
    function repay(ERC20 asset, uint256 amount) external {}

    /*///////////////////////////////////////////////////////////////
                          FLASHLOAN INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a Flash Loan is executed.
    event FlashLoan(address indexed from, address indexed borrower, ERC20 indexed asset, uint256 amount);

    /// @notice Execute a Flash Loan.
    function flashLoan(
        FlashBorrower borrower,
        bytes memory data,
        ERC20 asset,
        uint256 amount
    ) external {
        // TODO: gas optimizations.

        // Store the current vault balance.
        uint256 balance = vaults[asset].balanceOfUnderlying(address(this));

        // Withdraw the amount from the FusePool and transfer it to the borrower.
        vaults[asset].withdraw(address(borrower), amount);

        // Emit the event.
        emit FlashLoan(msg.sender, address(borrower), asset, amount);

        // Call the execute function on the borrower.
        borrower.execute(amount, data);

        // Ensure the sufficient amount has been returned.
        require(vaults[asset].balanceOfUnderlying(address(this)) >= balance, "AMOUNT_NOT_RETURNED");

        // Emit the event.
        emit FlashLoan(msg.sender, address(borrower), asset, amount);
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal accounting mechanism.
    /// Maps ERC20 tokens to a map of internal balances.
    /// One internal token is not equivalent to one underlying token.
    mapping(ERC20 => mapping(address => uint256)) internal balances;

    /// @dev Maps underlying tokens to a number representing the amount of internal tokens
    /// used to represent user balances.
    /// Equivalent to fToken.totalSupply().
    mapping(ERC20 => uint256) internal totalSupplies;

    /// @notice Returns the underlying balance of a specified user.
    /// @param asset The address of the underlying token.
    /// @param user The address of the user.
    function balanceOfUnderlying(ERC20 asset, address user) public view returns (uint256) {
        return balances[asset][user].fmul(exchangeRate(asset), baseUnits[asset]);
    }

    /// @notice Returns the total amount of underlying tokens held by the Fuse Pool.
    /// @param asset The address of the underlying token.
    function totalUnderlying(ERC20 asset) public view returns (uint256) {
        // TODO: Add other methods to account for funds not in the contract.

        // Retrive the total amount of underlying held in the asset vault.
        return vaults[asset].balanceOfUnderlying(address(this));
    }

    /// @dev Returns an exchange rate between underlying tokens and
    /// the Fuse Pools internal balance values.
    function exchangeRate(ERC20 asset) internal view returns (uint256) {
        // Retrieve the totalSupply of the internal balance token.
        uint256 supply = totalSupplies[asset];

        // If the totaly supply is 0, return 0.
        if (supply == 0) return baseUnits[asset];

        // Return the exchangeRate.
        return totalUnderlying(asset).fdiv(supply, baseUnits[asset]);
    }

    /// @notice Returns the total amount of available underlying in the contract.
    /// @param asset The address of the underlying token.
    function availableLiquidity(ERC20 asset) public view returns (uint256) {
        // Retrieve the totalSupply of the internal balance token.
        return vaults[asset].balanceOfUnderlying(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                        INTEREST ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Store the block number of the last interest accrual for each asset.
    mapping(ERC20 => uint256) internal lastInterestAccrual;

    /// @dev Accrue interest for a certain asset.
    /// Calling this function will increase value returned by
    /// totalBorrows() for that asset.
    function accrueInterest(ERC20 asset) internal {
        // TODO: OPTIMIZE
        // Ensure the IRM has been set.
        require(address(interestRateModel) != address(0), "INTEREST_RATE_MODEL_NOT_SET");

        // Retrieve the per-block interest rate from the IRM.
        uint256 interestRate = interestRateModel.getBorrowRate(totalUnderlying(asset), cachedTotalBorrows[asset], 0);

        // Calculate the block number delta between the last accrual and the current block.
        uint256 blockDelta = block.number - lastInterestAccrual[asset];

        // Calculate the interest accumulator.
        uint256 interestAccumulator = interestRate.fpow(blockDelta, 1e18);

        // Accrue interest.
        cachedTotalBorrows[asset] = cachedTotalBorrows[asset].fmul(interestAccumulator, 1e18);
    }

    /*///////////////////////////////////////////////////////////////
                       COLLATERALIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO: rename this
    // assets in the array/that are set to true are not always being used as collateral
    // and are potentially just being borrowed.

    /// @notice Maps addresses to an array of assets they have listed as collateral.
    /// If a user is borrowing an asset, it will also be part of this array.
    mapping(address => ERC20[]) public userCollateral;

    /// @notice Maps users to a map indicating whether they have listed
    /// the asset as collateral.
    /// If a user is borrowing an asset, it will also be set to true.
    mapping(address => mapping(ERC20 => bool)) public enabledCollateral;

    /// @notice Enable an asset as collateral for a user.
    /// @param asset The address of the underlying token.
    function enableAsset(ERC20 asset) public {
        // Ensure that the asset is currently disabled as collateral.
        if (enabledCollateral[msg.sender][asset]) return;

        // Enable the asset as collateral for the user.
        userCollateral[msg.sender].push(asset);
        enabledCollateral[msg.sender][asset] = true;
    }

    // TODO: optimize
    /// @notice Disable an asset as collateral for a user.
    /// @param asset The address of the underlying token.
    function disableAsset(ERC20 asset) public {
        // Ensure that the user is not borrowing this asset.
        // We do not want this code to fail, as it may be called
        // in withdrawals.
        if (borrowBalances[asset][msg.sender] > 0) return;

        // Remove the asset from the user's list of collateral.
        for (uint256 i = 0; i < userCollateral[msg.sender].length; i++) {
            if (userCollateral[msg.sender][i] == asset) {
                // Copy the value of the last element in the array.
                ERC20 last = userCollateral[msg.sender][userCollateral[msg.sender].length - 1];

                // Remove the last element from the array.
                delete userCollateral[msg.sender][userCollateral[msg.sender].length - 1];

                // Replace the disabled asset with the new asset.
                userCollateral[msg.sender][i] = last;
            }
        }

        // Disbale asset.
        enabledCollateral[msg.sender][asset] = false;
    }

    /*///////////////////////////////////////////////////////////////
                  INTERNAL BORROW/REPAYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps assets to a cached total borrow amount.
    /// These values are only changed on borrows and repayments.
    mapping(ERC20 => uint256) public cachedTotalBorrows;

    /// @dev Internal accounting mechanism for debt.
    /// Maps ERC20 tokens to a map of internal borrow balances.
    /// One internal unit of debt is not equivalent to one underlying token.
    mapping(ERC20 => mapping(address => uint256)) internal borrowBalances;

    /// @dev Maps underlying tokens to a number representing the amount of internal tokens
    /// used to represent user debt.
    mapping(ERC20 => uint256) internal totalInternalDebt;

    /// @dev Store account liquidity details whilst avoiding stack depth errors.
    struct AccountLiquidity {
        // A user's total borrow balance in ETH.
        uint256 borrowBalance;
        // A user's maximum borrowable value. If their borrowed value
        // reaches this point, they will get liquidated.
        uint256 maximumBorrowawble;
        // A user's borrow balance in ETH multiplied by the average borrow factor.
        // TODO: need a better name for this
        uint256 borrowBalancesTimesBorrowFactors;
        // A user's actual borrowable value. If their borrowed value
        // is greater than or equal to this number, the system will
        // not allow them to borrow any more assets.
        uint256 actualBorrowable;
    }

    /// @notice Returns the underlying borrow balance of a specified user.
    /// @param asset The address of the underlying token.
    /// @param user The address of the borrower.
    function borrowBalance(ERC20 asset, address user) public view returns (uint256) {
        // TODO: add logic to account for interest.
        return borrowBalances[asset][user];
    }

    /// @dev Returns an exchange rate between underlying tokens and
    /// the Fuse Pools internal unit of debt.
    /// @param asset The address of the underlying token.
    function debtExchangeRate(ERC20 asset) internal view returns (uint256) {
        // TODO: total supply is stored in totalInternalDebt.
        // To calculate total borrows, we need to do totalUnderlying() - availableLiquidity().

        // Retrieve the totalSupply of the internal debt units.
        uint256 internalDebtSupply = totalInternalDebt[asset];

        // If the totaly supply is 0, return 1.
        if (internalDebtSupply == 0) return baseUnits[asset];

        // Otherwise return the exchangeRate.
        // This is calculated by doing (totalUnderlying() - availableLiquidity())/internalDebtSupply.
        return (totalUnderlying(asset) - availableLiquidity(asset)).fdiv(internalDebtSupply, baseUnits[asset]);
    }

    /// @dev Evaluate whether a user is able to execute a borrow.
    /// @param asset The address of the underlying token.
    /// @param user The address of the borrower.
    /// @param amount The amount of underlying tokens to borrow.
    function canBorrow(
        ERC20 asset,
        address user,
        uint256 amount
    ) internal view returns (bool) {
        // TODO: OPTIMIZE + CLEANUP

        // Allocate memory to store the user's account liquidity.
        AccountLiquidity memory liquidity;

        // Retrieve the user's utilized assets.
        ERC20[] memory utilized = userCollateral[user];

        // Iterate through the user's utilized assets.
        for (uint256 i = 0; i < utilized.length; i++) {
            // Calculate the user's maximum borrowable value for this asset.
            // balanceOfUnderlying(asset,user) * ethPrice * collateralFactor.
            liquidity.maximumBorrowawble += balanceOfUnderlying(utilized[i], user)
                .fmul(oracle.getUnderlyingPrice(utilized[i]), baseUnits[utilized[i]])
                .fmul(configurations[utilized[i]].lendFactor, 1e18);

            // Calculate the user's hypothetical borrow balance for this asset.
            uint256 hypotheticalBorrowBalance = utilized[i] == asset
                ? borrowBalance(utilized[i], user) + amount
                : borrowBalance(utilized[i], user);

            // Add the user's borrow balance in this asset to their total borrow balance.
            liquidity.borrowBalance += hypotheticalBorrowBalance.fmul(
                oracle.getUnderlyingPrice(utilized[i]),
                baseUnits[utilized[i]]
            );

            // Multiply the user's borrow balance in this asset by the borrow factor.
            liquidity.borrowBalancesTimesBorrowFactors += hypotheticalBorrowBalance
                .fmul(oracle.getUnderlyingPrice(utilized[i]), baseUnits[utilized[i]])
                .fmul(configurations[utilized[i]].borrowFactor, 1e18);
        }

        // Calculate the user's actual borrowable value.
        uint256 actualBorrowable = liquidity.borrowBalancesTimesBorrowFactors.fdiv(liquidity.borrowBalance, 1e18).fmul(
            liquidity.maximumBorrowawble,
            1e18
        );

        // Return whether the user's hypothetical borrow value is
        // less than or equal to their borrowable value.
        return liquidity.borrowBalance <= actualBorrowable;
    }
}

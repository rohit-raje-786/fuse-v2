// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC4626} from "solmate-next/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate-next/auth/Auth.sol";

// TODO: Should not have to import ERC20 from here
import {ERC20, SafeTransferLib} from "solmate-next/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate-next/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate-next/utils/FixedPointMathLib.sol";

import {FusePoolFactory} from "./FusePoolFactory.sol";
import {IFlashBorrower} from "./interface/IFlashBorrower.sol";

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

    /// @notice Creates a new FusePool.
    /// @dev Retrieves the pool name from the FusePoolFactory state.
    /// This enables us to have a deterministic address that does not require
    /// the name to identify.
    constructor() Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        // Retrieve the name from the FusePoolFactory
        // and set it as the name of the FusePool.
        name = FusePoolFactory(msg.sender).poolDeploymentName();
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
    function deposit(ERC20 asset, uint256 amount) public {
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
    }

    /// @notice Withdraw underlying tokens from the Fuse Pool.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens withdrawn.
    function withdraw(ERC20 asset, uint256 amount) public {
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
        IFlashBorrower borrower,
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
                  INTERNAL BORROW/REPAYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal accounting mechanism for debt.
    /// Maps ERC20 tokens to a map of internal borrow balances.
    /// One internal unit of debt is not equivalent to one underlying token.
    mapping(ERC20 => mapping(address => uint256)) internal borrowBalances;

    /// @dev Maps underlying tokens to a number representing the amount of internal tokens
    /// used to represent user debt.
    mapping(ERC20 => uint256) internal totalBorrows;

    /// @notice Returns the underlying borrow balance of a specified user.
    /// @param asset The address of the underlying token.
    /// @param user The address of the borrower.
    function borrowBalance(ERC20 asset, address user) public view returns (uint256) {
        // TODO: add logic to account for interest.
        return borrowBalances[asset][user];
    }

    /// @dev Returns an exchange rate between underlying tokens and
    /// the Fuse Pools internal balance values.
    /// @param asset The address of the underlying token.
    function debtExchangeRate(ERC20 asset) internal view returns (uint256) {
        // Retrieve the totalSupply of the internal balance token.
        uint256 supply = totalSupplies[asset];

        // If the totaly supply is 0, return 0.
        if (supply == 0) return baseUnits[asset];

        // Return the exchangeRate.
        return totalUnderlying(asset).fdiv(supply, baseUnits[asset]);
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
        // Borrow Balance
    }
}

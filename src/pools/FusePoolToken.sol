// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth} from "lib/solmate/src/auth/Auth.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

import {SafeCastLib} from "lib/solmate/src/utils/SafeCastLib.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {IRateModel} from "./interfaces/IRateModel.sol";
import {FusePoolManager} from "./FusePoolManager.sol";

/// @title Fuse Pool Token (fToken)
/// @author Jet Jadeja <jet@rari.capital>
/// @notice ERC20 compatible representation of balances supplied to a Fuse Pool.
contract FusePoolToken is ERC20, Auth {
    using SafeCastLib for uint256;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the FusePoolManager contract.
    FusePoolManager public immutable MANAGER;

    /// @notice The underlying token contract address supported by the fToken.
    ERC20 public immutable UNDERLYING;

    /// @notice The base unit of the underlying token.
    /// @dev Equivalent to 10 ** decimals (used for fixed point math).
    uint256 public immutable BASE_UNIT;

    /// @notice Create a new Fuse Pool Token.
    /// @param underlying The address of the underlying ERC20 token.
    constructor(ERC20 underlying)
        ERC20(
            string(abi.encodePacked(FusePoolManager(msg.sender).name(), underlying.name())),
            string(abi.encodePacked(FusePoolManager(msg.sender).symbol(), underlying.symbol())),
            underlying.decimals()
        )
        Auth(Auth(address(msg.sender)).owner(), Auth(address(msg.sender)).authority())
    {
        // Set immutables.
        MANAGER = FusePoolManager(msg.sender);
        UNDERLYING = underlying;
        BASE_UNIT = 10**decimals;

        // Prevent minting of fTokens by setting supply to 2^256 - 1.
        // If any tokens are minted, an overflow will occur.
        totalSupply = type(uint256).max;
    }

    /*///////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Boolean indicating whether the fToken has been initialized.
    bool isInitalized;

    /// @notice Initialize the fToken.
    /// @dev This method does not require auth as it should
    /// be called in the same call as the constructor.
    function initialize(
        IRateModel _rateModel,
        uint256 _reserveRate,
        uint256 _feeRate
    ) external {
        require(!isInitalized, "fToken is already initialized.");

        rateModel = _rateModel;
        reserveRate = _reserveRate;
        feeRate = _feeRate;

        totalSupply = 0;
        isInitalized = true;
    }

    /*///////////////////////////////////////////////////////////////
                        RATE MODEL CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    /// @notice The address of the RateModel contract.
    /// @dev The Rate Model is used to calculate supply/borrow rates.
    IRateModel public rateModel;

    /// @notice Emmited when the Rate Model is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newRateModel The address of the new Rate Model.
    event RateModelUpdated(address indexed user, IRateModel indexed newRateModel);

    /// @notice Set a new Rate Model.
    /// @param newRateModel The address of the new Rate Model.
    function setNewRateModel(IRateModel newRateModel) external requiresAuth {
        // Ensure the new Rate Model is valid.
        require(address(newRateModel) != address(0), "MODEL_NOT_VALID");

        // Set the new Rate Model.
        rateModel = newRateModel;

        // Emit the event.
        emit RateModelUpdated(msg.sender, newRateModel);
    }

    /*///////////////////////////////////////////////////////////////
                          RESERVE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The percentage of interest set aside for reserves.
    /// @dev Fixed point value scaled by 1e18.
    uint256 public reserveRate;

    /// @notice The address of the Shared Reserve contract.
    /// @dev If address is set to 0, reserves are stored in the fToken.
    address public sharedReserve;

    /// @notice Emmited when the Reserve Rate is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newReserveRate The value of the new reserveRate.
    event ReserveRateUpdated(address indexed user, uint256 newReserveRate);

    /// @notice Emmited when the Shared Reserve contract is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newSharedReserve The address of the new SharedReserve contract.
    event SharedReserveUpdated(address indexed user, address indexed newSharedReserve);

    /// @notice Set a new Reserve Rate.
    /// @param newReserveRate The value of the new reserveRate.
    function setNewReserveRate(uint256 newReserveRate) external requiresAuth {
        // A reserve rate above 100% is not valid.
        require(newReserveRate <= 1e18, "RATE_TOO_HIGH");

        // Set the new Reserve Rate.
        reserveRate = newReserveRate;

        // Emit the event.
        emit ReserveRateUpdated(msg.sender, newReserveRate);
    }

    /// @notice Set a new Shared Reserve Contract.
    /// @param newSharedReserve The address of the new shared reserve contract.
    function setNewSharedReserve(address newSharedReserve) external requiresAuth {
        // Set the new Reserve Rate.
        sharedReserve = newSharedReserve;

        // Emit the event.
        emit SharedReserveUpdated(msg.sender, newSharedReserve);
    }

    /*///////////////////////////////////////////////////////////////
                        FEE RATE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The percentage of interest set aside for fees.
    /// @dev Fixed point value scaled by 1e18.
    uint256 public feeRate;

    /// @notice Emitted when the Fee Rate is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newFeeRate The value of the new feeRate.
    event FeeRateUpdated(address indexed user, uint256 newFeeRate);

    /// @notice Set a new fee rate value.
    /// @param newFeeRate The value of the new feeRate.
    function setNewSharedReserve(uint256 newFeeRate) external requiresAuth {
        // A fee rate above 100% is not valid.
        require(newFeeRate <= 1e18, "RATE_TOO_HIGH");

        // Set the new Fee Rate.
        feeRate = newFeeRate;

        // Emit the event.
        emit FeeRateUpdated(msg.sender, newFeeRate);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful deposit.
    /// @param user The user who deposited.
    /// @param amount The amount of underlying tokens deposited.
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted after a successful withdrawal.
    /// @param user The user who withdrew.
    /// @param amount The amount of underlying tokens withdrew.
    event Withdrawal(address indexed user, uint256 amount);

    /// @notice Deposit a specific amount of underlying tokens.
    /// @param underlyingAmount The amount of underlying tokens withdrawn.
    function deposit(uint256 underlyingAmount) external {
        // Ensure the amount is valid.
        require(underlyingAmount > 0, "AMOUNT_TOO_LOW");

        // Mint fTokens to the user.
        _mint(msg.sender, underlyingAmount.fdiv(exchangeRate(), BASE_UNIT));

        // Transfer tokens from the user to the fToken contract.
        UNDERLYING.safeTransferFrom(msg.sender, address(this), underlyingAmount);
    }

    /// @notice Withdraw a specific amount of underlying tokens.
    /// @param underlyingAmount The amount of underlying tokens withdrawn.
    function withdraw(uint256 underlyingAmount) external {
        // Ensure the amount is valid.
        require(underlyingAmount > 0, "AMOUNT_TOO_LOW");

        // Burn fTokens the equivalent amount of fTokens.
        // This code will fail if the user does not have enough fTokens.
        _burn(msg.sender, underlyingAmount.fdiv(exchangeRate(), BASE_UNIT));

        // Transfer tokens from the fToken contract to the user.
        UNDERLYING.safeTransfer(msg.sender, underlyingAmount);
    }

    /// @notice Redeem a specific amount of fTokens for underlying tokens.
    /// @param fTokenAmount The amount of fTokens redeemed.
    function redeem(uint256 fTokenAmount) external {
        // Ensure the amount is valid.
        require(fTokenAmount > 0, "AMOUNT_TOO_LOW");

        // Determine the equivalent amount of underlying tokens.
        // TODO: Add exchangeRate calculation.
        uint256 underlyingAmount = fTokenAmount;

        // Burn fTokens the equivalent amount of fTokens.
        // This code will fail if the user does not have enough fTokens.
        _burn(msg.sender, fTokenAmount.fmul(exchangeRate(), BASE_UNIT));

        // Transfer tokens from the fToken contract to the user.
        UNDERLYING.safeTransfer(msg.sender, underlyingAmount);
    }

    /*///////////////////////////////////////////////////////////////
                            BORROW/REPAY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful borrow.
    /// @param user The user who borrowed the underlying asset.
    /// @param asset The address of the fToken holding the borrowed asset.
    /// @param amount The amount of underlying tokens borrowed.
    event Borrow(address indexed user, FusePoolToken indexed asset, uint256 amount);

    /// @notice Emitted after a successful repayment
    /// @param user The user who repaid the underlying asset.
    /// @param asset The address of the fToken holding the repaid asset.
    /// @param amount The amount of underlying tokens repaid.
    event Repay(address indexed user, FusePoolToken indexed asset, uint256 amount);

    /// @notice Borrow a specific amount of underlying tokens.
    /// @param poolToken The address of the FusePoolToken contract
    /// that holds the underlying asset to be borrowed.
    /// @param amount The amount of underlying tokens to borrow.
    function borrow(FusePoolToken poolToken, uint256 amount) external {
        // Ensure the inputted values are valid.
        require(amount > 0, "AMOUNT_TOO_LOW");
        require(address(poolToken) != address(0), "POOL_TOKEN_NOT_VALID");

        // Facilitate a borrow through the manager.
        // This call will fail if the borrower does not have enough collateral
        // MANAGER.borrow(msg.sender, amount, balanceOf(msg.sender));

        // Emit the event.
        emit Borrow(msg.sender, poolToken, amount);
    }

    /// @notice Repay a specific amount of underlying tokens.
    /// @param poolToken The address of the FusePoolToken contract
    /// that holds the underlying asset to be repaid.
    /// @param amount The amount of underlying tokens to repay.
    function repay(FusePoolToken poolToken, uint256 amount) public {
        // Ensure the inputted values are valid.
        require(amount > 0, "AMOUNT_TOO_LOW");
        require(address(poolToken) != address(0), "POOL_TOKEN_NOT_VALID");

        // Facilitate a repayment through the manager.
        // This call will fail if the borrower does not have enough collateral
        // MANAGER.repay(msg.sender, amount, balanceOf(msg.sender));

        // Emit the event.
        emit Repay(msg.sender, poolToken, amount);
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the exchange rate between fTokens and underlying tokens.
    /// This value also represents the amount of underlying that one fToken can be redeemed for.
    function exchangeRate() public view returns (uint256) {
        // Retrieve the total supply of fTokens.
        uint256 supply = totalSupply;

        // If the totalSupply is 0, return a default exchange rate of 1.
        if (totalSupply == 0) return BASE_UNIT;

        // Return the exchange rate.
        return totalHoldings().fdiv(supply, BASE_UNIT);
    }

    /// @notice Calculates the total amoung of underlying tokens controlled by this contract.
    function totalHoldings() public view returns (uint256) {
        // TODO: Actually calculate this value.
        return UNDERLYING.balanceOf(address(this));
    }

    /// @notice Get the underlying balance of an account
    /// @param account The account to get the balance of.
    function balanceOfUnderlying(address account) public view returns (uint256) {
        return balanceOf[account].fmul(exchangeRate(), BASE_UNIT);
    }
}

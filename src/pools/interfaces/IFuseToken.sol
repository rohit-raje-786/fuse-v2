// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

/// @notice Fuse Token Interface
/// @author Jet Jadeja
interface IFuseToken {

    /*///////////////////////////////////////////////////////////////
                            USER INTERFACE
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount) external;
    function withdraw(uint256 redeemTokens) external returns (uint256);
    function redeem(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);

    function liquidateBorrow(address borrower, uint repayAmount, IFuseToken collateral) external returns (uint);

    /*///////////////////////////////////////////////////////////////
                           ACCOUNTING INTERFACE
    //////////////////////////////////////////////////////////////*/
    
    function balanceOfUnderlying(address owner) external view returns (uint256);
    function exchangeRate() external view returns (uint256);
    function totalHoldings() external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                            ADMIN INTERFACE
    //////////////////////////////////////////////////////////////*/
    
    function setPoolController(address) external;
    function sharedReserve(address) external;
    function setReserveFactor(uint256) external;
    function setInterestRateModel(address) external;
}
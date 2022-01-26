import {FusePool, ERC20} from "../../FusePool.sol";

/// @title Mock Flash Borrower
/// @dev A test implementation of the FlashBorrower contract.
contract MockFlashBorrower {
    /// @dev Called by the FusePool contract after a flash loan.
    function execute(uint256 amount, bytes memory data) external {
        // Retrieve the asset from the data.
        address asset = abi.decode(data, (address));

        // Deposit tokens back into the FusePool contract.
        FusePool(msg.sender).vaults(ERC20(asset)).deposit(asset, amount);
    }
}

pragma solidity 0.8.10;

import {ERC20, ERC4626} from "solmate-next/mixins/ERC4626.sol";

contract MockERC4626 is ERC4626 {
    constructor(
        ERC20 underlying,
        string memory name,
        string memory symbol
    ) ERC4626(underlying, name, symbol) {}

    function beforeWithdraw(uint256 underlyingAmount) internal override {}

    function afterDeposit(uint256 underlyingAmount) internal override {}

    function balanceOfUnderlying(address) public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

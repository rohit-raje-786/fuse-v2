import {FusePoolToken} from "../../pools/FusePoolToken.sol";
import {IPriceOracle} from "../../pools/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    /// @dev Maps fTokens to their hardcoded prices.
    mapping(FusePoolToken => uint256) public prices;

    /// @dev Modify the price of an asset.
    function modifyAssetPrice(FusePoolToken fToken, uint256 price) external {
        prices[fToken] = price;
    }

    /// @dev Get the underlying price of an asset.
    function getUnderlyingPrice(FusePoolToken fToken) external view returns (uint256) {
        return prices[fToken];
    }
}

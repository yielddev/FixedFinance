// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from  "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {DIAOracleConfig} from "./DIAOracleConfig.sol";
import {IDIAOracle} from "../interfaces/IDIAOracle.sol";
import {IDIAOracleV2} from "../external/dia/IDIAOracleV2.sol";

contract DIAOracle is ISiloOracle, IDIAOracle, Initializable {
    DIAOracleConfig public oracleConfig;

    /// @dev we accessing prices for assets by keys eg. "Jones/USD"
    /// I tried to store it as bytes32 immutable, but translation to string uses over 5K gas,
    /// reading string is less gas, because it is not immutable it is not stored in config contracts (less gas)
    mapping (DIAOracleConfig => string) public primaryKey;

    /// @dev key for secondary price
    mapping (DIAOracleConfig => string) public secondaryKey;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice validation of config is checked in factory, therefore you should not deploy and initialize directly
    /// use factory always.
    function initialize(
        DIAOracleConfig _configAddress,
        string memory _key1,
        string memory _key2
    )
        external
        virtual
        initializer
    {
        oracleConfig = _configAddress;

        primaryKey[_configAddress] = _key1;
        secondaryKey[_configAddress] = _key2;

        emit DIAConfigDeployed(_configAddress);
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken) external view virtual returns (uint256 quoteAmount) {
        DIAOracleConfig cacheOracleConfig = oracleConfig;
        DIAConfig memory data = cacheOracleConfig.getConfig();

        if (_baseToken != data.baseToken) revert AssetNotSupported();
        if (_baseAmount > type(uint128).max) revert BaseAmountOverflow();

        (
            uint128 assetPrice,
            bool priceUpToDate
        ) = getPriceForKey(data.diaOracle, primaryKey[cacheOracleConfig], data.heartbeat);

        if (!priceUpToDate) revert OldPrice();

        if (!data.convertToQuote) {
            return OracleNormalization.normalizePrice(
                _baseAmount, assetPrice, data.normalizationDivider, data.normalizationMultiplier
            );
        }

        (
            uint128 secondaryPrice, bool secondaryPriceValid
        ) = getPriceForKey(data.diaOracle, secondaryKey[cacheOracleConfig], data.heartbeat);

        if (!secondaryPriceValid) revert OldSecondaryPrice();

        return OracleNormalization.normalizePrices(
            _baseAmount,
            assetPrice,
            secondaryPrice,
            data.normalizationDivider,
            data.normalizationMultiplier,
            data.invertSecondPrice
        );
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        IDIAOracle.DIAConfig memory setup = oracleConfig.getConfig();
        return address(setup.quoteToken);
    }

    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @param _diaOracle IDIAOracleV2 oracle where price is stored
    /// @param _key string under this key asset price will be available in DIA oracle
    /// @param _heartbeat period after which price became invalid
    /// @return assetPriceInUsd uint128 asset price
    /// @return priceUpToDate bool TRUE if price is up to date (acceptable), FALSE otherwise
    function getPriceForKey(IDIAOracleV2 _diaOracle, string memory _key, uint256 _heartbeat)
        public
        view
        virtual
        returns (uint128 assetPriceInUsd, bool priceUpToDate)
    {
        uint128 priceTimestamp;
        (assetPriceInUsd, priceTimestamp) = _diaOracle.getValue(_key);
        if (priceTimestamp == 0) revert InvalidKey();

        // price must be updated at least once every 24h, otherwise something is wrong
        uint256 oldestAcceptedPriceTimestamp;
        // block.timestamp is more than HEARTBEAT, so we can not underflow
        unchecked { oldestAcceptedPriceTimestamp = block.timestamp - _heartbeat; }

        // we not checking assetPriceInUsd != 0, because this is checked on setup, so it will be always some value here
        priceUpToDate = priceTimestamp > oldestAcceptedPriceTimestamp;
    }
}

# Silo V2
Monorepository for Silo V2.

## How to deploy a Silo or implement an integration
### Prepare local environment, run the tests

```shell
# 1. Install Foundry 
# https://book.getfoundry.sh/getting-started/installation

# 2. Clone repository
$ git clone https://github.com/silo-finance/silo-contracts-v2.git

# 3. Open folder
$ cd silo-contracts-v2

# 4. Initialize submodules
$ git submodule update --init --recursive

# 5. Create the file ".env" in a root of this folder. ".env.example" is an example.
# RPC_MAINNET, RPC_ARBITRUM, RPC_ANVIL, PRIVATE_KEY are required to run the tests.
# Add your RPC URLs and private key if you are going to deploy a new Silo.

# 6. Build Silo foundry utils to prepare tools for Silo deployment and testing
$ cd ./gitmodules/silo-foundry-utils && cargo build --release && cp target/release/silo-foundry-utils ../../silo-foundry-utils && cd -

# 7. Check if tests can be executed
$ FOUNDRY_PROFILE=core-test forge test --no-match-test "_skip_" --nmc "SiloIntegrationTest|MaxBorrow|MaxLiquidationTest|MaxLiquidationBadDebt|PreviewTest|PreviewDepositTest|PreviewMintTest" --ffi -vv

# 8. You are ready to contribute to the protocol!
```

### Test new Silo deployment locally
```shell
# 1. Create a JSON with market setup, for example silo-core/deploy/input/arbitrum_one/wstETH_WETH_Silo.json.
# Any number in a config is basis points (a one hundredth of a percent). For example, `"lt0": 9600` -> lt0 == 96%.  

# 2. Execute the script to test the Silo deployment in a local fork of blockchain. Replace 'wstETH_WETH_Silo'
# with your config name.

$ FOUNDRY_PROFILE=core CONFIG=wstETH_WETH_Silo \
forge script silo-core/deploy/silo/SiloDeployWithGaugeHookReceiver.s.sol \
--ffi --rpc-url $YOUR_RPC_URL

# 3. Silo is deployed to a local blockchain fork. Check logs to verify market parameters. Green check marks
# represent basic verification of the on-chain parameters to be equal to the config parameters. 
```

### Deploy a Silo
```shell
# 1. Test your config by deploying the Silo in the local fork as described above.

$ anvil --fork-url $RPC_ARBITRUM --fork-block-number 284045200 & 

# in case of issues, deploy contracts locally, so you can retreive errors
FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/InterestRateModelV2FactoryDeploy.s.sol:InterestRateModelV2FactoryDeploy \
        --ffi --broadcast --rpc-url http://127.0.0.1:8545 
        
FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloDeployerDeploy.s.sol \
        --ffi --broadcast --rpc-url 127.0.0.1:8545
        
# 2. Execute the script to deploy a Silo. This script will sign and send real on-chain transaction. Smart
# contract will be verified on Etherscan. Standard Foundry --verifier-url parameter can be provided for other
# verification providers, including Arbiscan. 

$ FOUNDRY_PROFILE=core CONFIG=YOUR_CONFIG_NAME_WITHOUT_JSON_EXTENSION \
forge script silo-core/deploy/silo/SiloDeployWithGaugeHookReceiver.s.sol \
--ffi --broadcast --rpc-url 127.0.0.1:8545 --verify

# 3. Silo is deployed on-chain. Address is saved to silo-core/deploy/silo/_siloDeployments.json. 
# You can create a PR to merge config and deployed address to develop branch.
```

### More docs
Follow to [MOREDOCS.md](https://github.com/silo-finance/silo-contracts-v2/blob/develop/MOREDOCS.md) for more details about integration with Silo V2.

## LICENSE

The primary license for Silo V2 Core is the Business Source License 1.1 (`BUSL-1.1`), see [LICENSE](https://github.com/silo-finance/silo-contracts-v2/blob/master/LICENSE). Minus the following exceptions:

- Some libraries have a GPL license
- Hook.sol library and some of its tests have a GPL License
- Hook files in `utils/hook-receivers` have a GPL License
- Interfaces have an MIT license

Each of these files states their license type.

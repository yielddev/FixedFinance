# Silo hooks system Implementing Fixed Rate, Fixed Term Loans against Pristine Collateral

This Fixed Finance hook system implements a fixed rate, fixed term loan against pristine collateral. 
By taking GUSDC PT Tokens as collateral, borrowers can take out a loan of USDC at a fixed rate for a fixed term without the risk of liquidation based on price fluctuations. The loans are written as Repurchase agreements, with the collateral being held in a Silo Vault. The borrower account takes delivery of USDC and takes on a debt of the USDC amount + the fixed loan fee.

in order to reclaim their collateral the borrower must repurchase it for the the total debt amount before the end of the loan term.

Silo hooks manage the terms of the loan by writing the loan to a state variable before a borrow action is executed on the USDC vault. 

After the borrow action is executed the after borrow hook takes the loan fee and pays it back to the silo vault. In this way the total debt is x but the loan amount delivered is `x-fee`. The borrower must repay x in order to  'repurchase' their collateral. 

Since the PT tokens are fixed yielding assets they resolve to 1 of the underlying asset at maturity. Since the underlying (gUSD) is worth more than 1 USDC the borrower can collateralize 1 PT per 1 USDC liability. with a fixed 500 bps fee the user can access 95% liquidity(USDC delivered) of the liability amount.

The after repayment hook is used to settle the loan terms in the state variables and release a certain amount of collateral for the borrower in the event of partial repayments. If the borrower repays half of the debt, and defaults on the other half. The liquidator can repurchase half of the collateral. 

Future designs of the silos would integrate the Pendle oracle directly thus not relying on the assumption that the underlying asset is worth more than the borrowed asset. Instead the collateral value would be marked to a USDC value and the maximum loan amount would be a function of the collateral value and LTV.

Future designs would also allow for a dynamic fixed fee rate, where the effective fixed loan fee is a function of the loan term, utilization and variable rate of usdc. 

Liquidations are implement via hooks and are based on the expiration of the loan term. If the borrower has not repurchased their collateral before the end of the term. any liquidator is able to repurchase the collateral from the pool for the intiial repurchase price. In this case, the liquidator takes delivery of the collateral asset via the vault shares after paying the loans purchase price. 

Transfers for the debt token are managed via hooks to pass on the loan terms to the recipient of the debt. In the case that a debt receiver has an existing loan. the loan terms are updated to the shortest term between the sender and receiver. 

The project can be run locally on the arbitrum mainnet fork via: 


```
forge test --mc RepurchaseHook -vvv
```

### Silo V2 Hooks Quickstart

```shell
# Prepare local environment

# 1. Install Foundry 
# https://book.getfoundry.sh/getting-started/installation

# 2. Clone repository
$ git clone https://github.com/silo-finance/silo-v2-hooks-quickstart.git

# 3. Open folder
$ cd silo-v2-hooks-quickstart

# 4. Initialize submodules
$ git submodule update --init --recursive
```

### Tests
```shell
forge test
```

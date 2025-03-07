package cmd_test

import (
	"flag"
	"math/big"
	"os"
	"strconv"
	"testing"
	"time"

	clienttypes "github.com/smartcontractkit/chainlink/v2/common/chains/client"
	"github.com/smartcontractkit/chainlink/v2/core/chains/evm"
	"github.com/smartcontractkit/chainlink/v2/core/cmd"
	cmdMocks "github.com/smartcontractkit/chainlink/v2/core/cmd/mocks"
	"github.com/smartcontractkit/chainlink/v2/core/internal/cltest"
	"github.com/smartcontractkit/chainlink/v2/core/internal/cltest/heavyweight"
	"github.com/smartcontractkit/chainlink/v2/core/internal/mocks"
	"github.com/smartcontractkit/chainlink/v2/core/internal/testutils"
	configtest "github.com/smartcontractkit/chainlink/v2/core/internal/testutils/configtest/v2"
	"github.com/smartcontractkit/chainlink/v2/core/internal/testutils/evmtest"
	"github.com/smartcontractkit/chainlink/v2/core/internal/testutils/pgtest"
	"github.com/smartcontractkit/chainlink/v2/core/logger"
	"github.com/smartcontractkit/chainlink/v2/core/logger/audit"
	"github.com/smartcontractkit/chainlink/v2/core/services/chainlink"
	chainlinkmocks "github.com/smartcontractkit/chainlink/v2/core/services/chainlink/mocks"
	"github.com/smartcontractkit/chainlink/v2/core/services/pg"
	evmrelayer "github.com/smartcontractkit/chainlink/v2/core/services/relay/evm"
	"github.com/smartcontractkit/chainlink/v2/core/sessions"
	"github.com/smartcontractkit/chainlink/v2/core/store/dialects"
	"github.com/smartcontractkit/chainlink/v2/core/store/models"
	"github.com/smartcontractkit/chainlink/v2/core/utils"
	"github.com/smartcontractkit/chainlink/v2/plugins"

	gethTypes "github.com/ethereum/go-ethereum/core/types"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli"
)

func genTestEVMRelayers(t *testing.T, opts evm.ChainRelayExtenderConfig, ks evmrelayer.CSAETHKeystore) *chainlink.CoreRelayerChainInteroperators {
	f := chainlink.RelayerFactory{
		Logger:       opts.Logger,
		DB:           opts.DB,
		QConfig:      opts.AppConfig.Database(),
		LoopRegistry: plugins.NewLoopRegistry(opts.Logger),
	}

	relayers, err := chainlink.NewCoreRelayerChainInteroperators(chainlink.InitEVM(testutils.Context(t), f, chainlink.EVMFactoryConfig{
		RelayerConfig:  opts.RelayerConfig,
		CSAETHKeystore: ks,
	}))
	if err != nil {
		t.Fatal(err)
	}
	return relayers

}

func TestShell_RunNodeWithPasswords(t *testing.T) {
	tests := []struct {
		name         string
		pwdfile      string
		wantUnlocked bool
	}{
		{"correct", "../internal/fixtures/correct_password.txt", true},
		{"incorrect", "../internal/fixtures/incorrect_password.txt", false},
		{"wrongfile", "doesntexist.txt", false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := configtest.NewGeneralConfig(t, func(c *chainlink.Config, s *chainlink.Secrets) {
				s.Password.Keystore = models.NewSecret("dummy")
				c.EVM[0].Nodes[0].Name = ptr("fake")
				c.EVM[0].Nodes[0].HTTPURL = models.MustParseURL("http://fake.com")
				c.EVM[0].Nodes[0].WSURL = models.MustParseURL("WSS://fake.com/ws")
				// seems to be needed for config validate
				c.Insecure.OCRDevelopmentMode = nil
			})
			db := pgtest.NewSqlxDB(t)
			keyStore := cltest.NewKeyStore(t, db, cfg.Database())
			sessionORM := sessions.NewORM(db, time.Minute, logger.TestLogger(t), cfg.Database(), audit.NoopLogger)

			lggr := logger.TestLogger(t)

			opts := evm.ChainRelayExtenderConfig{
				Logger:   lggr,
				DB:       db,
				KeyStore: keyStore.Eth(),
				RelayerConfig: &evm.RelayerConfig{
					AppConfig:        cfg,
					EventBroadcaster: pg.NewNullEventBroadcaster(),
					MailMon:          &utils.MailboxMonitor{},
				},
			}
			testRelayers := genTestEVMRelayers(t, opts, keyStore)

			// Purge the fixture users to test assumption of single admin
			// initialUser user created above
			pgtest.MustExec(t, db, "DELETE FROM users;")

			app := mocks.NewApplication(t)
			app.On("SessionORM").Return(sessionORM).Maybe()
			app.On("GetKeyStore").Return(keyStore).Maybe()
			app.On("GetRelayers").Return(testRelayers).Maybe()
			app.On("Start", mock.Anything).Maybe().Return(nil)
			app.On("Stop").Maybe().Return(nil)
			app.On("ID").Maybe().Return(uuid.New())

			ethClient := evmtest.NewEthClientMock(t)
			ethClient.On("Dial", mock.Anything).Return(nil).Maybe()
			ethClient.On("BalanceAt", mock.Anything, mock.Anything, mock.Anything).Return(big.NewInt(10), nil).Maybe()

			cltest.MustInsertRandomKey(t, keyStore.Eth())
			apiPrompt := cltest.NewMockAPIInitializer(t)

			client := cmd.Shell{
				Config:                 cfg,
				FallbackAPIInitializer: apiPrompt,
				Runner:                 cltest.EmptyRunner{},
				AppFactory:             cltest.InstanceAppFactory{App: app},
				Logger:                 lggr,
			}

			set := flag.NewFlagSet("test", 0)
			cltest.FlagSetApplyFromAction(client.RunNode, set, "")

			require.NoError(t, set.Set("password", test.pwdfile))

			c := cli.NewContext(nil, set, nil)

			run := func() error {
				cli := cmd.NewApp(&client)
				if err := cli.Before(c); err != nil {
					return err
				}
				if err := client.RunNode(c); err != nil {
					return err
				}
				return nil
			}

			if test.wantUnlocked {
				assert.NoError(t, run())
				assert.Equal(t, 1, apiPrompt.Count)
			} else {
				assert.Error(t, run())
				assert.Equal(t, 0, apiPrompt.Count)
			}
		})
	}
}

func TestShell_RunNodeWithAPICredentialsFile(t *testing.T) {
	tests := []struct {
		name       string
		apiFile    string
		wantPrompt bool
		wantError  bool
	}{
		{"correct", "../internal/fixtures/apicredentials", false, false},
		{"no file", "", true, false},
		{"wrong file", "doesntexist.txt", false, true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := configtest.NewGeneralConfig(t, func(c *chainlink.Config, s *chainlink.Secrets) {
				s.Password.Keystore = models.NewSecret("16charlengthp4SsW0rD1!@#_")
				c.EVM[0].Nodes[0].Name = ptr("fake")
				c.EVM[0].Nodes[0].WSURL = models.MustParseURL("WSS://fake.com/ws")
				c.EVM[0].Nodes[0].HTTPURL = models.MustParseURL("http://fake.com")
				// seems to be needed for config validate
				c.Insecure.OCRDevelopmentMode = nil
			})
			db := pgtest.NewSqlxDB(t)
			sessionORM := sessions.NewORM(db, time.Minute, logger.TestLogger(t), cfg.Database(), audit.NoopLogger)

			// Clear out fixture users/users created from the other test cases
			// This asserts that on initial run with an empty users table that the credentials file will instantiate and
			// create/run with a new admin user
			pgtest.MustExec(t, db, "DELETE FROM users;")

			keyStore := cltest.NewKeyStore(t, db, cfg.Database())
			_, err := keyStore.Eth().Create(&cltest.FixtureChainID)
			require.NoError(t, err)

			ethClient := evmtest.NewEthClientMock(t)
			ethClient.On("Dial", mock.Anything).Return(nil).Maybe()
			ethClient.On("BalanceAt", mock.Anything, mock.Anything, mock.Anything).Return(big.NewInt(10), nil).Maybe()

			lggr := logger.TestLogger(t)
			opts := evm.ChainRelayExtenderConfig{
				Logger:   lggr,
				DB:       db,
				KeyStore: keyStore.Eth(),
				RelayerConfig: &evm.RelayerConfig{
					AppConfig:        cfg,
					EventBroadcaster: pg.NewNullEventBroadcaster(),

					MailMon: &utils.MailboxMonitor{},
				},
			}
			testRelayers := genTestEVMRelayers(t, opts, keyStore)
			app := mocks.NewApplication(t)
			app.On("SessionORM").Return(sessionORM)
			app.On("GetKeyStore").Return(keyStore)
			app.On("GetRelayers").Return(testRelayers).Maybe()
			app.On("Start", mock.Anything).Maybe().Return(nil)
			app.On("Stop").Maybe().Return(nil)
			app.On("ID").Maybe().Return(uuid.New())

			prompter := cmdMocks.NewPrompter(t)

			apiPrompt := cltest.NewMockAPIInitializer(t)

			client := cmd.Shell{
				Config:                 cfg,
				AppFactory:             cltest.InstanceAppFactory{App: app},
				KeyStoreAuthenticator:  cmd.TerminalKeyStoreAuthenticator{prompter},
				FallbackAPIInitializer: apiPrompt,
				Runner:                 cltest.EmptyRunner{},
				Logger:                 lggr,
			}

			set := flag.NewFlagSet("test", 0)
			cltest.FlagSetApplyFromAction(client.RunNode, set, "")

			require.NoError(t, set.Set("api", test.apiFile))

			c := cli.NewContext(nil, set, nil)

			if test.wantError {
				err = client.RunNode(c)
				assert.ErrorContains(t, err, "error creating api initializer: open doesntexist.txt: no such file or directory")
			} else {
				assert.NoError(t, client.RunNode(c))
			}

			assert.Equal(t, test.wantPrompt, apiPrompt.Count > 0)
		})
	}
}

func TestShell_DiskMaxSizeBeforeRotateOptionDisablesAsExpected(t *testing.T) {
	tests := []struct {
		name            string
		logFileSize     func(t *testing.T) utils.FileSize
		fileShouldExist bool
	}{
		{"DiskMaxSizeBeforeRotate = 0 => no log on disk", func(t *testing.T) utils.FileSize {
			return 0
		}, false},
		{"DiskMaxSizeBeforeRotate > 0 => log on disk (positive control)", func(t *testing.T) utils.FileSize {
			var logFileSize utils.FileSize
			err := logFileSize.UnmarshalText([]byte("100mb"))
			assert.NoError(t, err)

			return logFileSize
		}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := logger.Config{
				Dir:           t.TempDir(),
				FileMaxSizeMB: int(tt.logFileSize(t) / utils.MB),
			}
			assert.NoError(t, os.MkdirAll(cfg.Dir, os.FileMode(0700)))

			lggr, closeFn := cfg.New()
			t.Cleanup(func() { assert.NoError(t, closeFn()) })

			// Tries to create a log file by logging. The log file won't be created if there's no logging happening.
			lggr.Debug("Trying to create a log file by logging.")

			_, err := os.Stat(cfg.LogsFile())
			require.Equal(t, os.IsNotExist(err), !tt.fileShouldExist)
		})
	}
}

func TestShell_RebroadcastTransactions_Txm(t *testing.T) {
	// Use a non-transactional db for this test because we need to
	// test multiple connections to the database, and changes made within
	// the transaction cannot be seen from another connection.
	config, sqlxDB := heavyweight.FullTestDBV2(t, "rebroadcasttransactions", func(c *chainlink.Config, s *chainlink.Secrets) {
		c.Database.Dialect = dialects.Postgres
		// evm config is used in this test. but if set, it must be pass config validation.
		// simplest to make it nil
		c.EVM = nil
		// seems to be needed for config validate
		c.Insecure.OCRDevelopmentMode = nil
	})
	keyStore := cltest.NewKeyStore(t, sqlxDB, config.Database())
	_, fromAddress := cltest.MustInsertRandomKey(t, keyStore.Eth())

	txStore := cltest.NewTestTxStore(t, sqlxDB, config.Database())
	cltest.MustInsertConfirmedEthTxWithLegacyAttempt(t, txStore, 7, 42, fromAddress)

	lggr := logger.TestLogger(t)

	app := mocks.NewApplication(t)
	app.On("GetSqlxDB").Return(sqlxDB)
	app.On("GetKeyStore").Return(keyStore)
	app.On("ID").Maybe().Return(uuid.New())
	ethClient := evmtest.NewEthClientMockWithDefaultChain(t)
	legacy := cltest.NewLegacyChainsWithMockChain(t, ethClient, config)

	mockRelayerChainInteroperators := chainlinkmocks.NewRelayerChainInteroperators(t)
	mockRelayerChainInteroperators.On("LegacyEVMChains").Return(legacy, nil)
	app.On("GetRelayers").Return(mockRelayerChainInteroperators).Maybe()
	ethClient.On("Dial", mock.Anything).Return(nil)

	client := cmd.Shell{
		Config:                 config,
		AppFactory:             cltest.InstanceAppFactory{App: app},
		FallbackAPIInitializer: cltest.NewMockAPIInitializer(t),
		Runner:                 cltest.EmptyRunner{},
		Logger:                 lggr,
	}

	beginningNonce := uint64(7)
	endingNonce := uint64(10)
	set := flag.NewFlagSet("test", 0)
	cltest.FlagSetApplyFromAction(client.RebroadcastTransactions, set, "")

	require.NoError(t, set.Set("beginningNonce", strconv.FormatUint(beginningNonce, 10)))
	require.NoError(t, set.Set("endingNonce", strconv.FormatUint(endingNonce, 10)))
	require.NoError(t, set.Set("gasPriceWei", "100000000000"))
	require.NoError(t, set.Set("gasLimit", "3000000"))
	require.NoError(t, set.Set("address", fromAddress.Hex()))
	require.NoError(t, set.Set("password", "../internal/fixtures/correct_password.txt"))

	c := cli.NewContext(nil, set, nil)

	for i := beginningNonce; i <= endingNonce; i++ {
		n := i
		ethClient.On("SendTransactionReturnCode", mock.Anything, mock.MatchedBy(func(tx *gethTypes.Transaction) bool {
			return tx.Nonce() == n
		}), mock.Anything).Once().Return(clienttypes.Successful, nil)
	}

	assert.NoError(t, client.RebroadcastTransactions(c))
}

func TestShell_RebroadcastTransactions_OutsideRange_Txm(t *testing.T) {
	beginningNonce := uint(7)
	endingNonce := uint(10)
	gasPrice := big.NewInt(100000000000)
	gasLimit := uint64(3000000)

	tests := []struct {
		name  string
		nonce uint
	}{
		{"below beginning", beginningNonce - 1},
		{"above ending", endingNonce + 1},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Use the non-transactional db for this test because we need to
			// test multiple connections to the database, and changes made within
			// the transaction cannot be seen from another connection.
			config, sqlxDB := heavyweight.FullTestDBV2(t, "rebroadcasttransactions_outsiderange", func(c *chainlink.Config, s *chainlink.Secrets) {
				c.Database.Dialect = dialects.Postgres
				// evm config is used in this test. but if set, it must be pass config validation.
				// simplest to make it nil
				c.EVM = nil
				// seems to be needed for config validate
				c.Insecure.OCRDevelopmentMode = nil
			})

			keyStore := cltest.NewKeyStore(t, sqlxDB, config.Database())

			_, fromAddress := cltest.MustInsertRandomKey(t, keyStore.Eth(), 0)

			txStore := cltest.NewTestTxStore(t, sqlxDB, config.Database())
			cltest.MustInsertConfirmedEthTxWithLegacyAttempt(t, txStore, int64(test.nonce), 42, fromAddress)

			lggr := logger.TestLogger(t)

			app := mocks.NewApplication(t)
			app.On("GetSqlxDB").Return(sqlxDB)
			app.On("GetKeyStore").Return(keyStore)
			app.On("ID").Maybe().Return(uuid.New())
			ethClient := evmtest.NewEthClientMockWithDefaultChain(t)
			ethClient.On("Dial", mock.Anything).Return(nil)
			legacy := cltest.NewLegacyChainsWithMockChain(t, ethClient, config)

			mockRelayerChainInteroperators := chainlinkmocks.NewRelayerChainInteroperators(t)
			mockRelayerChainInteroperators.On("LegacyEVMChains").Return(legacy, nil)
			app.On("GetRelayers").Return(mockRelayerChainInteroperators).Maybe()

			client := cmd.Shell{
				Config:                 config,
				AppFactory:             cltest.InstanceAppFactory{App: app},
				FallbackAPIInitializer: cltest.NewMockAPIInitializer(t),
				Runner:                 cltest.EmptyRunner{},
				Logger:                 lggr,
			}

			set := flag.NewFlagSet("test", 0)
			cltest.FlagSetApplyFromAction(client.RebroadcastTransactions, set, "")

			require.NoError(t, set.Set("beginningNonce", strconv.FormatUint(uint64(beginningNonce), 10)))
			require.NoError(t, set.Set("endingNonce", strconv.FormatUint(uint64(endingNonce), 10)))
			require.NoError(t, set.Set("gasPriceWei", gasPrice.String()))
			require.NoError(t, set.Set("gasLimit", strconv.FormatUint(gasLimit, 10)))
			require.NoError(t, set.Set("address", fromAddress.Hex()))

			require.NoError(t, set.Set("password", "../internal/fixtures/correct_password.txt"))
			c := cli.NewContext(nil, set, nil)

			for i := beginningNonce; i <= endingNonce; i++ {
				n := i
				ethClient.On("SendTransactionReturnCode", mock.Anything, mock.MatchedBy(func(tx *gethTypes.Transaction) bool {
					return uint(tx.Nonce()) == n
				}), mock.Anything).Once().Return(clienttypes.Successful, nil)
			}

			assert.NoError(t, client.RebroadcastTransactions(c))

			cltest.AssertEthTxAttemptCountStays(t, app.GetSqlxDB(), 1)
		})
	}
}

func TestShell_RebroadcastTransactions_AddressCheck(t *testing.T) {
	tests := []struct {
		name          string
		enableAddress bool
		shouldError   bool
		errorContains string
	}{
		{"Rebroadcast: enabled address", true, false, ""},
		{"Rebroadcast: disabled address", false, true, "exists but is disabled for chain"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {

			config, sqlxDB := heavyweight.FullTestDBV2(t, "rebroadcasttransactions_outsiderange", func(c *chainlink.Config, s *chainlink.Secrets) {
				c.Database.Dialect = dialects.Postgres

				c.EVM = nil
				// seems to be needed for config validate
				c.Insecure.OCRDevelopmentMode = nil
			})

			keyStore := cltest.NewKeyStore(t, sqlxDB, config.Database())

			_, fromAddress := cltest.MustInsertRandomKey(t, keyStore.Eth(), 0)

			if !test.enableAddress {
				err := keyStore.Eth().Disable(fromAddress, testutils.FixtureChainID)
				require.NoError(t, err, "failed to disable test key")
			}

			lggr := logger.TestLogger(t)

			app := mocks.NewApplication(t)
			app.On("GetSqlxDB").Maybe().Return(sqlxDB)
			app.On("GetKeyStore").Return(keyStore)
			app.On("ID").Maybe().Return(uuid.New())
			ethClient := evmtest.NewEthClientMockWithDefaultChain(t)
			ethClient.On("Dial", mock.Anything).Return(nil)
			legacy := cltest.NewLegacyChainsWithMockChain(t, ethClient, config)

			mockRelayerChainInteroperators := chainlinkmocks.NewRelayerChainInteroperators(t)
			mockRelayerChainInteroperators.On("LegacyEVMChains").Return(legacy, nil)
			app.On("GetRelayers").Return(mockRelayerChainInteroperators).Maybe()
			ethClient.On("SendTransactionReturnCode", mock.Anything, mock.Anything, mock.Anything).Maybe().Return(clienttypes.Successful, nil)

			client := cmd.Shell{
				Config:                 config,
				AppFactory:             cltest.InstanceAppFactory{App: app},
				FallbackAPIInitializer: cltest.NewMockAPIInitializer(t),
				Runner:                 cltest.EmptyRunner{},
				Logger:                 lggr,
			}

			set := flag.NewFlagSet("test", 0)
			set.Set("evmChainID", testutils.SimulatedChainID.String())
			cltest.FlagSetApplyFromAction(client.RebroadcastTransactions, set, "")

			require.NoError(t, set.Set("address", fromAddress.Hex()))
			require.NoError(t, set.Set("password", "../internal/fixtures/correct_password.txt"))
			c := cli.NewContext(nil, set, nil)
			if test.shouldError {
				require.ErrorContains(t, client.RebroadcastTransactions(c), test.errorContains)
			} else {
				require.NoError(t, client.RebroadcastTransactions(c))
			}

		})
	}
}

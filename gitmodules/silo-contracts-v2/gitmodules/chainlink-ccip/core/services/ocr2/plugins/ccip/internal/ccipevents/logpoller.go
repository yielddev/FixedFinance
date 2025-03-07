package ccipevents

import (
	"context"
	"fmt"
	"math/big"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/rpc"
	"github.com/pkg/errors"

	evmclient "github.com/smartcontractkit/chainlink/v2/core/chains/evm/client"
	"github.com/smartcontractkit/chainlink/v2/core/chains/evm/logpoller"
	"github.com/smartcontractkit/chainlink/v2/core/gethwrappers/ccip/generated/evm_2_evm_offramp"
	"github.com/smartcontractkit/chainlink/v2/core/gethwrappers/ccip/generated/evm_2_evm_onramp"
	"github.com/smartcontractkit/chainlink/v2/core/gethwrappers/ccip/generated/price_registry"
	"github.com/smartcontractkit/chainlink/v2/core/logger"
	"github.com/smartcontractkit/chainlink/v2/core/services/ocr2/plugins/ccip/abihelpers"
	"github.com/smartcontractkit/chainlink/v2/core/services/pg"
)

var _ Client = &LogPollerClient{}

// LogPollerClient implements the Client interface by using a logPoller instance to fetch the events.
type LogPollerClient struct {
	lp     logpoller.LogPoller
	lggr   logger.Logger
	client evmclient.Client

	dependencyCache sync.Map
}

func NewLogPollerClient(lp logpoller.LogPoller, lggr logger.Logger, client evmclient.Client) *LogPollerClient {
	return &LogPollerClient{
		lp:     lp,
		lggr:   lggr,
		client: client,
	}
}

func (c *LogPollerClient) GetSendRequestsGteSeqNum(ctx context.Context, onRampAddress common.Address, seqNum uint64, checkFinalityTags bool, confs int) (sendReqs []Event[evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested], err error) {
	onRamp, err := c.loadOnRamp(onRampAddress)
	if err != nil {
		return nil, err
	}

	if !checkFinalityTags {
		logs, err2 := c.lp.LogsDataWordGreaterThan(
			abihelpers.EventSignatures.SendRequested,
			onRampAddress,
			abihelpers.EventSignatures.SendRequestedSequenceNumberWord,
			abihelpers.EvmWord(seqNum),
			confs,
			pg.WithParentCtx(ctx),
		)
		if err2 != nil {
			return nil, fmt.Errorf("logs data word greater than: %w", err2)
		}
		return parseLogs[evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested](
			logs,
			c.lggr,
			func(log types.Log) (*evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested, error) {
				return onRamp.ParseCCIPSendRequested(log)
			},
		)
	}

	// If the chain is based on explicit finality we only examine logs less than or equal to the latest finalized block number.
	// NOTE: there appears to be a bug in ethclient whereby BlockByNumber fails with "unsupported txtype" when trying to parse the block
	// when querying L2s, headers however work.
	// TODO (CCIP-778): Migrate to core finalized tags, below doesn't work for some chains e.g. Celo.
	latestFinalizedHeader, err := c.client.HeaderByNumber(
		ctx,
		big.NewInt(rpc.FinalizedBlockNumber.Int64()),
	)
	if err != nil {
		return nil, err
	}

	if latestFinalizedHeader == nil {
		return nil, errors.New("latest finalized header is nil")
	}
	if latestFinalizedHeader.Number == nil {
		return nil, errors.New("latest finalized number is nil")
	}
	logs, err := c.lp.LogsUntilBlockHashDataWordGreaterThan(
		abihelpers.EventSignatures.SendRequested,
		onRampAddress,
		abihelpers.EventSignatures.SendRequestedSequenceNumberWord,
		abihelpers.EvmWord(seqNum),
		latestFinalizedHeader.Hash(),
		pg.WithParentCtx(ctx),
	)
	if err != nil {
		return nil, fmt.Errorf("logs until block hash data word greater than: %w", err)
	}

	return parseLogs[evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested](
		logs,
		c.lggr,
		func(log types.Log) (*evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested, error) {
			return onRamp.ParseCCIPSendRequested(log)
		},
	)
}

func (c *LogPollerClient) GetSendRequestsBetweenSeqNums(ctx context.Context, onRampAddress common.Address, seqNumMin, seqNumMax uint64, confs int) ([]Event[evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested], error) {
	onRamp, err := c.loadOnRamp(onRampAddress)
	if err != nil {
		return nil, err
	}

	logs, err := c.lp.LogsDataWordRange(
		abihelpers.EventSignatures.SendRequested,
		onRampAddress,
		abihelpers.EventSignatures.SendRequestedSequenceNumberWord,
		logpoller.EvmWord(seqNumMin),
		logpoller.EvmWord(seqNumMax),
		confs,
		pg.WithParentCtx(ctx))
	if err != nil {
		return nil, err
	}

	return parseLogs[evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested](
		logs,
		c.lggr,
		func(log types.Log) (*evm_2_evm_onramp.EVM2EVMOnRampCCIPSendRequested, error) {
			return onRamp.ParseCCIPSendRequested(log)
		},
	)
}

func (c *LogPollerClient) GetTokenPriceUpdatesCreatedAfter(ctx context.Context, priceRegistryAddress common.Address, ts time.Time, confs int) ([]Event[price_registry.PriceRegistryUsdPerTokenUpdated], error) {
	priceRegistry, err := c.loadPriceRegistry(priceRegistryAddress)
	if err != nil {
		return nil, err
	}

	logs, err := c.lp.LogsCreatedAfter(
		abihelpers.EventSignatures.UsdPerTokenUpdated,
		priceRegistryAddress,
		ts,
		confs,
		pg.WithParentCtx(ctx),
	)
	if err != nil {
		return nil, err
	}

	return parseLogs[price_registry.PriceRegistryUsdPerTokenUpdated](
		logs,
		c.lggr,
		func(log types.Log) (*price_registry.PriceRegistryUsdPerTokenUpdated, error) {
			return priceRegistry.ParseUsdPerTokenUpdated(log)
		},
	)
}

func (c *LogPollerClient) GetGasPriceUpdatesCreatedAfter(ctx context.Context, priceRegistryAddress common.Address, chainSelector uint64, ts time.Time, confs int) ([]Event[price_registry.PriceRegistryUsdPerUnitGasUpdated], error) {
	priceRegistry, err := c.loadPriceRegistry(priceRegistryAddress)
	if err != nil {
		return nil, err
	}

	logs, err := c.lp.IndexedLogsCreatedAfter(
		abihelpers.EventSignatures.UsdPerUnitGasUpdated,
		priceRegistryAddress,
		1,
		[]common.Hash{abihelpers.EvmWord(chainSelector)},
		ts,
		confs,
		pg.WithParentCtx(ctx),
	)
	if err != nil {
		return nil, err
	}

	return parseLogs[price_registry.PriceRegistryUsdPerUnitGasUpdated](
		logs,
		c.lggr,
		func(log types.Log) (*price_registry.PriceRegistryUsdPerUnitGasUpdated, error) {
			return priceRegistry.ParseUsdPerUnitGasUpdated(log)
		},
	)
}

func (c *LogPollerClient) GetExecutionStateChangesBetweenSeqNums(ctx context.Context, offRampAddress common.Address, seqNumMin, seqNumMax uint64, confs int) ([]Event[evm_2_evm_offramp.EVM2EVMOffRampExecutionStateChanged], error) {
	offRamp, err := c.loadOffRamp(offRampAddress)
	if err != nil {
		return nil, err
	}

	logs, err := c.lp.IndexedLogsTopicRange(
		abihelpers.EventSignatures.ExecutionStateChanged,
		offRampAddress,
		abihelpers.EventSignatures.ExecutionStateChangedSequenceNumberIndex,
		logpoller.EvmWord(seqNumMin),
		logpoller.EvmWord(seqNumMax),
		confs,
		pg.WithParentCtx(ctx),
	)
	if err != nil {
		return nil, err
	}

	return parseLogs[evm_2_evm_offramp.EVM2EVMOffRampExecutionStateChanged](
		logs,
		c.lggr,
		func(log types.Log) (*evm_2_evm_offramp.EVM2EVMOffRampExecutionStateChanged, error) {
			return offRamp.ParseExecutionStateChanged(log)
		},
	)
}

func (c *LogPollerClient) LatestBlock(ctx context.Context) (int64, error) {
	return c.lp.LatestBlock(pg.WithParentCtx(ctx))
}

func parseLogs[T any](logs []logpoller.Log, lggr logger.Logger, parseFunc func(log types.Log) (*T, error)) ([]Event[T], error) {
	reqs := make([]Event[T], 0, len(logs))
	for _, log := range logs {
		data, err := parseFunc(log.ToGethLog())
		if err == nil {
			reqs = append(reqs, Event[T]{
				Data: *data,
				BlockMeta: BlockMeta{
					BlockTimestamp: log.BlockTimestamp,
					BlockNumber:    log.BlockNumber,
				},
			})
		}
	}

	if len(logs) != len(reqs) {
		lggr.Warnw("Some logs were not parsed", "logs", len(logs), "requests", len(reqs))
	}
	return reqs, nil
}

func (c *LogPollerClient) loadOnRamp(addr common.Address) (*evm_2_evm_onramp.EVM2EVMOnRampFilterer, error) {
	onRamp, exists := loadCachedDependency[*evm_2_evm_onramp.EVM2EVMOnRampFilterer](&c.dependencyCache, addr)
	if exists {
		return onRamp, nil
	}

	onRamp, err := evm_2_evm_onramp.NewEVM2EVMOnRampFilterer(addr, c.client)
	if err != nil {
		return nil, err
	}

	c.dependencyCache.Store(addr, onRamp)
	return onRamp, nil
}

func (c *LogPollerClient) loadPriceRegistry(addr common.Address) (*price_registry.PriceRegistryFilterer, error) {
	priceRegistry, exists := loadCachedDependency[*price_registry.PriceRegistryFilterer](&c.dependencyCache, addr)
	if exists {
		return priceRegistry, nil
	}

	priceRegistry, err := price_registry.NewPriceRegistryFilterer(addr, c.client)
	if err != nil {
		return nil, err
	}

	c.dependencyCache.Store(addr, priceRegistry)
	return priceRegistry, nil
}

func (c *LogPollerClient) loadOffRamp(addr common.Address) (*evm_2_evm_offramp.EVM2EVMOffRampFilterer, error) {
	offRamp, exists := loadCachedDependency[*evm_2_evm_offramp.EVM2EVMOffRampFilterer](&c.dependencyCache, addr)
	if exists {
		return offRamp, nil
	}

	offRamp, err := evm_2_evm_offramp.NewEVM2EVMOffRampFilterer(addr, c.client)
	if err != nil {
		return nil, err
	}

	c.dependencyCache.Store(addr, offRamp)
	return offRamp, nil
}

func loadCachedDependency[T any](cache *sync.Map, addr common.Address) (T, bool) {
	var empty T

	if rawVal, exists := cache.Load(addr); exists {
		if dep, is := rawVal.(T); is {
			return dep, true
		}
	}

	return empty, false
}

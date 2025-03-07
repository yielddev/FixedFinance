package test_env

import (
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"fmt"
	"math/big"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/google/uuid"
	"github.com/pelletier/go-toml/v2"
	"github.com/pkg/errors"
	"github.com/rs/zerolog/log"
	"github.com/smartcontractkit/chainlink-testing-framework/docker/test_env"
	tc "github.com/testcontainers/testcontainers-go"
	tcwait "github.com/testcontainers/testcontainers-go/wait"

	"github.com/smartcontractkit/chainlink-testing-framework/blockchain"
	"github.com/smartcontractkit/chainlink-testing-framework/logwatch"
	ocrtypes "github.com/smartcontractkit/libocr/offchainreporting2/types"
	"github.com/smartcontractkit/libocr/offchainreporting2plus/confighelper"

	"github.com/smartcontractkit/chainlink/v2/core/services/chainlink"
	"github.com/smartcontractkit/chainlink/v2/core/services/keystore/chaintype"

	"github.com/smartcontractkit/chainlink/integration-tests/client"
	"github.com/smartcontractkit/chainlink/integration-tests/utils"
	"github.com/smartcontractkit/chainlink/integration-tests/utils/templates"
)

var (
	ErrConnectNodeClient    = "could not connect Node HTTP Client"
	ErrStartCLNodeContainer = "failed to start CL node container"
)

type ClNode struct {
	test_env.EnvComponent
	API                   *client.ChainlinkClient
	NodeConfig            *chainlink.Config
	NodeSecretsConfigTOML string
	PostgresDb            *test_env.PostgresDb
	lw                    *logwatch.LogWatch
}

type ClNodeOption = func(c *ClNode)

// Sets custom node container name if name is not empty
func WithNodeContainerName(name string) ClNodeOption {
	return func(c *ClNode) {
		if name != "" {
			c.ContainerName = name
		}
	}
}

// Sets custom node db container name if name is not empty
func WithDbContainerName(name string) ClNodeOption {
	return func(c *ClNode) {
		if name != "" {
			c.PostgresDb.ContainerName = name
		}
	}
}

func WithLogWatch(lw *logwatch.LogWatch) ClNodeOption {
	return func(c *ClNode) {
		c.lw = lw
	}
}

func NewClNode(networks []string, nodeConfig *chainlink.Config, opts ...ClNodeOption) *ClNode {
	nodeDefaultCName := fmt.Sprintf("%s-%s", "cl-node", uuid.NewString()[0:8])
	pgDefaultCName := fmt.Sprintf("pg-%s", nodeDefaultCName)
	pgDb := test_env.NewPostgresDb(networks, test_env.WithPostgresDbContainerName(pgDefaultCName))
	n := &ClNode{
		EnvComponent: test_env.EnvComponent{
			ContainerName: nodeDefaultCName,
			Networks:      networks,
		},
		NodeConfig: nodeConfig,
		PostgresDb: pgDb,
	}
	for _, opt := range opts {
		opt(n)
	}
	return n
}

// Restart restarts only CL node, DB container is reused
func (n *ClNode) Restart(cfg *chainlink.Config) error {
	if err := n.Container.Terminate(context.Background()); err != nil {
		return err
	}
	n.NodeConfig = cfg
	return n.StartContainer()
}

func (n *ClNode) PrimaryETHAddress() (string, error) {
	return n.API.PrimaryEthAddress()
}

func (n *ClNode) AddBootstrapJob(verifierAddr common.Address, fromBlock uint64, chainId int64,
	feedId [32]byte) (*client.Job, error) {
	spec := utils.BuildBootstrapSpec(verifierAddr, chainId, fromBlock, feedId)
	return n.API.MustCreateJob(spec)
}

func (n *ClNode) AddMercuryOCRJob(verifierAddr common.Address, fromBlock uint64, chainId int64,
	feedId [32]byte, customAllowedFaults *int, bootstrapUrl string,
	mercuryServerUrl string, mercuryServerPubKey string,
	eaUrls []*url.URL) (*client.Job, error) {

	csaKeys, _, err := n.API.ReadCSAKeys()
	if err != nil {
		return nil, err
	}
	csaPubKey := csaKeys.Data[0].ID

	nodeOCRKeys, err := n.API.MustReadOCR2Keys()
	if err != nil {
		return nil, err
	}

	var nodeOCRKeyId []string
	for _, key := range nodeOCRKeys.Data {
		if key.Attributes.ChainType == string(chaintype.EVM) {
			nodeOCRKeyId = append(nodeOCRKeyId, key.ID)
			break
		}
	}

	bridges := utils.BuildBridges(eaUrls)
	for _, b := range bridges {
		err = n.API.MustCreateBridge(&b)
		if err != nil {
			return nil, err
		}
	}

	var allowedFaults int
	if customAllowedFaults != nil {
		allowedFaults = *customAllowedFaults
	} else {
		allowedFaults = 2
	}

	spec := utils.BuildOCRSpec(
		verifierAddr, chainId, fromBlock, feedId, bridges,
		csaPubKey, mercuryServerUrl, mercuryServerPubKey, nodeOCRKeyId[0],
		bootstrapUrl, allowedFaults)

	return n.API.MustCreateJob(spec)
}

func (n *ClNode) GetContainerName() string {
	name, err := n.Container.Name(context.Background())
	if err != nil {
		return ""
	}
	return strings.Replace(name, "/", "", -1)
}

func (n *ClNode) GetPeerUrl() (string, error) {
	p2pKeys, err := n.API.MustReadP2PKeys()
	if err != nil {
		return "", err
	}
	p2pId := p2pKeys.Data[0].Attributes.PeerID

	return fmt.Sprintf("%s@%s:%d", p2pId, n.GetContainerName(), 6690), nil
}

func (n *ClNode) GetNodeCSAKeys() (*client.CSAKeys, error) {
	csaKeys, _, err := n.API.ReadCSAKeys()
	if err != nil {
		return nil, err
	}
	return csaKeys, err
}

func (n *ClNode) ChainlinkNodeAddress() (common.Address, error) {
	addr, err := n.API.PrimaryEthAddress()
	if err != nil {
		return common.Address{}, err
	}
	return common.HexToAddress(addr), nil
}

func (n *ClNode) Fund(evmClient blockchain.EVMClient, amount *big.Float) error {
	toAddress, err := n.API.PrimaryEthAddress()
	if err != nil {
		return err
	}
	gasEstimates, err := evmClient.EstimateGas(ethereum.CallMsg{})
	if err != nil {
		return err
	}
	return evmClient.Fund(toAddress, amount, gasEstimates)
}

func (n *ClNode) StartContainer() error {
	err := n.PostgresDb.StartContainer()
	if err != nil {
		return err
	}
	nodeSecretsToml, err := templates.NodeSecretsTemplate{
		PgDbName:   n.PostgresDb.DbName,
		PgHost:     n.PostgresDb.ContainerName,
		PgPort:     n.PostgresDb.Port,
		PgPassword: n.PostgresDb.Password,
	}.String()
	if err != nil {
		return err
	}
	n.NodeSecretsConfigTOML = nodeSecretsToml
	cReq, err := n.getContainerRequest()
	if err != nil {
		return err
	}
	container, err := tc.GenericContainer(context.Background(), tc.GenericContainerRequest{
		ContainerRequest: *cReq,
		Started:          true,
		Reuse:            true,
	})
	if err != nil {
		return errors.Wrap(err, ErrStartCLNodeContainer)
	}
	if n.lw != nil {
		if err := n.lw.ConnectContainer(context.Background(), container, "cl-node", true); err != nil {
			return err
		}
	}
	clEndpoint, err := container.Endpoint(context.Background(), "http")
	if err != nil {
		return err
	}
	ip, err := container.ContainerIP(context.Background())
	if err != nil {
		return err
	}
	log.Info().Str("containerName", n.ContainerName).
		Str("clEndpoint", clEndpoint).
		Str("clInternalIP", ip).
		Msg("Started Chainlink Node container")
	clClient, err := client.NewChainlinkClient(&client.ChainlinkConfig{
		URL:        clEndpoint,
		Email:      "local@local.com",
		Password:   "localdevpassword",
		InternalIP: ip,
	})
	if err != nil {
		return errors.Wrap(err, ErrConnectNodeClient)
	}

	clClient.Config.InternalIP = n.ContainerName
	n.Container = container
	n.API = clClient

	return nil
}

func (n *ClNode) getContainerRequest() (
	*tc.ContainerRequest, error) {
	configFile, err := os.CreateTemp("", "node_config")
	if err != nil {
		return nil, err
	}
	data, err := toml.Marshal(n.NodeConfig)
	if err != nil {
		return nil, err
	}
	_, err = configFile.WriteString(string(data))
	if err != nil {
		return nil, err
	}
	secretsFile, err := os.CreateTemp("", "node_secrets")
	if err != nil {
		return nil, err
	}
	_, err = secretsFile.WriteString(n.NodeSecretsConfigTOML)
	if err != nil {
		return nil, err
	}

	adminCreds := "local@local.com\nlocaldevpassword"
	adminCredsFile, err := os.CreateTemp("", "admin_creds")
	if err != nil {
		return nil, err
	}
	_, err = adminCredsFile.WriteString(adminCreds)
	if err != nil {
		return nil, err
	}

	apiCreds := "local@local.com\nlocaldevpassword"
	apiCredsFile, err := os.CreateTemp("", "api_creds")
	if err != nil {
		return nil, err
	}
	_, err = apiCredsFile.WriteString(apiCreds)
	if err != nil {
		return nil, err
	}

	configPath := "/home/cl-node-config.toml"
	secretsPath := "/home/cl-node-secrets.toml"
	adminCredsPath := "/home/admin-credentials.txt"
	apiCredsPath := "/home/api-credentials.txt"

	image, ok := os.LookupEnv("CHAINLINK_IMAGE")
	if !ok {
		return nil, errors.New("CHAINLINK_IMAGE env must be set")
	}
	tag, ok := os.LookupEnv("CHAINLINK_VERSION")
	if !ok {
		return nil, errors.New("CHAINLINK_VERSION env must be set")
	}

	return &tc.ContainerRequest{
		Name:         n.ContainerName,
		Image:        fmt.Sprintf("%s:%s", image, tag),
		ExposedPorts: []string{"6688/tcp"},
		Entrypoint: []string{"chainlink",
			"-c", configPath,
			"-s", secretsPath,
			"node", "start", "-d",
			"-p", adminCredsPath,
			"-a", apiCredsPath,
		},
		Networks: n.Networks,
		WaitingFor: tcwait.ForHTTP("/health").
			WithPort("6688/tcp").
			WithStartupTimeout(90 * time.Second).
			WithPollInterval(1 * time.Second),
		Files: []tc.ContainerFile{
			{
				HostFilePath:      configFile.Name(),
				ContainerFilePath: configPath,
				FileMode:          0644,
			},
			{
				HostFilePath:      secretsFile.Name(),
				ContainerFilePath: secretsPath,
				FileMode:          0644,
			},
			{
				HostFilePath:      adminCredsFile.Name(),
				ContainerFilePath: adminCredsPath,
				FileMode:          0644,
			},
			{
				HostFilePath:      apiCredsFile.Name(),
				ContainerFilePath: apiCredsPath,
				FileMode:          0644,
			},
		},
	}, nil
}

func GetOracleIdentities(chainlinkNodes []*ClNode) ([]int, []confighelper.OracleIdentityExtra) {
	S := make([]int, len(chainlinkNodes))
	oracleIdentities := make([]confighelper.OracleIdentityExtra, len(chainlinkNodes))
	sharedSecretEncryptionPublicKeys := make([]ocrtypes.ConfigEncryptionPublicKey, len(chainlinkNodes))
	var wg sync.WaitGroup
	for i, cl := range chainlinkNodes {
		wg.Add(1)
		go func(i int, cl *ClNode) error {
			defer wg.Done()

			ocr2Keys, err := cl.API.MustReadOCR2Keys()
			if err != nil {
				return err
			}
			var ocr2Config client.OCR2KeyAttributes
			for _, key := range ocr2Keys.Data {
				if key.Attributes.ChainType == string(chaintype.EVM) {
					ocr2Config = key.Attributes
					break
				}
			}

			keys, err := cl.API.MustReadP2PKeys()
			if err != nil {
				return err
			}
			p2pKeyID := keys.Data[0].Attributes.PeerID

			offchainPkBytes, err := hex.DecodeString(strings.TrimPrefix(ocr2Config.OffChainPublicKey, "ocr2off_evm_"))
			if err != nil {
				return err
			}

			offchainPkBytesFixed := [ed25519.PublicKeySize]byte{}
			copy(offchainPkBytesFixed[:], offchainPkBytes)
			if err != nil {
				return err
			}

			configPkBytes, err := hex.DecodeString(strings.TrimPrefix(ocr2Config.ConfigPublicKey, "ocr2cfg_evm_"))
			if err != nil {
				return err
			}

			configPkBytesFixed := [ed25519.PublicKeySize]byte{}
			copy(configPkBytesFixed[:], configPkBytes)
			if err != nil {
				return err
			}

			onchainPkBytes, err := hex.DecodeString(strings.TrimPrefix(ocr2Config.OnChainPublicKey, "ocr2on_evm_"))
			if err != nil {
				return err
			}

			csaKeys, _, err := cl.API.ReadCSAKeys()
			if err != nil {
				return err
			}

			sharedSecretEncryptionPublicKeys[i] = configPkBytesFixed
			oracleIdentities[i] = confighelper.OracleIdentityExtra{
				OracleIdentity: confighelper.OracleIdentity{
					OnchainPublicKey:  onchainPkBytes,
					OffchainPublicKey: offchainPkBytesFixed,
					PeerID:            p2pKeyID,
					TransmitAccount:   ocrtypes.Account(csaKeys.Data[0].ID),
				},
				ConfigEncryptionPublicKey: configPkBytesFixed,
			}
			S[i] = 1

			return nil
		}(i, cl)
	}
	wg.Wait()

	return S, oracleIdentities
}

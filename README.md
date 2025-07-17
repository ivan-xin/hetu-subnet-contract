# HETU Subnet Contract

A comprehensive smart contract system for managing decentralized AI subnets on the HETU network. This project enables subnet creation, governance, staking, and reward distribution for AI model training and inference networks.

## 🌟 Overview

The HETU Subnet Contract system provides a complete infrastructure for:
- **Subnet Management**: Create and manage AI-focused subnets with custom tokenomics
- **Global Staking**: Stake HETU tokens to participate in subnet ecosystems
- **Neuron Registration**: Register as miners or validators in specific subnets
- **Reward Distribution**: Automated reward distribution based on network contributions
- **AMM Integration**: Built-in liquidity pools for subnet tokens

## 🏗️ Architecture

### Core Components

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  SubnetManager  │    │ GlobalStaking   │    │ NeuronManager   │
│                 │    │                 │    │                 │
│ • Create Subnets│    │ • Stake HETU    │    │ • Register      │
│ • Manage Tokens │    │ • Allocate      │    │ • Validate      │
│ • AMM Pools     │    │ • Participate   │    │ • Mine          │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Interfaces    │
                    │                 │
                    │ • ISubnetTypes  │
                    │ • IGlobalStaking│
                    │ • INeuronManager│
                    └─────────────────┘
```

## 📋 Features

### 🔧 Subnet Management
- **Subnet Creation**: Deploy new AI subnets with custom parameters
- **Alpha Token Generation**: Automatic ERC20 token creation for each subnet
- **AMM Pool Setup**: Integrated liquidity pools for token trading

### 💰 Staking System
- **Global Staking**: Stake HETU tokens to gain network participation rights
- **Subnet Allocation**: Allocate staked tokens to specific subnets
- **Flexible Management**: Add, remove, and reallocate stakes dynamically
- **Minimum Requirements**: Configurable minimum stake thresholds

### 🤖 Neuron Network
- **Role Selection**: Choose between miner and validator roles
- **Registration System**: Stake-based registration with role-specific requirements
- **Service Discovery**: Axon and Prometheus endpoint management
- **Reward Distribution**: Native code integration for performance-based rewards

### 🏊 Liquidity & Trading
- **Automated Market Making**: Built-in AMM for subnet token trading
- **Dynamic Pricing**: Real-time price discovery for subnet tokens
- **Liquidity Injection**: Initial liquidity provision during subnet creation
- **Volume Tracking**: Comprehensive trading statistics

## 🚀 Quick Start

### Prerequisites
- Node.js >= 16.0.0
- Hardhat or Foundry
- HETU testnet access

### Installation

```bash
git clone https://github.com/ivan-xin/hetu-subnet-contract.git
cd hetu-subnet-contract
npm install
```

### Development Setup

```bash
# Install dependencies
npm install

# Run local node
npx hardhat node

# Deploy to local network (in another terminal)
npx hardhat ignition deploy ignition/modules/HetuSubnet.js --network localhost
```

## 📖 Usage Examples

### Creating a Subnet

```javascript
// JavaScript/TypeScript Example
const subnetManager = await ethers.getContractAt("SubnetManager", subnetManagerAddress);

// 1. First approve HETU tokens
const lockCost = await subnetManager.getNetworkLockCost();
await hetuToken.approve(subnetManager.address, lockCost);

// 2. Create subnet
const tx = await subnetManager.registerNetwork(
    "AI Vision Subnet",
    "Computer vision and image processing network",
    "VISION",
    "VIS"
);

const receipt = await tx.wait();
const event = receipt.events.find(e => e.event === "NetworkRegistered");
const netuid = event.args.netuid;
console.log(`Subnet created with ID: ${netuid}`);
```

### Staking and Participation

```javascript
// 1. Approve and add global stake
await hetuToken.approve(globalStaking.address, ethers.utils.parseEther("1000"));
await globalStaking.addGlobalStake(ethers.utils.parseEther("1000"));

// 2. Allocate stake to specific subnet
await globalStaking.allocateToSubnet(netuid, ethers.utils.parseEther("500"));

// 3. Register as neuron
await neuronManager.registerNeuron(
    netuid,
    true, // isValidator
    "http://my-node.com", // axonEndpoint
    8080, // axonPort
    "http://my-metrics.com", // prometheusEndpoint
    9090  // prometheusPort
);
```

### Trading Subnet Tokens

```javascript
// 1. Get subnet info
const subnetInfo = await subnetManager.getSubnetInfo(netuid);
const pool = await ethers.getContractAt("SubnetAMM", subnetInfo.ammPool);

// 2. Approve HETU tokens for trading
await hetuToken.approve(pool.address, ethers.utils.parseEther("100"));

// 3. Swap HETU for Alpha tokens
await pool.swapTaoForAlpha(
    ethers.utils.parseEther("100"), // HETU amount
    0 // Minimum output (slippage protection)
);
```

## 📚 API Reference

### SubnetManager

| Function | Description | Access |
|----------|-------------|---------|
| `registerNetwork()` | Create new subnet | Public |
| `activateSubnet()` | Activate subnet | Owner |
| `transferSubnetOwnership()` | Transfer ownership | Owner |
| `getSubnetDetails()` | Get subnet info | View |

### GlobalStaking

| Function | Description | Access |
|----------|-------------|---------|
| `addGlobalStake()` | Stake HETU tokens | Public |
| `allocateToSubnet()` | Allocate to subnet | Public |
| `removeGlobalStake()` | Unstake tokens | Public |
| `getStakeInfo()` | Get stake details | View |

### NeuronManager

| Function | Description | Access |
|----------|-------------|---------|
| `registerNeuron()` | Register as neuron | Public |
| `deregisterNeuron()` | Unregister neuron | Public |
| `updateService()` | Update endpoints | Neuron |
| `distributeRewards()` | Distribute rewards | Authorized |

## 🔐 Security

### Audit Status
- [ ] Initial audit pending
- [ ] Bug bounty program: TBD

### Security Features
- **Reentrancy Protection**: All state-changing functions protected
- **Access Control**: Role-based permissions system
- **Emergency Pause**: Circuit breaker for critical situations
- **Upgrade Safety**: Proxy pattern for safe upgrades

### Best Practices
- Always check subnet existence before operations
- Verify stake requirements before neuron registration
- Monitor gas costs for batch operations
- Use events for off-chain monitoring


## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Install dependencies
npm install

# Run local node
npx hardhat node

# Deploy to local network
npx hardhat run scripts/deploy-local.js --network localhost
```

### Code Style
- Solidity: Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- JavaScript: ESLint + Prettier configuration
- Documentation: NatSpec for all public functions

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.



## ⚠️ Disclaimer

This software is in active development. Use at your own risk. The HETU team is not responsible for any losses incurred through the use of this software.

---

**Built with ❤️ by the HETU Team**

# Hetu Subnet Contract Documentation

Welcome to the Hetu Subnet Contract system - a decentralized platform for creating and participating in AI subnets. This documentation has been split into specialized guides for better usability.

## 📚 Documentation Structure

### For Subnet Creators
📖 **[Subnet Registration Guide](./Subnet-Registration-Guide.md)**
- Complete guide to creating your own AI subnet
- Covers basic and advanced configuration options
- Includes troubleshooting and best practices
- Step-by-step code examples

### For Network Participants  
🔗 **[Neuron Registration Guide](./Neuron-Registration-Guide.md)**
- How to join subnets as miners or validators
- Staking requirements and management
- Multiple subnet participation strategies
- Role switching and optimization

---

## 🚀 Quick Start

### I Want to Create a Subnet
If you want to start your own AI subnet:
1. Read the **[Subnet Registration Guide](./Subnet-Registration-Guide.md)**
2. Ensure you have sufficient HETU tokens
3. Follow the step-by-step registration process
4. Configure your subnet parameters

### I Want to Join a Subnet
If you want to participate in existing subnets:
1. Read the **[Neuron Registration Guide](./Neuron-Registration-Guide.md)**
2. Stake HETU tokens in GlobalStaking
3. Choose your role (Miner or Validator)
4. Register in your target subnet(s)

---

## 🏗️ System Architecture

The Hetu Subnet Contract system consists of several interconnected components:

### Core Contracts

- **SubnetManager**: Handles subnet creation, configuration, and management
- **NeuronManager**: Manages neuron registration, deregistration, and role assignments  
- **GlobalStaking**: Manages HETU token staking and allocation across subnets
- **SubnetAMM**: Provides automated market making for subnet-specific tokens

### Key Concepts

- **Subnet**: A decentralized AI network with its own token, AMM pool, and customizable parameters
- **Neuron**: A participant in a subnet that can be either a miner or validator
- **HETU**: The native token used for staking, fees, and subnet registration
- **Alpha Token**: Each subnet has its own ERC-20 token for incentives and rewards
- **Staking**: HETU tokens must be staked globally and then allocated to specific subnets

---

## 🔄 Typical Workflows

### Subnet Creation Workflow
```
1. Wrap HETU → WHETU
2. Check registration cost and rate limits
3. Approve token spending
4. Register subnet (basic or with custom parameters)
5. Verify subnet creation
6. Monitor for neuron registrations
```

### Neuron Participation Workflow  
```
1. Wrap HETU → WHETU
2. Add tokens to GlobalStaking
3. Choose target subnet(s)
4. Allocate stake to subnet(s)
5. Register as neuron (miner or validator)
6. Start participating in consensus
```

---

## 💡 Key Features

### For Subnet Owners
- **Full Control**: Complete ownership and governance over your subnet
- **Custom Economics**: Configure your own token economics and reward parameters
- **Flexible Parameters**: Adjust consensus mechanisms, difficulty, and participation rules
- **AMM Integration**: Built-in liquidity pools for your subnet token

### For Neuron Operators
- **Multi-Subnet Support**: Participate in multiple subnets simultaneously
- **Flexible Staking**: Dynamically allocate stake across different subnets
- **Role Flexibility**: Switch between miner and validator roles based on stake
- **Reward Optimization**: Optimize rewards across multiple subnet participations

---

## ⚡ Getting Started Quickly

### Create Your First Subnet (5 minutes)
```javascript
// 1. Wrap HETU
await whetuToken.deposit({ value: ethers.parseEther("1000") });

// 2. Approve and register
const cost = await subnetManager.getNetworkLockCost();
await whetuToken.approve(subnetManager.target, cost);
await subnetManager.registerNetwork("My Subnet", "Description", "Token", "TKN");
```

### Join Your First Subnet (3 minutes)  
```javascript
// 1. Add global stake
await whetuToken.approve(globalStaking.target, ethers.parseEther("300"));
await globalStaking.addGlobalStake(ethers.parseEther("300"));

// 2. Register as neuron with automatic allocation
await neuronManager.registerNeuronWithStakeAllocation(
    netuid, ethers.parseEther("300"), false, // false = miner
    "http://127.0.0.1:8091", 8091, "http://127.0.0.1:9091", 9091
);
```

---

## 📖 Detailed Guides

### Subnet Registration Guide
**[→ Read the full Subnet Registration Guide](./Subnet-Registration-Guide.md)**

This comprehensive guide covers:
- Prerequisites and preparation
- Step-by-step registration process
- Custom hyperparameter configuration
- Verification and troubleshooting
- Advanced subnet management
- Complete code examples

### Neuron Registration Guide  
**[→ Read the full Neuron Registration Guide](./Neuron-Registration-Guide.md)**

This detailed guide includes:
- Understanding miner vs validator roles
- Global staking setup and management
- Multiple registration methods
- Multi-subnet participation strategies
- Stake optimization techniques
- Monitoring and management tools

---

## 🛠️ API Quick Reference

### SubnetManager
```javascript
// Register a subnet
await subnetManager.registerNetwork(name, description, tokenName, tokenSymbol);

// Get subnet info
const info = await subnetManager.getSubnetInfo(netuid);
const params = await subnetManager.getSubnetParams(netuid);
```

### NeuronManager
```javascript
// Register as neuron (one-step)
await neuronManager.registerNeuronWithStakeAllocation(
    netuid, stakeAmount, isValidator, axonEndpoint, axonPort, promEndpoint, promPort
);

// Get neuron info
const neuronInfo = await neuronManager.getNeuronInfo(netuid, address);
```

### GlobalStaking
```javascript
// Add global stake
await globalStaking.addGlobalStake(amount);

// Allocate to subnet
await globalStaking.allocateToSubnet(netuid, amount);

// Check allocations
const available = await globalStaking.getAvailableStake(address, netuid);
const effective = await globalStaking.getEffectiveStake(address, netuid);
```

---

## 🧪 Testing and Development

### Running Tests
```bash
# Test subnet registration
npx hardhat test test/SubnetManager.test.js

# Test neuron registration and management
npx hardhat test test/NeuronManager.test.js

# Test staking functionality
npx hardhat test test/GlobalStaking.test.js

# Run all tests
npx hardhat test
```

### Development Setup
```bash
# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Deploy locally
npx hardhat node
npx hardhat run scripts/deploy-ignition.js --network localhost
```

---

## 🚨 Important Notes

### Security Considerations
- Always test on testnet before mainnet deployment
- Verify contract addresses before interacting
- Use proper error handling in production code
- Monitor gas costs for complex operations

### Best Practices
- Check balances and allowances before transactions
- Implement proper event monitoring
- Use rate limiting respect network limits
- Keep detailed logs for debugging

### Common Pitfalls
- Not wrapping HETU to WHETU before contract interactions
- Forgetting to approve token spending before operations
- Not checking rate limits before subnet registration
- Insufficient stake for desired neuron role

---

## 📞 Support and Resources

### Documentation
- **[Subnet Registration Guide](./Subnet-Registration-Guide.md)** - Complete subnet creation guide
- **[Neuron Registration Guide](./Neuron-Registration-Guide.md)** - Comprehensive participation guide
- **Test Files** - Extensive examples in the `test/` directory
- **Contract Source** - Full implementation in the `contracts/` directory

### Getting Help
- Review the test files for working examples
- Check the detailed guides for step-by-step instructions
- Examine error messages carefully for debugging hints
- Use the verification steps to confirm successful operations

---

*This documentation provides an overview of the Hetu Subnet Contract system. For detailed implementation guidance, please refer to the specialized guides linked above.*

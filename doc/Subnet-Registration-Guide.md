# How to Register a Subnet

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step-by-Step Guide](#step-by-step-guide)
4. [Advanced Registration Options](#advanced-registration-options)
5. [Verification](#verification)
6. [API Reference](#api-reference)
7. [Examples](#examples)
8. [Troubleshooting](#troubleshooting)

---

## Overview

Subnet registration in the Hetu network allows you to create your own decentralized AI subnet with the following components:

- **Custom Alpha Token**: Each subnet has its own ERC-20 token for incentives
- **AMM Pool**: Automated market making pool for token trading
- **Hyperparameters**: Configurable network parameters for consensus and rewards
- **Governance**: Full control over subnet settings and participants

### What You Get After Registration

✅ **Unique Subnet ID (netuid)**: Your subnet's identifier in the network  
✅ **Alpha Token Contract**: ERC-20 token for your subnet  
✅ **AMM Pool**: Liquidity pool for HETU ↔ Alpha Token trading  
✅ **Full Ownership**: Complete control over subnet parameters  
✅ **Neuron Management**: Ability to accept miners and validators  

---

## Prerequisites

### 1. HETU Tokens
You need sufficient HETU tokens to pay for subnet registration. The cost is dynamic and increases with network activity.

### 2. WHETU (Wrapped HETU)
Native HETU must be wrapped to WHETU (ERC-20 format) for contract interactions.

### 3. Rate Limit Compliance
There's a block interval requirement between registrations to prevent spam.

### 4. Contract Addresses
Ensure you have the correct deployed contract addresses:
- `WHETU Token Contract`
- `SubnetManager Contract`

---

## Step-by-Step Guide

### Step 1: Wrap Native HETU to WHETU

```javascript
// Wrap 1000 HETU to WHETU
const hetuAmount = ethers.parseEther("1000");
await whetuToken.connect(user).deposit({ value: hetuAmount });

// Verify your WHETU balance
const whetuBalance = await whetuToken.balanceOf(user.address);
console.log(`WHETU Balance: ${ethers.formatEther(whetuBalance)} WHETU`);

// Expected output: "WHETU Balance: 1000.0 WHETU"
```

### Step 2: Check Registration Cost

The registration cost is dynamic and decreases over time to prevent spam while allowing fair access.

```javascript
// Get current network lock cost
const lockCost = await subnetManager.getNetworkLockCost();
console.log(`Current Registration Cost: ${ethers.formatEther(lockCost)} HETU`);

// Check if you have sufficient balance
const userBalance = await whetuToken.balanceOf(user.address);
if (userBalance < lockCost) {
    throw new Error(`Insufficient balance. Need: ${ethers.formatEther(lockCost)} HETU, Have: ${ethers.formatEther(userBalance)} HETU`);
}

console.log(`✅ Sufficient balance for registration`);
```

### Step 3: Approve Token Transfer

```javascript
// Approve SubnetManager to spend your HETU tokens
await whetuToken.connect(user).approve(subnetManager.target, lockCost);

// Verify approval
const allowance = await whetuToken.allowance(user.address, subnetManager.target);
console.log(`Approved Amount: ${ethers.formatEther(allowance)} HETU`);
```

### Step 4: Check and Wait for Rate Limit

```javascript
// Check current rate limit status
const currentBlock = await ethers.provider.getBlockNumber();
const lastLockBlock = await subnetManager.networkLastLockBlock();
const rateLimit = await subnetManager.networkRateLimit();

const blocksSinceLastLock = currentBlock - lastLockBlock;
console.log(`Blocks since last registration: ${blocksSinceLastLock}`);
console.log(`Rate limit requirement: ${rateLimit} blocks`);

if (blocksSinceLastLock < rateLimit) {
    const blocksToWait = rateLimit - blocksSinceLastLock;
    console.log(`⏳ Need to wait ${blocksToWait} more blocks...`);
    
    // In a real application, you would wait or schedule for later
    // For testing, you can advance blocks:
    await time.advanceBlockTo(currentBlock + blocksToWait);
    console.log(`✅ Rate limit satisfied`);
} else {
    console.log(`✅ Rate limit already satisfied`);
}
```

### Step 5: Register Your Subnet

#### Basic Registration

```javascript
// Register subnet with basic parameters
const tx = await subnetManager.connect(user).registerNetwork(
    "My AI Subnet",                    // Subnet name
    "A subnet for AI model training",  // Subnet description  
    "MyToken",                         // Alpha token name
    "MYT"                             // Alpha token symbol (3-4 characters recommended)
);

console.log(`📤 Transaction submitted: ${tx.hash}`);

// Wait for transaction confirmation
const receipt = await tx.wait();
console.log(`✅ Transaction confirmed in block ${receipt.blockNumber}`);
```

#### Parse Registration Event

```javascript
// Extract the assigned subnet ID from transaction events
let netuid;
let alphaTokenAddress;
let ammPoolAddress;

for (const log of receipt.logs) {
    try {
        const decoded = subnetManager.interface.parseLog(log);
        if (decoded.name === "NetworkRegistered") {
            netuid = decoded.args.netuid;
            alphaTokenAddress = decoded.args.alphaToken;
            ammPoolAddress = decoded.args.ammPool;
            break;
        }
    } catch (e) {
        // Skip logs that don't match the expected interface
    }
}

if (netuid) {
    console.log(`🎉 Subnet successfully registered!`);
    console.log(`   Subnet ID: ${netuid}`);
    console.log(`   Alpha Token: ${alphaTokenAddress}`);
    console.log(`   AMM Pool: ${ammPoolAddress}`);
} else {
    throw new Error("Failed to parse registration event");
}
```

---

## Advanced Registration Options

### Register with Custom Hyperparameters

For advanced users who want to customize their subnet's consensus and reward mechanisms:

```javascript
// Define custom hyperparameters
const customHyperparams = {
    rho: 100,                           // Reward distribution parameter
    kappa: 200,                         // Consensus mechanism parameter
    immunityPeriod: 500,                // Protection period for new neurons (blocks)
    minAllowedWeights: 5,               // Minimum weights a neuron can set
    maxWeightLimit: 1000,               // Maximum weight limit
    tempo: 100,                         // Network update frequency (blocks)
    minDifficulty: 1000,                // Minimum PoW difficulty
    maxDifficulty: 100000,              // Maximum PoW difficulty
    weightsVersion: 1,                  // Version for weight compatibility
    weightsRateLimit: 100,              // Rate limit for weight updates
    adjustmentInterval: 1000,           // Difficulty adjustment interval
    activityCutoff: 5000,               // Inactivity threshold (blocks)
    registrationAllowed: true,          // Whether new registrations are allowed
    targetRegistrationsPerInterval: 2,  // Target new registrations per interval
    minBurn: ethers.parseEther("1"),    // Minimum burn for registration
    maxBurn: ethers.parseEther("100"),  // Maximum burn for registration
    bondsMovingAvg: 900000,             // Moving average for bond calculations
    maxRegistrationsPerBlock: 1,        // Max registrations per block
    adjustmentAlpha: 58000,             // Alpha parameter for adjustments
    difficultyRecycleInterval: 36,      // Difficulty recycle interval
    immunityPeriodBurns: 2,             // Immunity period for burn mechanism
    maxAllowedUids: 256,                // Maximum number of neurons
    maxAllowedValidators: 128,          // Maximum number of validators
    minStakeIncrease: ethers.parseEther("1"),    // Minimum stake increase
    maxStakeIncrease: ethers.parseEther("100"),  // Maximum stake increase
    validatorThreshold: ethers.parseEther("500"), // Minimum stake for validators
    neuronThreshold: ethers.parseEther("100"),    // Minimum stake for neurons
    baseBurnCost: ethers.parseEther("5")          // Base cost for neuron registration
};

// Specify which parameters to customize (true = use custom, false = use default)
const useCustomFlags = [
    true,  // rho - use custom value
    true,  // kappa - use custom value
    true,  // immunityPeriod - use custom value
    false, // minAllowedWeights - use default
    false, // maxWeightLimit - use default
    true,  // tempo - use custom value
    false, // minDifficulty - use default
    false, // maxDifficulty - use default
    false, // weightsVersion - use default
    true,  // weightsRateLimit - use custom value
    false, // adjustmentInterval - use default
    false, // activityCutoff - use default
    true,  // registrationAllowed - use custom value
    false, // targetRegistrationsPerInterval - use default
    true,  // minBurn - use custom value
    true,  // maxBurn - use custom value
    false, // bondsMovingAvg - use default
    false, // maxRegistrationsPerBlock - use default
    false, // adjustmentAlpha - use default
    false, // difficultyRecycleInterval - use default
    false, // immunityPeriodBurns - use default
    true,  // maxAllowedUids - use custom value
    true,  // maxAllowedValidators - use custom value
    false, // minStakeIncrease - use default
    false, // maxStakeIncrease - use default
    true,  // validatorThreshold - use custom value
    true,  // neuronThreshold - use custom value
    true   // baseBurnCost - use custom value
];

// Register with custom parameters
const advancedTx = await subnetManager.connect(user).registerNetworkWithPartialCustom(
    "Advanced AI Subnet",
    "Subnet with custom consensus parameters",
    "AdvToken",
    "ADV",
    customHyperparams,
    useCustomFlags
);

const advancedReceipt = await advancedTx.wait();
console.log(`🚀 Advanced subnet registered with custom parameters!`);
```

### Using Permit for Gasless Approval (Advanced)

If the WHETU token supports EIP-2612 permits, you can combine approval and registration in a single transaction:

```javascript
// This is an advanced feature - check if your WHETU token supports permits
const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

// Create permit signature (implementation depends on your wallet/signing setup)
const permitSignature = await createPermitSignature(
    user,
    subnetManager.target,
    lockCost,
    deadline
);

// Register with permit (saves one transaction)
await subnetManager.connect(user).registerNetworkWithPermit(
    "Permit Subnet",
    "Registered using permit",
    "PermitToken",
    "PERM",
    lockCost,
    deadline,
    permitSignature.v,
    permitSignature.r,
    permitSignature.s
);
```

---

## Verification

After successful registration, verify your subnet is properly configured:

### Basic Subnet Information

```javascript
// Check if subnet exists
const exists = await subnetManager.subnetExists(netuid);
console.log(`Subnet ${netuid} exists: ${exists}`);

// Get comprehensive subnet information
const subnetInfo = await subnetManager.getSubnetInfo(netuid);
console.log(`📊 Subnet Information:`);
console.log(`   Owner: ${subnetInfo.owner}`);
console.log(`   Name: ${subnetInfo.name}`);
console.log(`   Description: ${subnetInfo.description}`);
console.log(`   Alpha Token: ${subnetInfo.alphaToken}`);
console.log(`   AMM Pool: ${subnetInfo.ammPool}`);
console.log(`   Registration Block: ${subnetInfo.registrationBlock}`);
console.log(`   Is Active: ${subnetInfo.isActive}`);
```

### Subnet Parameters

```javascript
// Get subnet hyperparameters
const params = await subnetManager.getSubnetParams(netuid);
console.log(`⚙️ Subnet Parameters:`);
console.log(`   Validator Threshold: ${ethers.formatEther(params.validatorThreshold)} HETU`);
console.log(`   Neuron Threshold: ${ethers.formatEther(params.neuronThreshold)} HETU`);
console.log(`   Base Burn Cost: ${ethers.formatEther(params.baseBurnCost)} HETU`);
console.log(`   Max Allowed UIDs: ${params.maxAllowedUids}`);
console.log(`   Max Allowed Validators: ${params.maxAllowedValidators}`);
console.log(`   Tempo: ${params.tempo} blocks`);
console.log(`   Registration Allowed: ${params.registrationAllowed}`);
```

### Alpha Token Verification

```javascript
// Verify Alpha Token was created correctly
const AlphaToken = await ethers.getContractFactory("AlphaToken");
const alphaToken = AlphaToken.attach(subnetInfo.alphaToken);

const tokenName = await alphaToken.name();
const tokenSymbol = await alphaToken.symbol();
const tokenDecimals = await alphaToken.decimals();
const tokenOwner = await alphaToken.owner();

console.log(`🪙 Alpha Token Details:`);
console.log(`   Name: ${tokenName}`);
console.log(`   Symbol: ${tokenSymbol}`);
console.log(`   Decimals: ${tokenDecimals}`);
console.log(`   Owner: ${tokenOwner}`);
console.log(`   Address: ${subnetInfo.alphaToken}`);
```

### AMM Pool Verification

```javascript
// Verify AMM Pool was created correctly
const SubnetAMM = await ethers.getContractFactory("SubnetAMM");
const ammPool = SubnetAMM.attach(subnetInfo.ammPool);

const poolHetuToken = await ammPool.hetuToken();
const poolAlphaToken = await ammPool.alphaToken();
const poolOwner = await ammPool.owner();

console.log(`🏊 AMM Pool Details:`);
console.log(`   HETU Token: ${poolHetuToken}`);
console.log(`   Alpha Token: ${poolAlphaToken}`);
console.log(`   Pool Owner: ${poolOwner}`);
console.log(`   Pool Address: ${subnetInfo.ammPool}`);
```

---

## API Reference

### SubnetManager Core Functions

#### `registerNetwork(name, description, tokenName, tokenSymbol)`
Registers a basic subnet with default hyperparameters.

**Parameters:**
- `name` (string): Subnet name
- `description` (string): Subnet description
- `tokenName` (string): Alpha token name
- `tokenSymbol` (string): Alpha token symbol

**Returns:** Transaction object

**Events Emitted:** `NetworkRegistered(netuid, owner, name, alphaToken, ammPool)`

#### `registerNetworkWithPartialCustom(name, description, tokenName, tokenSymbol, hyperparams, useCustomFlags)`
Registers a subnet with custom hyperparameters.

**Parameters:**
- `name` (string): Subnet name
- `description` (string): Subnet description  
- `tokenName` (string): Alpha token name
- `tokenSymbol` (string): Alpha token symbol
- `hyperparams` (struct): Custom hyperparameter values
- `useCustomFlags` (bool[]): Array indicating which parameters to customize

#### `getNetworkLockCost()`
Returns the current dynamic cost for subnet registration.

**Returns:** `uint256` - Cost in HETU tokens

#### `getSubnetInfo(netuid)`
Returns comprehensive information about a subnet.

**Returns:** SubnetInfo struct with all subnet details

#### `getSubnetParams(netuid)`
Returns the hyperparameters for a subnet.

**Returns:** SubnetHyperparams struct with all parameters

#### `subnetExists(netuid)`
Checks if a subnet exists.

**Returns:** `bool` - True if subnet exists

---

### Best Practices

1. **Test First**: Always test your registration on a testnet before mainnet
2. **Check Costs**: Registration costs are dynamic - check before each registration
3. **Handle Rate Limits**: Implement proper waiting mechanisms for rate limits
4. **Verify Parameters**: Validate custom hyperparameters before submission
5. **Monitor Events**: Listen for registration events to confirm success
6. **Error Handling**: Implement comprehensive error handling for all edge cases
7. **Gas Management**: Consider gas costs for complex registrations with custom parameters

### Getting Help

- **Contract Events**: Monitor blockchain events for detailed error information
- **Test Files**: Reference the test files for working examples
- **Parameter Validation**: Use the default parameters as a reference for valid ranges
- **Community**: Join the developer community for support and best practices

---

This completes the comprehensive guide for subnet registration. The next step would be to register neurons in your subnet - refer to the "How to Register Neurons" documentation for that process.

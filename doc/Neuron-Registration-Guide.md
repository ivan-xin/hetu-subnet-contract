# How to Register Neurons (Miners and Validators)

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Understanding Roles](#understanding-roles)
4. [Step-by-Step Guide](#step-by-step-guide)
5. [Registration Methods](#registration-methods)
6. [Advanced Usage](#advanced-usage)
7. [Management and Monitoring](#management-and-monitoring)
8. [API Reference](#api-reference)
9. [Examples](#examples)
10. [Troubleshooting](#troubleshooting)

---

## Overview

Neuron registration allows you to participate in Hetu subnets as either a **Miner** or **Validator**. Neurons are the computing nodes that contribute to the AI network and earn rewards for their participation.

### What Happens When You Register

✅ **Stake Allocation**: Your HETU tokens are allocated to the specific subnet  
✅ **Role Assignment**: You become either a Miner or Validator based on your stake  
✅ **Network Participation**: You can start participating in consensus and earning rewards  
✅ **Endpoint Registration**: Your service endpoints are registered for other neurons to connect  
✅ **Unique ID**: You receive a unique identifier (UID) within the subnet  

### Key Benefits

- **Earn Rewards**: Get compensated for contributing computing resources
- **Multiple Subnets**: Participate in multiple subnets simultaneously  
- **Flexible Staking**: Adjust your stake allocation across different subnets
- **Role Flexibility**: Switch between Miner and Validator roles based on stake

---

## Prerequisites

### 1. Active Subnet
You need a registered and active subnet to join. You can either:
- Create your own subnet (see [Subnet Registration Guide](./Subnet-Registration-Guide.md))
- Join an existing subnet created by others

### 2. HETU Tokens and Global Staking
You must have HETU tokens staked in the GlobalStaking contract:

```javascript
// Minimum requirements vary by subnet, typically:
// - Miners: 100+ HETU 
// - Validators: 500+ HETU
```

### 3. Service Endpoints
You need to provide endpoints for your neuron services:
- **Axon Endpoint**: Your main service endpoint for serving requests
- **Prometheus Endpoint**: Monitoring and metrics endpoint

### 4. Contract Addresses
Ensure you have the correct deployed contract addresses:
- `GlobalStaking Contract`
- `NeuronManager Contract`
- `SubnetManager Contract`

---

## Understanding Roles

### Miners 🔨
Miners provide computing resources and process AI tasks.

**Characteristics:**
- Lower stake requirement (typically 100+ HETU)
- Process inference requests and training tasks
- Earn rewards based on performance and availability
- Can serve multiple types of AI workloads

**Responsibilities:**
- Maintain high availability for service endpoints
- Process requests efficiently and accurately
- Update weights and participate in consensus
- Maintain good performance metrics

### Validators ✅
Validators verify the quality of miners' work and participate in consensus.

**Characteristics:**
- Higher stake requirement (typically 500+ HETU)
- Validate miners' outputs and performance
- Have voting power in network decisions
- Earn rewards for accurate validation

**Responsibilities:**
- Evaluate miner performance objectively
- Participate in weight setting and consensus
- Maintain high availability and reliability
- Make fair and accurate assessments

### Stake Requirements

Each subnet can set its own stake requirements:

```javascript
// Example subnet requirements
const subnetParams = await subnetManager.getSubnetParams(netuid);
console.log(`Miner Threshold: ${ethers.formatEther(subnetParams.neuronThreshold)} HETU`);
console.log(`Validator Threshold: ${ethers.formatEther(subnetParams.validatorThreshold)} HETU`);
```

---

## Step-by-Step Guide

### Step 1: Set Up Global Staking

First, you need to add HETU tokens to the global staking contract:

```javascript
// Wrap HETU to WHETU if needed
const stakeAmount = ethers.parseEther("1000"); // 1000 HETU
await whetuToken.connect(user).deposit({ value: stakeAmount });

// Approve GlobalStaking contract
await whetuToken.connect(user).approve(globalStaking.target, stakeAmount);

// Add to global staking pool
await globalStaking.connect(user).addGlobalStake(stakeAmount);

// Verify your global stake
const stakeInfo = await globalStaking.getStakeInfo(user.address);
console.log(`Total Staked: ${ethers.formatEther(stakeInfo.totalStaked)} HETU`);
console.log(`Available for Allocation: ${ethers.formatEther(stakeInfo.availableForAllocation)} HETU`);
```

### Step 2: Choose Your Target Subnet

```javascript
// Get information about available subnets
const netuid = 1; // Example subnet ID

// Check if subnet exists and is active
const subnetExists = await subnetManager.subnetExists(netuid);
const subnetInfo = await subnetManager.getSubnetInfo(netuid);

if (!subnetExists || !subnetInfo.isActive) {
    throw new Error(`Subnet ${netuid} is not available for registration`);
}

console.log(`Target Subnet: ${subnetInfo.name}`);
console.log(`Description: ${subnetInfo.description}`);
console.log(`Owner: ${subnetInfo.owner}`);
```

### Step 3: Check Subnet Requirements

```javascript
// Get subnet parameters to understand requirements
const subnetParams = await subnetManager.getSubnetParams(netuid);

console.log(`📊 Subnet Requirements:`);
console.log(`   Miner Threshold: ${ethers.formatEther(subnetParams.neuronThreshold)} HETU`);
console.log(`   Validator Threshold: ${ethers.formatEther(subnetParams.validatorThreshold)} HETU`);
console.log(`   Registration Cost: ${ethers.formatEther(subnetParams.baseBurnCost)} HETU`);
console.log(`   Max Neurons: ${subnetParams.maxAllowedUids}`);
console.log(`   Max Validators: ${subnetParams.maxAllowedValidators}`);

// Check current capacity
const currentNeuronCount = await neuronManager.getSubnetNeuronCount(netuid);
const currentValidatorCount = await neuronManager.getSubnetValidatorCount(netuid);

console.log(`📈 Current Capacity:`);
console.log(`   Current Neurons: ${currentNeuronCount}/${subnetParams.maxAllowedUids}`);
console.log(`   Current Validators: ${currentValidatorCount}/${subnetParams.maxAllowedValidators}`);
```

### Step 4: Determine Your Role and Stake Amount

```javascript
// Decide your role based on your available stake and preferences
const availableStake = await globalStaking.getAvailableStake(user.address, netuid);

// For Miner role
const minerStakeAmount = ethers.parseEther("200"); // Above neuron threshold
const canBeMiner = availableStake >= minerStakeAmount && 
                   minerStakeAmount >= subnetParams.neuronThreshold;

// For Validator role  
const validatorStakeAmount = ethers.parseEther("600"); // Above validator threshold
const canBeValidator = availableStake >= validatorStakeAmount && 
                      validatorStakeAmount >= subnetParams.validatorThreshold &&
                      currentValidatorCount < subnetParams.maxAllowedValidators;

console.log(`💰 Stake Analysis:`);
console.log(`   Available: ${ethers.formatEther(availableStake)} HETU`);
console.log(`   Can be Miner: ${canBeMiner} (need ${ethers.formatEther(subnetParams.neuronThreshold)} HETU)`);
console.log(`   Can be Validator: ${canBeValidator} (need ${ethers.formatEther(subnetParams.validatorThreshold)} HETU)`);

// Choose your role
const isValidatorRole = canBeValidator; // true for validator, false for miner
const stakeAmount = isValidatorRole ? validatorStakeAmount : minerStakeAmount;

console.log(`🎯 Selected Role: ${isValidatorRole ? 'Validator' : 'Miner'}`);
console.log(`🎯 Stake Amount: ${ethers.formatEther(stakeAmount)} HETU`);
```

---

## Registration Methods

### One-Step Registration (Recommended)

This method allocates stake and registers the neuron in a single transaction:

```javascript
// Define your service endpoints
const axonEndpoint = "http://127.0.0.1:8091";      // Your main service endpoint
const axonPort = 8091;                              // Port for axon service
const prometheusEndpoint = "http://127.0.0.1:9091"; // Metrics endpoint
const prometheusPort = 9091;                        // Port for metrics

// Register neuron with automatic stake allocation
const tx = await neuronManager.connect(user).registerNeuronWithStakeAllocation(
    netuid,                    // Subnet ID
    stakeAmount,              // Amount to allocate to this subnet
    isValidatorRole,          // true for validator, false for miner
    axonEndpoint,             // Your axon service endpoint
    axonPort,                 // Axon service port
    prometheusEndpoint,       // Prometheus metrics endpoint
    prometheusPort            // Prometheus metrics port
);

console.log(`📤 Registration transaction submitted: ${tx.hash}`);

// Wait for confirmation
const receipt = await tx.wait();
console.log(`✅ Neuron registered successfully in block ${receipt.blockNumber}`);

// Parse registration event for details
let registrationEvent;
for (const log of receipt.logs) {
    try {
        const decoded = neuronManager.interface.parseLog(log);
        if (decoded.name === "NeuronRegistered") {
            registrationEvent = decoded;
            break;
        }
    } catch (e) {}
}

if (registrationEvent) {
    console.log(`🎉 Registration Details:`);
    console.log(`   Subnet: ${registrationEvent.args.netuid}`);
    console.log(`   Account: ${registrationEvent.args.account}`);
    console.log(`   Stake: ${ethers.formatEther(registrationEvent.args.stake)} HETU`);
    console.log(`   Role: ${registrationEvent.args.isValidator ? 'Validator' : 'Miner'}`);
    console.log(`   Block: ${registrationEvent.args.registrationBlock}`);
}
```

---

## Management and Monitoring

### Checking Your Neuron Status

```javascript
async function checkNeuronStatus() {
    const user = await ethers.getSigners()[0];
    const netuid = 1;
    
    // Check if neuron exists
    const exists = await neuronManager.neuronExists(netuid, user.address);
    console.log(`Neuron exists in subnet ${netuid}: ${exists}`);
    
    if (exists) {
        // Get detailed neuron information
        const neuronInfo = await neuronManager.getNeuronInfo(netuid, user.address);
        const effectiveStake = await globalStaking.getEffectiveStake(user.address, netuid);
        const lockedStake = await globalStaking.getLockedStake(user.address, netuid);
        const unlockedStake = await globalStaking.getUnlockedStakeInSubnet(user.address, netuid);
        
        console.log(`\n📊 Neuron Status:`);
        console.log(`   Active: ${neuronInfo.isActive}`);
        console.log(`   Role: ${neuronInfo.isValidator ? 'Validator' : 'Miner'}`);
        console.log(`   UID: ${neuronInfo.uid}`);
        console.log(`   Registration Block: ${neuronInfo.registrationBlock}`);
        console.log(`   Last Update: ${new Date(Number(neuronInfo.lastUpdate) * 1000).toISOString()}`);
        
        console.log(`\n💰 Stake Information:`);
        console.log(`   Total Effective Stake: ${ethers.formatEther(effectiveStake)} HETU`);
        console.log(`   Locked Stake: ${ethers.formatEther(lockedStake)} HETU`);
        console.log(`   Unlocked Stake: ${ethers.formatEther(unlockedStake)} HETU`);
        
        console.log(`\n🌐 Service Endpoints:`);
        console.log(`   Axon: ${neuronInfo.axonEndpoint}:${neuronInfo.axonPort}`);
        console.log(`   Prometheus: ${neuronInfo.prometheusEndpoint}:${neuronInfo.prometheusPort}`);
    }
}
```

### Deregistering from Subnets

```javascript
async function deregisterFromSubnet() {
    const user = await ethers.getSigners()[0];
    const netuid = 1;
    
    // Check current status
    const neuronExists = await neuronManager.neuronExists(netuid, user.address);
    
    if (neuronExists) {
        console.log(`📤 Deregistering from subnet ${netuid}...`);
        
        // Deregister neuron
        const tx = await neuronManager.connect(user).deregisterNeuron(netuid);
        await tx.wait();
        
        console.log(`✅ Successfully deregistered from subnet ${netuid}`);
        
        // Optionally remove stake allocation
        const currentStake = await globalStaking.getEffectiveStake(user.address, netuid);
        if (currentStake > 0) {
            console.log(`💰 Current stake allocation: ${ethers.formatEther(currentStake)} HETU`);
            
            // You can choose to:
            // 1. Keep the allocation for future re-registration
            // 2. Remove the allocation to free up stake
            
            const removeAllocation = true; // Set based on your preference
            
            if (removeAllocation) {
                await globalStaking.connect(user).allocateToSubnet(netuid, 0);
                console.log(`✅ Removed stake allocation from subnet ${netuid}`);
            } else {
                console.log(`ℹ️ Keeping stake allocation for potential re-registration`);
            }
        }
    } else {
        console.log(`❌ No active neuron found in subnet ${netuid}`);
    }
}
```

---

## API Reference

### NeuronManager Core Functions

#### `registerNeuronWithStakeAllocation(netuid, stakeAmount, isValidatorRole, axonEndpoint, axonPort, prometheusEndpoint, prometheusPort)`
Registers a neuron with automatic stake allocation in one transaction.

**Parameters:**
- `netuid` (uint16): Target subnet ID
- `stakeAmount` (uint256): Amount of HETU to allocate to this subnet
- `isValidatorRole` (bool): true for validator, false for miner
- `axonEndpoint` (string): Your main service endpoint URL
- `axonPort` (uint32): Port for axon service
- `prometheusEndpoint` (string): Metrics endpoint URL
- `prometheusPort` (uint32): Port for metrics service

**Events Emitted:** `NeuronRegistered(netuid, account, stake, isValidator, wasValidatorRequested, axonEndpoint, axonPort, prometheusEndpoint, prometheusPort, registrationBlock)`

#### `registerNeuron(netuid, isValidatorRole, axonEndpoint, axonPort, prometheusEndpoint, prometheusPort)`
Registers a neuron using existing stake allocation.

**Requirements:** Must have sufficient stake already allocated to the target subnet.

#### `deregisterNeuron(netuid)`
Removes the neuron from the subnet.

**Effects:** 
- Neuron becomes inactive
- Locked stake is unlocked
- Neuron is removed from subnet's active list

#### `getNeuronInfo(netuid, account)`
Returns complete information about a neuron.

**Returns:** NeuronInfo struct with all neuron details

#### `neuronExists(netuid, account)`
Checks if an account has an active neuron in the subnet.

**Returns:** `bool` - True if neuron exists and is active

### GlobalStaking Functions for Neurons

#### `allocateToSubnet(netuid, amount)`
Allocates your global stake to a specific subnet.

#### `allocateToSubnetWithMinThreshold(netuid, amount, minThreshold)`
Allocates stake with custom threshold validation.

#### `getEffectiveStake(user, netuid)`
Returns the total stake allocated to a subnet.

#### `getAvailableStake(user, netuid)`
Returns the global stake available for new allocations.

#### `getUnlockedStakeInSubnet(user, netuid)`
Returns the unlocked stake within a specific subnet.

---

### Best Practices

1. **Start Small**: Begin with miner roles to understand the network before becoming a validator
2. **Monitor Performance**: Keep track of your neuron's performance and rewards
3. **Diversify**: Consider participating in multiple subnets to spread risk
4. **Maintain Endpoints**: Ensure your service endpoints are always accessible and responsive
5. **Stay Updated**: Monitor subnet parameter changes and adjust your strategy accordingly
6. **Backup Strategy**: Have contingency plans for stake reallocation if performance drops
7. **Security**: Secure your private keys and service infrastructure properly

### Getting Help

- **Test Networks**: Always test your setup on testnets before mainnet deployment
- **Monitor Events**: Watch blockchain events for detailed information about your operations
- **Community**: Join the developer community for best practices and troubleshooting
- **Documentation**: Keep this guide and the contract documentation handy for reference

---

This completes the comprehensive guide for neuron registration. Combined with the subnet registration guide, you now have complete documentation for participating in the Hetu network ecosystem.

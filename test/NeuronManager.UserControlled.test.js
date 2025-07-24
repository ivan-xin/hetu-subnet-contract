const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NeuronManager - User Controlled Allocation", function () {
  // Contract deployment fixture
  async function deployNeuronManagerFixture() {
    const [owner, creator, miner, validator, otherAccount] = await ethers.getSigners();

    // Deploy WHETU token
    const WHETU = await ethers.getContractFactory("WHETU");
    const whetuToken = await WHETU.deploy();

    // Deploy AMM Factory
    const SubnetAMMFactory = await ethers.getContractFactory("SubnetAMMFactory");
    const ammFactory = await SubnetAMMFactory.deploy(owner.address);

    // Deploy Subnet Manager
    const SubnetManager = await ethers.getContractFactory("SubnetManager");
    const subnetManager = await SubnetManager.deploy(whetuToken.target, ammFactory.target);

    // Deploy Global Staking
    const GlobalStaking = await ethers.getContractFactory("GlobalStaking");
    const globalStaking = await GlobalStaking.deploy(whetuToken.target, owner.address, owner.address);

    // Deploy Neuron Manager
    const NeuronManager = await ethers.getContractFactory("NeuronManager");
    const neuronManager = await NeuronManager.deploy(
      subnetManager.target,
      globalStaking.target,
      owner.address
    );

    // Set authorized callers
    await globalStaking.setAuthorizedCaller(neuronManager.target, true);

    return {
      owner,
      creator,
      miner,
      validator,
      otherAccount,
      whetuToken,
      ammFactory,
      subnetManager,
      globalStaking,
      neuronManager
    };
  }

  // Helper function to setup a subnet
  async function setupSubnet(fixtures) {
    const { creator, whetuToken, subnetManager } = fixtures;
    
    const hetuAmount = ethers.parseEther("2000");
    await whetuToken.connect(creator).deposit({ value: hetuAmount });
    
    const lockCost = await subnetManager.getNetworkLockCost();
    await whetuToken.connect(creator).approve(subnetManager.target, lockCost);
    
    await time.advanceBlockTo((await ethers.provider.getBlockNumber()) + 1001);
    
    const tx = await subnetManager.connect(creator).registerNetwork(
      "Test Subnet",
      "Subnet for neuron testing",
      "TestToken",
      "TEST"
    );
    
    const receipt = await tx.wait();
    
    // Parse registration event to get netuid
    let networkRegisteredEvent;
    for (const log of receipt.logs) {
      try {
        const decoded = subnetManager.interface.parseLog(log);
        if (decoded.name === "NetworkRegistered") {
          networkRegisteredEvent = decoded;
          break;
        }
      } catch (e) {
        // Skip logs that don't match
      }
    }
    
    return networkRegisteredEvent.args.netuid;
  }

  // Helper function to setup staking
  async function setupStaking(fixtures, user, amount = "1000") {
    const { whetuToken, globalStaking } = fixtures;
    
    const stakeAmount = ethers.parseEther(amount);
    await whetuToken.connect(user).deposit({ value: stakeAmount });
    await whetuToken.connect(user).approve(globalStaking.target, stakeAmount);
    await globalStaking.connect(user).addGlobalStake(stakeAmount);
    
    return stakeAmount;
  }

  describe("User Controlled Stake Allocation During Registration", function () {
    it("Should allow user to directly allocate and register in one flow", async function () {
      const fixtures = await loadFixture(deployNeuronManagerFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      // 1. Setup subnet
      const netuid = await setupSubnet(fixtures);
      console.log(`✅ Subnet created with netuid: ${netuid}`);
      
      // 2. Setup global staking only (no pre-allocation)
      await setupStaking(fixtures, miner, "1000");
      
      // 3. Check initial state
      let availableStake = await globalStaking.getAvailableStake(miner.address);
      console.log(`💰 Available stake before allocation: ${ethers.formatEther(availableStake)} HETU`);
      
      // 4. User registers neuron with custom stake allocation in one transaction
      const customStakeAmount = ethers.parseEther("300");
      const tx = await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        customStakeAmount,
        false, // Not validator
        "http://127.0.0.1:8091",
        8091,
        "http://127.0.0.1:9091",
        9091
      );
      
      await tx.wait();
      
      // 5. Verify allocation was created by user
      const allocation = await globalStaking.getSubnetAllocation(miner.address, netuid);
      expect(allocation.allocated).to.equal(customStakeAmount);
      
      // 6. Verify available stake reduced
      availableStake = await globalStaking.getAvailableStake(miner.address);
      const expectedAvailable = ethers.parseEther("1000") - customStakeAmount - allocation.cost;
      expect(availableStake).to.equal(expectedAvailable);
      
      // 7. Verify neuron registration
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.stake).to.equal(customStakeAmount);
      
      console.log(`✅ User directly allocated and registered: ${ethers.formatEther(customStakeAmount)} HETU`);
      console.log(`💰 Remaining available stake: ${ethers.formatEther(availableStake)} HETU`);
    });

    it("Should handle registration with existing stake", async function () {
      const fixtures = await loadFixture(deployNeuronManagerFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      // 1. Setup subnet and staking
      const netuid = await setupSubnet(fixtures);
      await setupStaking(fixtures, miner, "500");
      
      // 2. Register using the new unified method
      const allocationAmount = ethers.parseEther("200");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        allocationAmount,
        false,
        "http://127.0.0.1:8092",
        8092,
        "http://127.0.0.1:9092",
        9092
      );
      
      // 3. Verify registration and allocation
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.stake).to.equal(allocationAmount);
      
      const allocation = await globalStaking.getSubnetAllocation(miner.address, netuid);
      expect(allocation.allocated).to.equal(allocationAmount);
      
      console.log(`✅ Unified registration flow completed successfully`);
    });

    it("Should validate threshold during user allocation", async function () {
      const fixtures = await loadFixture(deployNeuronManagerFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      // 1. Setup subnet and staking
      const netuid = await setupSubnet(fixtures);
      await setupStaking(fixtures, miner, "1000");
      
      // 2. Try to register with insufficient stake (should fail)
      const insufficientStake = 50; // 50 wei, below neuron threshold of 100 wei
      
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          insufficientStake,
          false,
          "http://127.0.0.1:8093",
          8093,
          "http://127.0.0.1:9093",
          9093
        )
      ).to.be.revertedWith("INSUFFICIENT_NEURON_STAKE");
      
      console.log(`✅ Correctly rejected insufficient stake allocation`);
    });

    it("Should validate validator threshold during user allocation", async function () {
      const fixtures = await loadFixture(deployNeuronManagerFixture);
      const { validator, globalStaking, neuronManager } = fixtures;
      
      // 1. Setup subnet and staking
      const netuid = await setupSubnet(fixtures);
      await setupStaking(fixtures, validator, "1000");
      
      // 2. Try to register as validator with insufficient stake
      const insufficientValidatorStake = 500; // 500 wei, meets neuron threshold but not validator threshold
      
      await expect(
        neuronManager.connect(validator).registerNeuronWithStakeAllocation(
          netuid,
          insufficientValidatorStake,
          true, // Validator role
          "http://127.0.0.1:8094",
          8094,
          "http://127.0.0.1:9094",
          9094
        )
      ).to.be.revertedWith("INSUFFICIENT_VALIDATOR_STAKE");
      
      console.log(`✅ Correctly rejected insufficient validator stake`);
    });

    it("Should allow multiple allocations to different subnets", async function () {
      const fixtures = await loadFixture(deployNeuronManagerFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      // 1. Setup two subnets
      const netuid1 = await setupSubnet(fixtures);
      
      // Register second subnet - need more HETU for creator
      const { creator, whetuToken, subnetManager } = fixtures;
      const additionalHetu = ethers.parseEther("2000");
      await whetuToken.connect(creator).deposit({ value: additionalHetu });
      
      const lockCost = await subnetManager.getNetworkLockCost();
      await whetuToken.connect(creator).approve(subnetManager.target, lockCost);
      
      await time.advanceBlockTo((await ethers.provider.getBlockNumber()) + 1001);
      const tx2 = await subnetManager.connect(creator).registerNetwork(
        "Test Subnet 2",
        "Second subnet for testing",
        "TestToken2",
        "TEST2"
      );
      const receipt2 = await tx2.wait();
      let netuid2;
      for (const log of receipt2.logs) {
        try {
          const decoded = subnetManager.interface.parseLog(log);
          if (decoded.name === "NetworkRegistered") {
            netuid2 = decoded.args.netuid;
            break;
          }
        } catch (e) {}
      }
      
      // 2. Setup sufficient staking
      await setupStaking(fixtures, miner, "2000");
      
      // 3. Register in first subnet
      const allocation1 = ethers.parseEther("400");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid1,
        allocation1,
        false,
        "http://127.0.0.1:8095",
        8095,
        "http://127.0.0.1:9095",
        9095
      );
      
      // 4. Register in second subnet
      const allocation2 = ethers.parseEther("600");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid2,
        allocation2,
        true, // Validator in second subnet
        "http://127.0.0.1:8096",
        8096,
        "http://127.0.0.1:9096",
        9096
      );
      
      // 5. Verify both allocations
      const subnet1Allocation = await globalStaking.getSubnetAllocation(miner.address, netuid1);
      const subnet2Allocation = await globalStaking.getSubnetAllocation(miner.address, netuid2);
      expect(subnet1Allocation.allocated).to.equal(allocation1);
      expect(subnet2Allocation.allocated).to.equal(allocation2);
      
      // 6. Verify remaining available stake
      const availableStake = await globalStaking.getAvailableStake(miner.address);
      const totalCost = subnet1Allocation.cost + subnet2Allocation.cost;
      const expectedAvailable = ethers.parseEther("2000") - allocation1 - allocation2 - totalCost;
      expect(availableStake).to.equal(expectedAvailable);
      
      console.log(`✅ User allocated to multiple subnets:`);
      console.log(`   Subnet ${netuid1}: ${ethers.formatEther(subnet1Allocation.allocated)} HETU`);
      console.log(`   Subnet ${netuid2}: ${ethers.formatEther(subnet2Allocation.allocated)} HETU`);
      console.log(`   Remaining: ${ethers.formatEther(availableStake)} HETU`);
    });
  });
});

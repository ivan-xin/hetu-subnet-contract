const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NeuronManager", function () {
  // Basic fixture for deploying contracts
  async function deployFixture() {
    const [owner, creator, miner, validator] = await ethers.getSigners();

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

    // Set authorization
    await globalStaking.setAuthorizedCaller(neuronManager.target, true);

    return {
      owner,
      creator,
      miner,
      validator,
      whetuToken,
      subnetManager,
      globalStaking,
      neuronManager
    };
  }

  // Helper function to create subnet
  async function createSubnet(fixtures) {
    const { creator, whetuToken, subnetManager } = fixtures;
    
    // Get HETU and register subnet
    const hetuAmount = ethers.parseEther("2000");
    await whetuToken.connect(creator).deposit({ value: hetuAmount });
    
    const lockCost = await subnetManager.getNetworkLockCost();
    await whetuToken.connect(creator).approve(subnetManager.target, lockCost);
    
    // Wait for enough blocks
    await time.advanceBlockTo((await ethers.provider.getBlockNumber()) + 1001);
    
    const tx = await subnetManager.connect(creator).registerNetwork(
      "Test Subnet",
      "Test Description",
      "TestToken",
      "TEST"
    );
    
    const receipt = await tx.wait();
    const event = receipt.logs.find(log => {
      try {
        const decoded = subnetManager.interface.parseLog(log);
        return decoded.name === "NetworkRegistered";
      } catch (e) {
        return false;
      }
    });
    
    return event.args.netuid;
  }

  // Helper function to stake HETU
  async function stakeHetu(fixtures, user, amount = "1000") {
    const { whetuToken, globalStaking } = fixtures;
    
    const stakeAmount = ethers.parseEther(amount);
    await whetuToken.connect(user).deposit({ value: stakeAmount });
    await whetuToken.connect(user).approve(globalStaking.target, stakeAmount);
    await globalStaking.connect(user).addGlobalStake(stakeAmount);
    
    return stakeAmount;
  }

  describe("Neuron Registration Main Flow", function () {
    it("should successfully register miner neuron", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      // 1. Create subnet
      const netuid = await createSubnet(fixtures);
      
      // 2. User stakes HETU
      await stakeHetu(fixtures, miner, "500");
      
      // 3. Register miner neuron (complete allocation and registration in one step)
      const stakeAmount = ethers.parseEther("200");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        false, // Not a validator
        "http://127.0.0.1:8080",
        8080,
        "http://127.0.0.1:9090",
        9090
      );
      
      // 5. Verify registration result
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.false;
      expect(neuronInfo.stake).to.equal(stakeAmount);
    });

    it("should successfully register validator neuron", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { validator, globalStaking, neuronManager } = fixtures;
      
      // 1. Create subnet
      const netuid = await createSubnet(fixtures);
      
      // 2. Stake enough HETU (validators need more)
      await stakeHetu(fixtures, validator, "1200");
      
      // 3. Register validator neuron (complete allocation and registration in one step)
      const stakeAmount = ethers.parseEther("1100");
      await neuronManager.connect(validator).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        true, // Validator role
        "http://127.0.0.1:8081",
        8081,
        "http://127.0.0.1:9091",
        9091
      );
      
      // 5. Verify registration result
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, validator.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.true;
      expect(neuronInfo.stake).to.equal(stakeAmount);
    });

    it("should support custom stake allocation registration", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      // 1. Create subnet
      const netuid = await createSubnet(fixtures);
      
      // 2. User stakes HETU
      await stakeHetu(fixtures, miner, "2000");
      
      // 3. Use registerNeuronWithStakeAllocation to complete allocation and registration in one step
      const stakeAmount = ethers.parseEther("200");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        false,
        "http://127.0.0.1:8082",
        8082,
        "http://127.0.0.1:9092",
        9092
      );
      
      // 4. Verify registration result
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.false;
      expect(neuronInfo.stake).to.equal(stakeAmount);
      
      console.log("✅ registerNeuronWithStakeAllocation successful");
    });
  });

  describe("Registration Failure Scenarios", function () {
    it("should fail registration when stake is insufficient", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // Global stake is just not enough to pay registration cost and required stake
      await stakeHetu(fixtures, miner, "1.05"); // 1.05 HETU, not enough to pay registration cost (1 HETU) + stake requirement
      
      // Attempt to register when total demand exceeds available balance
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          ethers.parseEther("0.1"), // 0.1 HETU stake + 1 HETU registration cost = 1.1 HETU > 1.05 HETU
          false,
          "http://127.0.0.1:8083",
          8083,
          "http://127.0.0.1:9093",
          9093
        )
      ).to.be.revertedWith("INSUFFICIENT_AVAILABLE_STAKE");
    });

    it("should fail registration when validator stake is insufficient", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "1000");
      
      // Attempt to register as validator with insufficient stake
      const insufficientStake = 500; // 500 wei, meets neuron threshold but not validator threshold
      
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          insufficientStake,
          true, // Request validator role
          "http://127.0.0.1:8084",
          8084,
          "http://127.0.0.1:9094",
          9094
        )
      ).to.be.revertedWith("INSUFFICIENT_VALIDATOR_STAKE");
    });

    it("should fail on duplicate registration", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "500");
      
      // First registration
      const stakeAmount = ethers.parseEther("200");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        false,
        "http://127.0.0.1:8085",
        8085,
        "http://127.0.0.1:9095",
        9095
      );
      
      // Second registration should fail
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          ethers.parseEther("100"),
          false,
          "http://127.0.0.1:8086",
          8086,
          "http://127.0.0.1:9096",
          9096
        )
      ).to.be.revertedWith("ALREADY_REGISTERED");
    });
  });

  describe("Neuron Information Query", function () {
    it("should correctly query neuron information", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "500");
      
      const stakeAmount = ethers.parseEther("250");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        false,
        "http://test.com",
        8080,
        "http://metrics.test.com",
        9090
      );
      
      // Query neuron information
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      
      expect(neuronInfo.account).to.equal(miner.address);
      expect(neuronInfo.netuid).to.equal(netuid);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.false;
      expect(neuronInfo.stake).to.equal(stakeAmount);
      expect(neuronInfo.axonEndpoint).to.equal("http://test.com");
      expect(neuronInfo.axonPort).to.equal(8080);
    });

    it("should correctly check if neuron exists", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, validator, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // Check non-existing neuron
      expect(await neuronManager.isNeuron(netuid, miner.address)).to.be.false;
      
      // Register neuron
      await stakeHetu(fixtures, miner, "500");
      const stakeAmount = ethers.parseEther("200");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        false,
        "http://127.0.0.1:8087",
        8087,
        "http://127.0.0.1:9097",
        9097
      );
      
      // Check existing neuron
      expect(await neuronManager.isNeuron(netuid, miner.address)).to.be.true;
      
      // Check other user (should be false)
      expect(await neuronManager.isNeuron(netuid, validator.address)).to.be.false;
    });
  });
  
  describe("Registration Cost and Threshold Tests", function () {
    it("should correctly charge registration cost", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "1000");
      
      // Get initial treasury balance and user balance
      const { whetuToken, owner } = fixtures;
      const initialTreasuryBalance = await whetuToken.balanceOf(owner.address);
      const initialUserStake = await globalStaking.getStakeInfo(miner.address);
      
      const stakeAmount = ethers.parseEther("200");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        false,
        "http://127.0.0.1:8088",
        8088,
        "http://127.0.0.1:9098",
        9098
      );
      
      // Check if registration cost was correctly charged
      const finalUserStake = await globalStaking.getStakeInfo(miner.address);
      const finalTreasuryBalance = await whetuToken.balanceOf(owner.address);
      
      // Registration cost should be deducted from user stake and transferred to treasury
      expect(finalUserStake.totalCost).to.be.gt(0);
      expect(finalTreasuryBalance).to.be.gt(initialTreasuryBalance);
      
      console.log(`✅ Registration cost: ${ethers.formatEther(finalUserStake.totalCost)} HETU`);
    });

    it("should reject registration below neuron threshold", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "500");
      
      // Attempt to register with very low stake (below threshold)
      const lowStake = 50; // 50 wei, below neuron threshold of 100 wei
      
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          lowStake,
          false,
          "http://127.0.0.1:8089",
          8089,
          "http://127.0.0.1:9099",
          9099
        )
      ).to.be.revertedWith("INSUFFICIENT_NEURON_STAKE");
    });

    it("should correctly handle registration cost when stake is insufficient", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // Only stake just enough for allocation, but not enough to cover registration cost
      await stakeHetu(fixtures, miner, "200.1"); // Slightly more than 200, but not enough to cover registration cost
      
      const stakeAmount = ethers.parseEther("200");
      
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          stakeAmount,
          false,
          "http://127.0.0.1:8090",
          8090,
          "http://127.0.0.1:9100",
          9100
        )
      ).to.be.revertedWith("INSUFFICIENT_AVAILABLE_STAKE");
    });
  });

  describe("Query Function Tests", function () {
    it("should correctly query validator list", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, validator, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // Register a miner
      await stakeHetu(fixtures, miner, "500");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        ethers.parseEther("200"),
        false,
        "http://miner.com",
        8080,
        "http://miner-metrics.com",
        9090
      );
      
      // Register a validator
      await stakeHetu(fixtures, validator, "1200");
      await neuronManager.connect(validator).registerNeuronWithStakeAllocation(
        netuid,
        ethers.parseEther("1100"),
        true,
        "http://validator.com",
        8081,
        "http://validator-metrics.com",
        9091
      );
      
      // Query validators
      const validators = await neuronManager.getSubnetValidators(netuid);
      expect(validators.length).to.equal(1);
      expect(validators[0]).to.equal(validator.address);
      
      // Query validator count
      const validatorCount = await neuronManager.getSubnetValidatorCount(netuid);
      expect(validatorCount).to.equal(1);
      
      // Query total neuron count
      const neuronCount = await neuronManager.getNeuronCount(netuid);
      expect(neuronCount).to.equal(2);
    });

    it("should correctly check validator identity", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, validator, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // Register miner and validator
      await stakeHetu(fixtures, miner, "500");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        ethers.parseEther("200"),
        false,
        "http://miner.com",
        8080,
        "http://miner-metrics.com",
        9090
      );
      
      await stakeHetu(fixtures, validator, "1200");
      await neuronManager.connect(validator).registerNeuronWithStakeAllocation(
        netuid,
        ethers.parseEther("1100"),
        true,
        "http://validator.com",
        8081,
        "http://validator-metrics.com",
        9091
      );
      
      // Check identity
      expect(await neuronManager.isValidator(netuid, validator.address)).to.be.true;
      expect(await neuronManager.isValidator(netuid, miner.address)).to.be.false;
      
      expect(await neuronManager.isNeuron(netuid, validator.address)).to.be.true;
      expect(await neuronManager.isNeuron(netuid, miner.address)).to.be.true;
    });
  });

  describe("Service Information Update Tests", function () {
    it("should allow updating neuron service information", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "500");
      
      // Register neuron
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        ethers.parseEther("200"),
        false,
        "http://old-endpoint.com",
        8080,
        "http://old-metrics.com",
        9090
      );
      
      // Update service information
      await neuronManager.connect(miner).updateNeuronService(
        netuid,
        "http://new-endpoint.com",
        8081,
        "http://new-metrics.com",
        9091
      );
      
      // Verify update
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.axonEndpoint).to.equal("http://new-endpoint.com");
      expect(neuronInfo.axonPort).to.equal(8081);
      expect(neuronInfo.prometheusEndpoint).to.equal("http://new-metrics.com");
      expect(neuronInfo.prometheusPort).to.equal(9091);
    });

    it("unregistered neurons cannot update service information", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // Attempt to update service information for unregistered neuron
      await expect(
        neuronManager.connect(miner).updateNeuronService(
          netuid,
          "http://test.com",
          8080,
          "http://metrics.com",
          9090
        )
      ).to.be.revertedWith("NOT_REGISTERED");
    });
  });
});
const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GlobalStaking - Available Stake Logic", function () {
  async function deployGlobalStakingFixture() {
    const [owner, user1, user2] = await ethers.getSigners();

    // Deploy WHETU token
    const WHETU = await ethers.getContractFactory("WHETU");
    const whetuToken = await WHETU.deploy();

    // Deploy Global Staking
    const GlobalStaking = await ethers.getContractFactory("GlobalStaking");
    const globalStaking = await GlobalStaking.deploy(whetuToken.target, owner.address, owner.address);

    return {
      owner,
      user1,
      user2,
      whetuToken,
      globalStaking
    };
  }

  describe("Available Stake Calculation", function () {
    it("Should correctly calculate available stake after allocations", async function () {
      const { user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // 1. Add global stake
      const totalStake = ethers.parseEther("1000");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      // Verify initial state
      let availableStake = await globalStaking.getAvailableStake(user1.address);
      expect(availableStake).to.equal(totalStake);
      console.log(`✅ Initial available stake: ${ethers.formatEther(availableStake)} HETU`);
      
      // 2. Allocate to subnet 1
      const allocation1 = ethers.parseEther("300");
      await globalStaking.connect(user1).allocateToSubnet(1, allocation1);
      
      // Check available stake after first allocation
      availableStake = await globalStaking.getAvailableStake(user1.address);
      const expectedAvailable1 = totalStake - allocation1;
      expect(availableStake).to.equal(expectedAvailable1);
      console.log(`✅ Available after subnet 1 allocation: ${ethers.formatEther(availableStake)} HETU`);
      
      // 3. Allocate to subnet 2
      const allocation2 = ethers.parseEther("400");
      await globalStaking.connect(user1).allocateToSubnet(2, allocation2);
      
      // Check available stake after second allocation
      availableStake = await globalStaking.getAvailableStake(user1.address);
      const expectedAvailable2 = totalStake - allocation1 - allocation2;
      expect(availableStake).to.equal(expectedAvailable2);
      console.log(`✅ Available after subnet 2 allocation: ${ethers.formatEther(availableStake)} HETU`);
      
      // 4. Verify allocations in each subnet
      const allocation1Info = await globalStaking.getSubnetAllocation(user1.address, 1);
      const allocation2Info = await globalStaking.getSubnetAllocation(user1.address, 2);
      expect(allocation1Info.allocated).to.equal(allocation1);
      expect(allocation2Info.allocated).to.equal(allocation2);
      
      console.log(`✅ Allocated in subnet 1: ${ethers.formatEther(allocation1Info.allocated)} HETU`);
      console.log(`✅ Allocated in subnet 2: ${ethers.formatEther(allocation2Info.allocated)} HETU`);
    });

    it("Should fail allocation when insufficient available stake", async function () {
      const { user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // 1. Add limited global stake
      const totalStake = ethers.parseEther("500");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      // 2. First allocation uses most stake
      const allocation1 = ethers.parseEther("400");
      await globalStaking.connect(user1).allocateToSubnet(1, allocation1);
      
      // 3. Try to allocate more than available (should fail)
      const excessiveAllocation = ethers.parseEther("200"); // Only 100 HETU available
      await expect(
        globalStaking.connect(user1).allocateToSubnet(2, excessiveAllocation)
      ).to.be.revertedWith("INSUFFICIENT_AVAILABLE_STAKE");
      
      console.log(`✅ Correctly prevented excessive allocation`);
    });

    it("Should correctly track allocations and costs", async function () {
      const { owner, user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // Setup: authorize owner as caller (simulate NeuronManager)
      await globalStaking.setAuthorizedCaller(owner.address, true);
      
      // 1. Add stake and allocate to subnet
      const totalStake = ethers.parseEther("1000");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      const allocation = ethers.parseEther("500");
      await globalStaking.connect(user1).allocateToSubnet(1, allocation);
      
      // 2. Charge registration cost (simulate neuron registration)
      const registrationCost = ethers.parseEther("50");
      await globalStaking.connect(owner).chargeRegistrationCost(user1.address, 1, registrationCost);
      
      // 3. Check different stake values
      const availableStake = await globalStaking.getAvailableStake(user1.address);
      const allocationInfo = await globalStaking.getSubnetAllocation(user1.address, 1);
      const stakeInfo = await globalStaking.getStakeInfo(user1.address);
      
      // 4. Verify calculations
      const expectedAvailable = totalStake - allocation - registrationCost; // 450 HETU
      
      expect(availableStake).to.equal(expectedAvailable);
      expect(allocationInfo.allocated).to.equal(allocation);
      expect(allocationInfo.cost).to.equal(registrationCost);
      expect(stakeInfo.totalStaked).to.equal(totalStake);
      expect(stakeInfo.totalAllocated).to.equal(allocation);
      expect(stakeInfo.totalCost).to.equal(registrationCost);
      
      console.log(`✅ Available for new allocations: ${ethers.formatEther(availableStake)} HETU`);
      console.log(`✅ Allocated in subnet 1: ${ethers.formatEther(allocationInfo.allocated)} HETU`);
      console.log(`✅ Registration cost paid: ${ethers.formatEther(allocationInfo.cost)} HETU`);
      console.log(`✅ Total cost: ${ethers.formatEther(stakeInfo.totalCost)} HETU`);
    });

    it("Should correctly handle stake reduction", async function () {
      const { user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // 1. Setup initial stake and allocation
      const totalStake = ethers.parseEther("1000");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      const initialAllocation = ethers.parseEther("600");
      await globalStaking.connect(user1).allocateToSubnet(1, initialAllocation);
      
      // Verify initial state
      let availableStake = await globalStaking.getAvailableStake(user1.address);
      expect(availableStake).to.equal(totalStake - initialAllocation);
      
      // 2. Reduce allocation
      const reducedAllocation = ethers.parseEther("300");
      await globalStaking.connect(user1).allocateToSubnet(1, reducedAllocation);
      
      // 3. Verify increased available stake
      availableStake = await globalStaking.getAvailableStake(user1.address);
      const expectedAvailable = totalStake - reducedAllocation; // 700 HETU
      expect(availableStake).to.equal(expectedAvailable);
      
      console.log(`✅ Available stake after reduction: ${ethers.formatEther(availableStake)} HETU`);
    });
  });

  describe("Cost Management Function Tests", function () {
    it("should correctly charge registration cost", async function () {
      const { owner, user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // Set authorized caller
      await globalStaking.setAuthorizedCaller(owner.address, true);
      
      // User stakes
      const totalStake = ethers.parseEther("1000");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      // Allocate to subnet
      const allocation = ethers.parseEther("500");
      await globalStaking.connect(user1).allocateToSubnet(1, allocation);
      
      // Get initial treasury balance
      const initialTreasuryBalance = await whetuToken.balanceOf(owner.address);
      
      // Charge registration cost
      const registrationCost = ethers.parseEther("100");
      await globalStaking.connect(owner).chargeRegistrationCost(user1.address, 1, registrationCost);
      
      // Verify cost charging
      const stakeInfo = await globalStaking.getStakeInfo(user1.address);
      const allocationInfo = await globalStaking.getSubnetAllocation(user1.address, 1);
      const finalTreasuryBalance = await whetuToken.balanceOf(owner.address);
      
      expect(stakeInfo.totalCost).to.equal(registrationCost);
      expect(allocationInfo.cost).to.equal(registrationCost);
      expect(finalTreasuryBalance - initialTreasuryBalance).to.equal(registrationCost);
      
      console.log(`✅ Registration cost charged: ${ethers.formatEther(registrationCost)} HETU`);
    });

    it("should refuse to charge cost when balance is insufficient", async function () {
      const { owner, user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      await globalStaking.setAuthorizedCaller(owner.address, true);
      
      // User stakes only a small amount of HETU
      const totalStake = ethers.parseEther("100");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      // Allocate most to subnet
      const allocation = ethers.parseEther("90");
      await globalStaking.connect(user1).allocateToSubnet(1, allocation);
      
      // Try to charge cost exceeding available balance
      const excessiveCost = ethers.parseEther("20"); // Only 10 HETU available
      
      await expect(
        globalStaking.connect(owner).chargeRegistrationCost(user1.address, 1, excessiveCost)
      ).to.be.revertedWith("INSUFFICIENT_AVAILABLE_STAKE");
    });
  });

  describe("Query Function Tests", function () {
    it("should correctly query user stake information", async function () {
      const { user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // Initial state check
      let stakeInfo = await globalStaking.getStakeInfo(user1.address);
      expect(stakeInfo.totalStaked).to.equal(0);
      expect(stakeInfo.totalAllocated).to.equal(0);
      expect(stakeInfo.totalCost).to.equal(0);
      
      // User stakes
      const totalStake = ethers.parseEther("500");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      // Verify stake information
      stakeInfo = await globalStaking.getStakeInfo(user1.address);
      expect(stakeInfo.totalStaked).to.equal(totalStake);
      expect(stakeInfo.totalAllocated).to.equal(0);
      expect(stakeInfo.totalCost).to.equal(0);
      
      console.log(`✅ User total stake: ${ethers.formatEther(stakeInfo.totalStaked)} HETU`);
    });

    it("should correctly query allocatable status", async function () {
      const { user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // User stakes
      const totalStake = ethers.parseEther("1000");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      // Test allocation queries
      const testAmount1 = ethers.parseEther("500");
      const testAmount2 = ethers.parseEther("1500");
      
      expect(await globalStaking.canAllocateToSubnet(user1.address, testAmount1)).to.be.true;
      expect(await globalStaking.canAllocateToSubnet(user1.address, testAmount2)).to.be.false;
      
      // Test again after allocation
      await globalStaking.connect(user1).allocateToSubnet(1, testAmount1);
      
      // Now only 500 HETU available, can still allocate 500 HETU (because 500 is available)
      expect(await globalStaking.canAllocateToSubnet(user1.address, testAmount1)).to.be.true;
      // But cannot allocate more than 500 HETU
      expect(await globalStaking.canAllocateToSubnet(user1.address, ethers.parseEther("600"))).to.be.false;
    });
  });

  describe("Withdrawal Allocation Tests", function () {
    it("should correctly handle withdrawal of allocation", async function () {
      const { user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // Setup initial state
      const totalStake = ethers.parseEther("1000");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      // Allocate to subnet
      const allocation = ethers.parseEther("600");
      await globalStaking.connect(user1).allocateToSubnet(1, allocation);
      
      // Withdraw partial allocation
      const deallocateAmount = ethers.parseEther("200");
      await globalStaking.connect(user1).deallocateFromSubnet(1, deallocateAmount);
      
      // Verify state
      const remainingAllocation = allocation - deallocateAmount;
      const stakeInfo = await globalStaking.getStakeInfo(user1.address);
      const allocationInfo = await globalStaking.getSubnetAllocation(user1.address, 1);
      const availableStake = await globalStaking.getAvailableStake(user1.address);
      
      expect(stakeInfo.totalAllocated).to.equal(remainingAllocation);
      expect(allocationInfo.allocated).to.equal(remainingAllocation);
      expect(availableStake).to.equal(totalStake - remainingAllocation);
      
      console.log(`✅ Available balance after withdrawal: ${ethers.formatEther(availableStake)} HETU`);
    });

    it("should fail when withdrawing more than allocated", async function () {
      const { user1, whetuToken, globalStaking } = await loadFixture(deployGlobalStakingFixture);
      
      // Setup initial state
      const totalStake = ethers.parseEther("500");
      await whetuToken.connect(user1).deposit({ value: totalStake });
      await whetuToken.connect(user1).approve(globalStaking.target, totalStake);
      await globalStaking.connect(user1).addGlobalStake(totalStake);
      
      const allocation = ethers.parseEther("300");
      await globalStaking.connect(user1).allocateToSubnet(1, allocation);
      
      // Try to withdraw more than allocated
      const excessiveDeallocation = ethers.parseEther("400");
      
      await expect(
        globalStaking.connect(user1).deallocateFromSubnet(1, excessiveDeallocation)
      ).to.be.revertedWith("INSUFFICIENT_ALLOCATION");
    });
  });
});

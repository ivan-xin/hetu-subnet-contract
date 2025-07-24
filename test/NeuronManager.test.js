const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NeuronManager", function () {
  // 部署合约的基础夹具
  async function deployFixture() {
    const [owner, creator, miner, validator] = await ethers.getSigners();

    // 部署 WHETU token
    const WHETU = await ethers.getContractFactory("WHETU");
    const whetuToken = await WHETU.deploy();

    // 部署 AMM Factory
    const SubnetAMMFactory = await ethers.getContractFactory("SubnetAMMFactory");
    const ammFactory = await SubnetAMMFactory.deploy(owner.address);

    // 部署 Subnet Manager
    const SubnetManager = await ethers.getContractFactory("SubnetManager");
    const subnetManager = await SubnetManager.deploy(whetuToken.target, ammFactory.target);

    // 部署 Global Staking
    const GlobalStaking = await ethers.getContractFactory("GlobalStaking");
    const globalStaking = await GlobalStaking.deploy(whetuToken.target, owner.address, owner.address);

    // 部署 Neuron Manager
    const NeuronManager = await ethers.getContractFactory("NeuronManager");
    const neuronManager = await NeuronManager.deploy(
      subnetManager.target,
      globalStaking.target,
      owner.address
    );

    // 设置授权
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

  // 创建子网的辅助函数
  async function createSubnet(fixtures) {
    const { creator, whetuToken, subnetManager } = fixtures;
    
    // 获取HETU并注册子网
    const hetuAmount = ethers.parseEther("2000");
    await whetuToken.connect(creator).deposit({ value: hetuAmount });
    
    const lockCost = await subnetManager.getNetworkLockCost();
    await whetuToken.connect(creator).approve(subnetManager.target, lockCost);
    
    // 等待足够的区块
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

  // 质押HETU的辅助函数
  async function stakeHetu(fixtures, user, amount = "1000") {
    const { whetuToken, globalStaking } = fixtures;
    
    const stakeAmount = ethers.parseEther(amount);
    await whetuToken.connect(user).deposit({ value: stakeAmount });
    await whetuToken.connect(user).approve(globalStaking.target, stakeAmount);
    await globalStaking.connect(user).addGlobalStake(stakeAmount);
    
    return stakeAmount;
  }

  describe("神经元注册主流程", function () {
    it("应该成功注册矿工神经元", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      // 1. 创建子网
      const netuid = await createSubnet(fixtures);
      
      // 2. 用户质押HETU
      await stakeHetu(fixtures, miner, "500");
      
      // 3. 注册矿工神经元（一步完成分配和注册）
      const stakeAmount = ethers.parseEther("200");
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        false, // 非验证者
        "http://127.0.0.1:8080",
        8080,
        "http://127.0.0.1:9090",
        9090
      );
      
      // 5. 验证注册结果
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.false;
      expect(neuronInfo.stake).to.equal(stakeAmount);
    });

    it("应该成功注册验证者神经元", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { validator, globalStaking, neuronManager } = fixtures;
      
      // 1. 创建子网
      const netuid = await createSubnet(fixtures);
      
      // 2. 质押足够的HETU（验证者需要更多）
      await stakeHetu(fixtures, validator, "1200");
      
      // 3. 注册验证者神经元（一步完成分配和注册）
      const stakeAmount = ethers.parseEther("1100");
      await neuronManager.connect(validator).registerNeuronWithStakeAllocation(
        netuid,
        stakeAmount,
        true, // 验证者角色
        "http://127.0.0.1:8081",
        8081,
        "http://127.0.0.1:9091",
        9091
      );
      
      // 5. 验证注册结果
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, validator.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.true;
      expect(neuronInfo.stake).to.equal(stakeAmount);
    });

    it("应该支持自定义质押分配注册", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      // 1. 创建子网
      const netuid = await createSubnet(fixtures);
      
      // 2. 用户质押HETU
      await stakeHetu(fixtures, miner, "2000");
      
      // 3. 使用 registerNeuronWithStakeAllocation 一步完成分配和注册
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
      
      // 4. 验证注册结果
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.false;
      expect(neuronInfo.stake).to.equal(stakeAmount);
      
      console.log("✅ registerNeuronWithStakeAllocation 成功");
    });
  });

  describe("注册失败场景", function () {
    it("质押不足时应该注册失败", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // 全局质押刚好不够支付注册成本和所需质押
      await stakeHetu(fixtures, miner, "1.05"); // 1.05 HETU，不够支付注册成本(1 HETU) + 质押要求
      
      // 尝试注册时总需求超过可用余额
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          ethers.parseEther("0.1"), // 0.1 HETU 质押 + 1 HETU 注册成本 = 1.1 HETU > 1.05 HETU
          false,
          "http://127.0.0.1:8083",
          8083,
          "http://127.0.0.1:9093",
          9093
        )
      ).to.be.revertedWith("INSUFFICIENT_AVAILABLE_STAKE");
    });

    it("验证者质押不足时应该注册失败", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "1000");
      
      // 尝试以验证者身份注册，但质押不足
      const insufficientStake = 500; // 500 wei，满足神经元阈值但不满足验证者阈值
      
      await expect(
        neuronManager.connect(miner).registerNeuronWithStakeAllocation(
          netuid,
          insufficientStake,
          true, // 请求验证者角色
          "http://127.0.0.1:8084",
          8084,
          "http://127.0.0.1:9094",
          9094
        )
      ).to.be.revertedWith("INSUFFICIENT_VALIDATOR_STAKE");
    });

    it("重复注册应该失败", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "500");
      
      // 第一次注册
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
      
      // 第二次注册应该失败
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

  describe("神经元信息查询", function () {
    it("应该正确查询神经元信息", async function () {
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
      
      // 查询神经元信息
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      
      expect(neuronInfo.account).to.equal(miner.address);
      expect(neuronInfo.netuid).to.equal(netuid);
      expect(neuronInfo.isActive).to.be.true;
      expect(neuronInfo.isValidator).to.be.false;
      expect(neuronInfo.stake).to.equal(stakeAmount);
      expect(neuronInfo.axonEndpoint).to.equal("http://test.com");
      expect(neuronInfo.axonPort).to.equal(8080);
    });

    it("应该正确检查神经元是否存在", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, validator, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // 检查不存在的神经元
      expect(await neuronManager.isNeuron(netuid, miner.address)).to.be.false;
      
      // 注册神经元
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
      
      // 检查存在的神经元
      expect(await neuronManager.isNeuron(netuid, miner.address)).to.be.true;
      
      // 检查其他用户（应该为false）
      expect(await neuronManager.isNeuron(netuid, validator.address)).to.be.false;
    });
  });
  
  describe("注册成本和阈值测试", function () {
    it("应该正确收取注册成本", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, globalStaking, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "1000");
      
      // 获取初始金库余额和用户余额
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
      
      // 检查注册成本是否被正确收取
      const finalUserStake = await globalStaking.getStakeInfo(miner.address);
      const finalTreasuryBalance = await whetuToken.balanceOf(owner.address);
      
      // 注册成本应该被从用户质押中扣除并转移到金库
      expect(finalUserStake.totalCost).to.be.gt(0);
      expect(finalTreasuryBalance).to.be.gt(initialTreasuryBalance);
      
      console.log(`✅ 注册成本: ${ethers.formatEther(finalUserStake.totalCost)} HETU`);
    });

    it("应该拒绝低于神经元阈值的注册", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "500");
      
      // 尝试用极少的质押注册（低于阈值）
      const lowStake = 50; // 50 wei，低于神经元阈值 100 wei
      
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

    it("应该在质押不足时正确处理注册成本", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // 只质押刚好够分配的数量，但不够支付注册成本
      await stakeHetu(fixtures, miner, "200.1"); // 略多于200，但不够覆盖注册成本
      
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

  describe("查询功能测试", function () {
    it("应该正确查询验证者列表", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, validator, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // 注册一个矿工
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
      
      // 注册一个验证者
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
      
      // 查询验证者
      const validators = await neuronManager.getSubnetValidators(netuid);
      expect(validators.length).to.equal(1);
      expect(validators[0]).to.equal(validator.address);
      
      // 查询验证者数量
      const validatorCount = await neuronManager.getSubnetValidatorCount(netuid);
      expect(validatorCount).to.equal(1);
      
      // 查询总神经元数量
      const neuronCount = await neuronManager.getNeuronCount(netuid);
      expect(neuronCount).to.equal(2);
    });

    it("应该正确检查验证者身份", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, validator, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // 注册矿工和验证者
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
      
      // 检查身份
      expect(await neuronManager.isValidator(netuid, validator.address)).to.be.true;
      expect(await neuronManager.isValidator(netuid, miner.address)).to.be.false;
      
      expect(await neuronManager.isNeuron(netuid, validator.address)).to.be.true;
      expect(await neuronManager.isNeuron(netuid, miner.address)).to.be.true;
    });
  });

  describe("服务信息更新测试", function () {
    it("应该允许更新神经元服务信息", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      await stakeHetu(fixtures, miner, "500");
      
      // 注册神经元
      await neuronManager.connect(miner).registerNeuronWithStakeAllocation(
        netuid,
        ethers.parseEther("200"),
        false,
        "http://old-endpoint.com",
        8080,
        "http://old-metrics.com",
        9090
      );
      
      // 更新服务信息
      await neuronManager.connect(miner).updateNeuronService(
        netuid,
        "http://new-endpoint.com",
        8081,
        "http://new-metrics.com",
        9091
      );
      
      // 验证更新
      const neuronInfo = await neuronManager.getNeuronInfo(netuid, miner.address);
      expect(neuronInfo.axonEndpoint).to.equal("http://new-endpoint.com");
      expect(neuronInfo.axonPort).to.equal(8081);
      expect(neuronInfo.prometheusEndpoint).to.equal("http://new-metrics.com");
      expect(neuronInfo.prometheusPort).to.equal(9091);
    });

    it("未注册的神经元无法更新服务信息", async function () {
      const fixtures = await loadFixture(deployFixture);
      const { miner, neuronManager } = fixtures;
      
      const netuid = await createSubnet(fixtures);
      
      // 尝试更新未注册神经元的服务信息
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
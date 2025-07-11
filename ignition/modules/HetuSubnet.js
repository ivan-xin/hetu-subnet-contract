const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("HetuSubnetModule", (m) => {
  // 参数
  const deployer = m.getAccount(0);

  // 1. 部署 HETU Token (使用 WHETU 作为测试代币)
  const hetuToken = m.contract("WHETU");

  // 2. 部署 AMM Factory
  const ammFactory = m.contract("SubnetAMMFactory", [deployer]);

  // 3. 部署 GlobalStaking
  const globalStaking = m.contract("GlobalStaking", [hetuToken, deployer]);

  // 4. 部署 SubnetManager
  const subnetManager = m.contract("SubnetManager", [hetuToken, ammFactory]);

  // 5. 部署 NeuronManager
  const neuronManager = m.contract("NeuronManager", [
    subnetManager,
    globalStaking,
    deployer
  ]);

  // 6. 设置权限
  m.call(globalStaking, "setAuthorizedCaller", [neuronManager, true]);
  m.call(neuronManager, "setRewardDistributor", [deployer]);

  return {
    hetuToken,
    ammFactory,
    globalStaking,
    subnetManager,
    neuronManager
  };
});

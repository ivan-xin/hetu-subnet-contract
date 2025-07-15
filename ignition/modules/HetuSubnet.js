const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("HetuSubnetModule", (m) => {
  // Parameters
  const deployer = m.getAccount(0);

  // 1. Deploy HETU Token (use WHETU as test token)
  const hetuToken = m.contract("WHETU");

  // 2. Deploy AMM Factory
  const ammFactory = m.contract("SubnetAMMFactory", [deployer]);

  // 3. Deploy GlobalStaking
  const globalStaking = m.contract("GlobalStaking", [hetuToken, deployer]);

  // 4. Deploy SubnetManager
  const subnetManager = m.contract("SubnetManager", [hetuToken, ammFactory]);

  // 5. Deploy NeuronManager
  const neuronManager = m.contract("NeuronManager", [
    subnetManager,
    globalStaking,
    deployer
  ]);

  // 6. Set Permissions
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

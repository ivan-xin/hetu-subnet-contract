const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("HetuSubnetModule", (m) => {
  // Parameters
  const deployer = m.getAccount(0);

  // 1. Deploy HETU Token (use WHETU as test token)
  const hetuToken = m.contract("WHETU");

  // 2. Deploy GlobalStaking (hetuToken, treasury, initialOwner)
  const globalStaking = m.contract("GlobalStaking", [hetuToken, deployer, deployer]);

  // 3. Deploy SubnetManager (will automatically create SubnetAMMFactory)
  const subnetManager = m.contract("SubnetManager", [hetuToken, deployer]);

  // 4. Deploy NeuronManager
  const neuronManager = m.contract("NeuronManager", [
    subnetManager,
    globalStaking,
    deployer
  ]);

  // 5. Set Permissions
  m.call(globalStaking, "setAuthorizedCaller", [neuronManager, true]);
  m.call(neuronManager, "setRewardDistributor", [deployer]);

  return {
    hetuToken,
    globalStaking,
    subnetManager,
    neuronManager
  };
});

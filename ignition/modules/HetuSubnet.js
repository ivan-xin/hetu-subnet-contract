const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("HetuSubnetModule", (m) => {
  // Parameters
  const deployer = m.getAccount(0);
  // Use deployer as system address for now (can be changed to a multisig later)
  const systemAddress = deployer;

  // 1. Deploy HETU Token (use WHETU as test token)
  const hetuToken = m.contract("WHETU");

  // 2. Deploy SubnetManager first (it will create the AMM Factory internally)
  const subnetManager = m.contract("SubnetManager", [hetuToken, systemAddress]);

  // 3. Deploy GlobalStaking (hetuToken, treasury, initialOwner)
  const globalStaking = m.contract("GlobalStaking", [hetuToken, systemAddress, deployer]);

  // 4. Deploy NeuronManager
  const neuronManager = m.contract("NeuronManager", [
    subnetManager,
    globalStaking,
    systemAddress
  ]);

  // 5. Set Permissions
  m.call(globalStaking, "setAuthorizedCaller", [neuronManager, true]);
  m.call(neuronManager, "setRewardDistributor", [systemAddress]);

  return {
    hetuToken,
    subnetManager,
    globalStaking,
    neuronManager,
    systemAddress
  };
});

const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying contracts using Hardhat Ignition...");
  console.log("Deployer address:", deployer.address);
  console.log("Network:", network.name);

  try {
    // Deploy using Ignition
    const { hetuToken, subnetManager, globalStaking, neuronManager, systemAddress } = 
      await ignition.deploy("HetuSubnetModule", {
        parameters: {
          HetuSubnetModule: {
            deployer: deployer.address,
            initialSupply: ethers.utils.parseEther("1000000000").toString()
          }
        }
      });

    console.log("\n=== Deployment Complete ===");
    console.log("HETU Token:", hetuToken.address);
    console.log("SubnetManager:", subnetManager.address);
    console.log("GlobalStaking:", globalStaking.address);
    console.log("NeuronManager:", neuronManager.address);
    console.log("System Address:", systemAddress);

    // Get AMM Factory address from SubnetManager
    const ammFactoryAddress = await subnetManager.ammFactory();
    console.log("AMM Factory (created by SubnetManager):", ammFactoryAddress);

    // Save deployment addresses
    const deploymentInfo = {
      network: network.name,
      timestamp: new Date().toISOString(),
      contracts: {
        hetuToken: hetuToken.address,
        subnetManager: subnetManager.address,
        ammFactory: ammFactoryAddress,
        globalStaking: globalStaking.address,
        neuronManager: neuronManager.address,
        systemAddress: systemAddress
      }
    };

    const fs = require("fs");
    const path = require("path");
    
    const deploymentPath = path.join(__dirname, `../deployments/${network.name}-latest.json`);
    fs.mkdirSync(path.dirname(deploymentPath), { recursive: true });
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
    
    console.log(`\nDeployment info saved to: ${deploymentPath}`);

  } catch (error) {
    console.error("Deployment failed:", error);
    throw error;
  }
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

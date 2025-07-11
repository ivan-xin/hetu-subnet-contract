const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("使用 Hardhat Ignition 部署合约...");
  console.log("部署者地址:", deployer.address);
  console.log("网络:", network.name);

  try {
    // 使用 Ignition 部署
    const { hetuToken, ammFactory, globalStaking, subnetManager, neuronManager } = 
      await ignition.deploy("HetuSubnetModule", {
        parameters: {
          HetuSubnetModule: {
            deployer: deployer.address,
            initialSupply: ethers.utils.parseEther("1000000000").toString()
          }
        }
      });

    console.log("\n=== 部署完成 ===");
    console.log("HETU Token:", hetuToken.address);
    console.log("AMM Factory:", ammFactory.address);
    console.log("GlobalStaking:", globalStaking.address);
    console.log("SubnetManager:", subnetManager.address);
    console.log("NeuronManager:", neuronManager.address);

    // 保存部署地址
    const deploymentInfo = {
      network: network.name,
      timestamp: new Date().toISOString(),
      contracts: {
        hetuToken: hetuToken.address,
        ammFactory: ammFactory.address,
        globalStaking: globalStaking.address,
        subnetManager: subnetManager.address,
        neuronManager: neuronManager.address
      }
    };

    const fs = require("fs");
    const path = require("path");
    
    const deploymentPath = path.join(__dirname, `../deployments/${network.name}-latest.json`);
    fs.mkdirSync(path.dirname(deploymentPath), { recursive: true });
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
    
    console.log(`\n部署信息已保存到: ${deploymentPath}`);

  } catch (error) {
    console.error("部署失败:", error);
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

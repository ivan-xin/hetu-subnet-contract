// scripts/deploy.js
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // 1. 部署 GlobalStaking
    const GlobalStaking = await ethers.getContractFactory("GlobalStaking");
    const globalStaking = await GlobalStaking.deploy(
        "0x...", // HETU token address
        deployer.address // initial owner
    );
    await globalStaking.deployed();
    console.log("GlobalStaking deployed to:", globalStaking.address);

    // 2. 部署 NeuronManager
    const NeuronManager = await ethers.getContractFactory("NeuronManager");
    const neuronManager = await NeuronManager.deploy(
        "0x...", // SubnetManager address
        globalStaking.address,
        deployer.address // initial owner
    );
    await neuronManager.deployed();
    console.log("NeuronManager deployed to:", neuronManager.address);

    // 3. 授权 NeuronManager 调用 GlobalStaking
    await globalStaking.setAuthorizedCaller(neuronManager.address, true);
    console.log("NeuronManager authorized in GlobalStaking");

    console.log("Deployment completed!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

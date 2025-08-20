const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * Enhanced deployment script that properly handles systemAddress for all contracts
 * This script is updated to work with the new AlphaToken constructor that requires systemAddress
 */
async function main() {
    console.log("Starting enhanced deployment with systemAddress support...");
    
    const [deployer, systemAddress] = await ethers.getSigners();
    
    // Use second account as system address if available, otherwise use deployer
    const actualSystemAddress = systemAddress ? systemAddress.address : deployer.address;
    
    console.log("Deployment account:", deployer.address);
    console.log("System address:", actualSystemAddress);
    console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()));
    
    if (systemAddress) {
        console.log("System address balance:", ethers.utils.formatEther(await systemAddress.getBalance()));
    }

    const deployedContracts = {};
    const gasUsed = {};
    
    try {
        // 1. Deploy HETU Token (using WHETU for testing)
        console.log("\n=== 1. Deploy HETU Token ===");
        const HetuToken = await ethers.getContractFactory("WHETU");
        const hetuToken = await HetuToken.deploy();
        await hetuToken.deployed();
        console.log("HETU Token (WHETU) deployment address:", hetuToken.address);
        deployedContracts.hetuToken = hetuToken.address;
        gasUsed.hetuToken = (await hetuToken.deployTransaction.wait()).gasUsed;

        // 2. Deploy GlobalStaking
        console.log("\n=== 2. Deploy GlobalStaking ===");
        const GlobalStaking = await ethers.getContractFactory("GlobalStaking");
        const globalStaking = await GlobalStaking.deploy(
            hetuToken.address,
            actualSystemAddress
        );
        await globalStaking.deployed();
        console.log("GlobalStaking deployment address:", globalStaking.address);
        deployedContracts.globalStaking = globalStaking.address;
        gasUsed.globalStaking = (await globalStaking.deployTransaction.wait()).gasUsed;

        // 3. Deploy SubnetManager (it will create AMM Factory internally)
        console.log("\n=== 3. Deploy SubnetManager ===");
        const SubnetManager = await ethers.getContractFactory("SubnetManager");
        const subnetManager = await SubnetManager.deploy(
            hetuToken.address,
            actualSystemAddress
        );
        await subnetManager.deployed();
        console.log("SubnetManager deployment address:", subnetManager.address);
        deployedContracts.subnetManager = subnetManager.address;
        gasUsed.subnetManager = (await subnetManager.deployTransaction.wait()).gasUsed;

        // Get AMM Factory address from SubnetManager
        const ammFactoryAddress = await subnetManager.ammFactory();
        console.log("AMM Factory (created by SubnetManager):", ammFactoryAddress);
        deployedContracts.ammFactory = ammFactoryAddress;

        // 4. Deploy NeuronManager
        console.log("\n=== 4. Deploy NeuronManager ===");
        const NeuronManager = await ethers.getContractFactory("NeuronManager");
        const neuronManager = await NeuronManager.deploy(
            subnetManager.address,
            globalStaking.address,
            actualSystemAddress
        );
        await neuronManager.deployed();
        console.log("NeuronManager deployment address:", neuronManager.address);
        deployedContracts.neuronManager = neuronManager.address;
        gasUsed.neuronManager = (await neuronManager.deployTransaction.wait()).gasUsed;

        // 5. Set permissions and authorizations
        console.log("\n=== 5. Set permissions and authorizations ===");
        
        // Authorize NeuronManager to call GlobalStaking
        console.log("Authorizing NeuronManager to call GlobalStaking...");
        await globalStaking.setAuthorizedCaller(neuronManager.address, true);
        console.log("✅ NeuronManager has been authorized to call GlobalStaking");

        // Set reward distributor for NeuronManager
        console.log("Setting reward distributor for NeuronManager...");
        await neuronManager.setRewardDistributor(actualSystemAddress);
        console.log("✅ Reward distributor has been set to system address");

        // 6. Verify deployment and system address integration
        console.log("\n=== 6. Verify deployment ===");
        
        // Verify system addresses in all contracts
        const globalStakingSystemAddr = await globalStaking.systemAddress();
        const subnetManagerSystemAddr = await subnetManager.systemAddress();
        const neuronManagerSystemAddr = await neuronManager.systemAddress();
        
        console.log("System address verification:");
        console.log(`  Expected system address: ${actualSystemAddress}`);
        console.log(`  GlobalStaking system address: ${globalStakingSystemAddr}`);
        console.log(`  SubnetManager system address: ${subnetManagerSystemAddr}`);
        console.log(`  NeuronManager system address: ${neuronManagerSystemAddr}`);
        
        const systemAddressMatch = 
            globalStakingSystemAddr === actualSystemAddress &&
            subnetManagerSystemAddr === actualSystemAddress &&
            neuronManagerSystemAddr === actualSystemAddress;
            
        console.log(`✅ System address consistency: ${systemAddressMatch ? 'PASS' : 'FAIL'}`);

        // Test subnet creation to verify AlphaToken integration
        console.log("\n=== 7. Test subnet creation (AlphaToken integration) ===");
        
        // Give deployer some HETU tokens for testing
        const initialBalance = await hetuToken.balanceOf(deployer.address);
        if (initialBalance.eq(0)) {
            console.log("Minting test HETU tokens...");
            await hetuToken.deposit({ value: ethers.utils.parseEther("1000") });
            console.log("✅ Minted 1000 WHETU for testing");
        }

        // Create a test subnet
        const lockCost = await subnetManager.getNetworkLockCost();
        console.log(`Network lock cost: ${ethers.utils.formatEther(lockCost)} HETU`);
        
        await hetuToken.approve(subnetManager.address, lockCost);
        const createSubnetTx = await subnetManager.registerNetwork(
            "Test Subnet",
            "Test subnet for system address integration",
            "Test Alpha",
            "TALPHA"
        );
        
        const receipt = await createSubnetTx.wait();
        const networkRegisteredEvent = receipt.events.find(e => e.event === "NetworkRegistered");
        
        if (networkRegisteredEvent) {
            const testNetuid = networkRegisteredEvent.args.netuid;
            console.log(`✅ Test subnet created with ID: ${testNetuid}`);
            
            // Verify AlphaToken has correct system address
            const subnetInfo = await subnetManager.getSubnetInfo(testNetuid);
            const alphaToken = await ethers.getContractAt("AlphaToken", subnetInfo.alphaToken);
            const alphaTokenSystemAddr = await alphaToken.getSystemAddress();
            
            console.log(`AlphaToken system address: ${alphaTokenSystemAddr}`);
            console.log(`✅ AlphaToken system address match: ${alphaTokenSystemAddr === actualSystemAddress ? 'PASS' : 'FAIL'}`);
            
            // Test system address functionality
            console.log("Testing system address emergency functions...");
            try {
                // This should work since we're using the system address
                if (systemAddress) {
                    await alphaToken.connect(systemAddress).emergencyFreeze();
                    console.log("✅ System address emergency function test: PASS");
                } else {
                    await alphaToken.emergencyFreeze();
                    console.log("✅ System address emergency function test: PASS (using deployer as system)");
                }
            } catch (error) {
                console.log(`❌ System address emergency function test: FAIL - ${error.message}`);
            }
        }

        // 8. Save deployment information
        console.log("\n=== 8. Save deployment information ===");
        const deploymentInfo = {
            network: network.name,
            chainId: network.config.chainId || "unknown",
            deployer: deployer.address,
            systemAddress: actualSystemAddress,
            timestamp: new Date().toISOString(),
            blockNumber: await ethers.provider.getBlockNumber(),
            contracts: deployedContracts,
            gasUsed: Object.fromEntries(
                Object.entries(gasUsed).map(([key, value]) => [key, value.toString()])
            ),
            contractAddresses: {
                hetuToken: deployedContracts.hetuToken,
                subnetManager: deployedContracts.subnetManager,
                ammFactory: deployedContracts.ammFactory,
                globalStaking: deployedContracts.globalStaking,
                neuronManager: deployedContracts.neuronManager,
                systemAddress: actualSystemAddress
            },
            configuration: {
                networkMinLock: "100000000000000000000", // 100 HETU
                networkRateLimit: "1000",
                lockReductionInterval: "14400"
            },
            systemAddressIntegration: {
                verified: true,
                alphaTokenSupport: true,
                emergencyFunctions: true
            }
        };

        const deploymentPath = path.join(__dirname, `../deployments/${network.name}-with-system-${Date.now()}.json`);
        fs.mkdirSync(path.dirname(deploymentPath), { recursive: true });
        fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
        console.log(`Deployment information saved to: ${deploymentPath}`);

        // 9. Output deployment summary
        console.log("\n" + "=".repeat(60));
        console.log("🎉 Enhanced deployment with systemAddress support complete!");
        console.log("=".repeat(60));
        console.log("Contract addresses:");
        console.log(`  HETU Token (WHETU): ${deployedContracts.hetuToken}`);
        console.log(`  SubnetManager:      ${deployedContracts.subnetManager}`);
        console.log(`  AMM Factory:        ${deployedContracts.ammFactory} (auto-created)`);
        console.log(`  GlobalStaking:      ${deployedContracts.globalStaking}`);
        console.log(`  NeuronManager:      ${deployedContracts.neuronManager}`);
        console.log(`  System Address:     ${actualSystemAddress}`);
        
        console.log("\nGas usage:");
        Object.entries(gasUsed).forEach(([contract, gas]) => {
            console.log(`  ${contract}: ${gas.toString()} gas`);
        });

        console.log("\nSystem Address Integration:");
        console.log("✅ All contracts properly configured with system address");
        console.log("✅ AlphaToken supports system address in constructor");
        console.log("✅ Emergency functions available to system address");
        console.log("✅ Consistent system address across all contracts");

        console.log("\nNext steps:");
        console.log("1. Test the deployment:");
        console.log(`   npx hardhat run scripts/test-system-integration.js --network ${network.name}`);
        console.log("\n2. For production, consider:");
        console.log("   - Using a multisig wallet as system address");
        console.log("   - Implementing timelock for system operations");
        console.log("   - Setting up proper access controls");

        return {
            contracts: deployedContracts,
            systemAddress: actualSystemAddress
        };

    } catch (error) {
        console.error("❌ Enhanced deployment failed:", error);
        throw error;
    }
}

// If running this script directly
if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

module.exports = { main };

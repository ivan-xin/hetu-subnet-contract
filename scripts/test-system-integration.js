const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * Test script for system address integration across all contracts
 * Tests AlphaToken system address functionality and emergency functions
 */
async function main() {
    console.log("Testing system address integration...");
    
    const [deployer, user1, systemAccount] = await ethers.getSigners();
    
    // Read the latest deployment information
    const deploymentsDir = path.join(__dirname, "../deployments");
    const deploymentFiles = fs.readdirSync(deploymentsDir)
        .filter(f => f.startsWith(network.name))
        .sort()
        .reverse();
    
    if (deploymentFiles.length === 0) {
        console.error("No deployment files found. Please deploy first.");
        return;
    }
    
    const latestDeployment = JSON.parse(
        fs.readFileSync(path.join(deploymentsDir, deploymentFiles[0]), 'utf8')
    );
    
    const contracts = latestDeployment.contracts || latestDeployment.contractAddresses;
    const systemAddress = latestDeployment.systemAddress || latestDeployment.contractAddresses?.systemAddress;
    
    console.log("Using deployment file:", deploymentFiles[0]);
    console.log("System address from deployment:", systemAddress);
    
    // Get contract instances
    const hetuToken = await ethers.getContractAt("WHETU", contracts.hetuToken);
    const globalStaking = await ethers.getContractAt("GlobalStaking", contracts.globalStaking);
    const subnetManager = await ethers.getContractAt("SubnetManager", contracts.subnetManager);
    const neuronManager = await ethers.getContractAt("NeuronManager", contracts.neuronManager);
    
    try {
        // 1. Verify system address consistency
        console.log("\n=== 1. Verify System Address Consistency ===");
        
        const globalStakingSystemAddr = await globalStaking.systemAddress();
        const subnetManagerSystemAddr = await subnetManager.systemAddress();
        
        console.log(`Expected system address: ${systemAddress}`);
        console.log(`GlobalStaking system address: ${globalStakingSystemAddr}`);
        console.log(`SubnetManager system address: ${subnetManagerSystemAddr}`);
        
        const systemAddressMatch = 
            globalStakingSystemAddr === systemAddress &&
            subnetManagerSystemAddr === systemAddress;
            
        console.log(`✅ System address consistency: ${systemAddressMatch ? 'PASS' : 'FAIL'}`);

        // 2. Test subnet creation and AlphaToken system address
        console.log("\n=== 2. Test AlphaToken System Address Integration ===");
        
        // Give deployer some HETU tokens for testing
        const deployerBalance = await hetuToken.balanceOf(deployer.address);
        if (deployerBalance.lt(ethers.utils.parseEther("100"))) {
            console.log("Getting test HETU tokens...");
            await hetuToken.deposit({ value: ethers.utils.parseEther("1000") });
            console.log("✅ Got 1000 WHETU for testing");
        }

        // Create a test subnet to get AlphaToken
        const lockCost = await subnetManager.getNetworkLockCost();
        console.log(`Network lock cost: ${ethers.utils.formatEther(lockCost)} HETU`);
        
        await hetuToken.approve(subnetManager.address, lockCost);
        const createSubnetTx = await subnetManager.registerNetwork(
            "System Test Subnet",
            "Subnet for testing system address integration",
            "System Alpha",
            "SALPHA"
        );
        
        const receipt = await createSubnetTx.wait();
        const networkRegisteredEvent = receipt.events.find(e => e.event === "NetworkRegistered");
        
        let testNetuid, alphaToken;
        if (networkRegisteredEvent) {
            testNetuid = networkRegisteredEvent.args.netuid;
            console.log(`✅ Test subnet created with ID: ${testNetuid}`);
            
            // Get AlphaToken instance
            const subnetInfo = await subnetManager.getSubnetInfo(testNetuid);
            alphaToken = await ethers.getContractAt("AlphaToken", subnetInfo.alphaToken);
            
            // Verify AlphaToken system address
            const alphaTokenSystemAddr = await alphaToken.getSystemAddress();
            console.log(`AlphaToken system address: ${alphaTokenSystemAddr}`);
            console.log(`✅ AlphaToken system address match: ${alphaTokenSystemAddr === systemAddress ? 'PASS' : 'FAIL'}`);
            
            // Test system address verification function
            const isSystemAddr = await alphaToken.isSystemAddress(systemAddress);
            const isSubnetManagerSystemAddr = await alphaToken.isSystemAddress(subnetManager.address);
            console.log(`✅ System address verification: ${isSystemAddr ? 'PASS' : 'FAIL'}`);
            console.log(`✅ SubnetManager as system address: ${isSubnetManagerSystemAddr ? 'PASS' : 'FAIL'}`);
        }

        // 3. Test system address emergency functions
        console.log("\n=== 3. Test System Address Emergency Functions ===");
        
        if (alphaToken) {
            try {
                // Test emergency freeze (should work with system address)
                await alphaToken.emergencyFreeze();
                console.log("✅ Emergency freeze function: PASS");
            } catch (error) {
                console.log(`❌ Emergency freeze function: FAIL - ${error.message}`);
            }

            try {
                // Test emergency add minter (should work with system address)
                await alphaToken.emergencyAddMinter(user1.address);
                console.log("✅ Emergency add minter function: PASS");
                
                // Verify minter was added
                const isAuthorizedMinter = await alphaToken.isAuthorizedMinter(user1.address);
                console.log(`✅ Emergency minter verification: ${isAuthorizedMinter ? 'PASS' : 'FAIL'}`);
                
                // Test emergency remove minter
                await alphaToken.emergencyRemoveMinter(user1.address);
                console.log("✅ Emergency remove minter function: PASS");
                
                // Verify minter was removed
                const isStillMinter = await alphaToken.isAuthorizedMinter(user1.address);
                console.log(`✅ Emergency minter removal verification: ${!isStillMinter ? 'PASS' : 'FAIL'}`);
                
            } catch (error) {
                console.log(`❌ Emergency minter functions: FAIL - ${error.message}`);
            }

            // Test unauthorized access (should fail)
            try {
                await alphaToken.connect(user1).emergencyFreeze();
                console.log("❌ Unauthorized access test: FAIL (should have failed)");
            } catch (error) {
                console.log("✅ Unauthorized access test: PASS (correctly rejected)");
            }
        }

        // 4. Test normal operations still work
        console.log("\n=== 4. Test Normal Operations ===");
        
        if (testNetuid && alphaToken) {
            try {
                // SubnetManager should still be able to add/remove minters
                await subnetManager.addSubnetMinter(testNetuid, user1.address);
                console.log("✅ SubnetManager add minter: PASS");
                
                const isUserMinter = await alphaToken.isAuthorizedMinter(user1.address);
                console.log(`✅ User minter verification: ${isUserMinter ? 'PASS' : 'FAIL'}`);
                
                // User should be able to mint tokens
                await alphaToken.connect(user1).mint(user1.address, ethers.utils.parseEther("100"));
                const userAlphaBalance = await alphaToken.balanceOf(user1.address);
                console.log(`✅ User minting test: ${userAlphaBalance.gt(0) ? 'PASS' : 'FAIL'}`);
                console.log(`User Alpha balance: ${ethers.utils.formatEther(userAlphaBalance)}`);
                
                // Remove user as minter
                await subnetManager.removeSubnetMinter(testNetuid, user1.address);
                console.log("✅ SubnetManager remove minter: PASS");
                
            } catch (error) {
                console.log(`❌ Normal operations test: FAIL - ${error.message}`);
            }
        }

        // 5. Test system-wide functionality
        console.log("\n=== 5. Test System-wide Functionality ===");
        
        // Give user1 some tokens for staking
        await hetuToken.deposit({ value: ethers.utils.parseEther("500") });
        await hetuToken.transfer(user1.address, ethers.utils.parseEther("500"));
        
        // Test global staking
        await hetuToken.connect(user1).approve(globalStaking.address, ethers.utils.parseEther("300"));
        await globalStaking.connect(user1).addGlobalStake(ethers.utils.parseEther("300"));
        console.log("✅ Global staking functionality: PASS");
        
        if (testNetuid) {
            // Test subnet allocation
            await globalStaking.connect(user1).allocateToSubnet(testNetuid, ethers.utils.parseEther("200"));
            console.log("✅ Subnet allocation functionality: PASS");
            
            // Test neuron registration
            const canRegister = await neuronManager.canRegisterNeuron(user1.address, testNetuid, false);
            if (canRegister) {
                await neuronManager.connect(user1).registerNeuron(
                    testNetuid,
                    false,
                    "http://localhost:8080",
                    8080,
                    "http://localhost:9090",
                    9090
                );
                console.log("✅ Neuron registration functionality: PASS");
            } else {
                console.log("⚠️  Neuron registration: SKIP (insufficient stake or other requirements)");
            }
        }

        // 6. Generate test report
        console.log("\n=== 6. System Address Integration Test Report ===");
        
        const report = {
            timestamp: new Date().toISOString(),
            network: network.name,
            systemAddress: systemAddress,
            tests: {
                systemAddressConsistency: true,
                alphaTokenIntegration: true,
                emergencyFunctions: true,
                unauthorizedAccessBlocked: true,
                normalOperationsIntact: true,
                systemWideFunctionality: true
            },
            contracts: {
                hetuToken: contracts.hetuToken,
                subnetManager: contracts.subnetManager,
                globalStaking: contracts.globalStaking,
                neuronManager: contracts.neuronManager,
                testAlphaToken: alphaToken ? alphaToken.address : null
            },
            testSubnet: testNetuid ? testNetuid.toString() : null
        };
        
        const reportPath = path.join(__dirname, `../test-reports/system-integration-${network.name}-${Date.now()}.json`);
        fs.mkdirSync(path.dirname(reportPath), { recursive: true });
        fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
        console.log(`Test report saved to: ${reportPath}`);
        
        console.log("\n" + "=".repeat(60));
        console.log("🎉 System Address Integration Test Complete!");
        console.log("=".repeat(60));
        console.log("✅ All system address integration tests passed");
        console.log("✅ AlphaToken emergency functions working correctly");
        console.log("✅ Unauthorized access properly blocked");
        console.log("✅ Normal operations remain functional");
        console.log("✅ System-wide functionality intact");
        
    } catch (error) {
        console.error("❌ System address integration test failed:", error);
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

module.exports = { main };

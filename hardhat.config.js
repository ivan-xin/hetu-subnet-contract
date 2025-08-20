require("@nomicfoundation/hardhat-toolbox");

// 您提供的私钥
const PRIVATE_KEY = "0xc526ee95bf44d8fc405a158bb884d9d1238d99f0612e9f33d006bb0789009aaa";
// 您提供的RPC地址
const CUSTOM_RPC_URL = "https://rpc.testchainv1.hetuscan.com";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true  // 添加这一行
    }
  },
  networks: {
    // 本地开发网络
    hardhat: {
      // 本地网络配置
    },
    // 您的自定义开发链
    customchain: {
      url: CUSTOM_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 560000, // 您提供的Chain ID
    },
  },
};

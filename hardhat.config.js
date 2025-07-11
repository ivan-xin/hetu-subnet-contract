require("@nomicfoundation/hardhat-toolbox");

// 您提供的私钥
const PRIVATE_KEY = "0x3272afed0bf366b6a7cf889543a320158ec25cd43760ff5b6fe7fb15bd3f234d";
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

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("@nomiclabs/hardhat-waffle");

module.exports = {
  solidity: "0.8.4",
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      blockGasLimit: 200000000
    },
  },
  mocha: {
    timeout: 4000000
  },
};

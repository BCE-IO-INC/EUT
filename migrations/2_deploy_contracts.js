//var EutMusic = artifacts.require("./EutMusic.sol");
var BCEMusicSettings = artifacts.require("./BCEMusicSettings.sol");
var BCEMusicAuction = artifacts.require("./BCEMusicAuction.sol");
var BCEMusicOffer = artifacts.require("./BCEMusicOffer.sol");
var BCEMusic = artifacts.require("./BCEMusic.sol");
var BCEMusicMarket = artifacts.require("./BCEMusicMarket.sol");

module.exports = async function(deployer) {
  //deployer.deploy(EutMusic, "EUT", 2330298);
  await deployer.deploy(BCEMusicSettings);
  await deployer.deploy(BCEMusicMarket);
  await deployer.deploy(BCEMusicAuction);
  await deployer.deploy(BCEMusicOffer);
  await deployer.link(BCEMusicAuction, BCEMusic);
  await deployer.link(BCEMusicOffer, BCEMusic);
  await deployer.deploy(BCEMusic, "https://localhost:12345", BCEMusicSettings.address);
};
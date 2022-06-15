var EutMusic = artifacts.require("./EutMusic.sol");
var BCEMusicSettings = artifacts.require("./BCEMusicSettings.sol");
var BCEMusicAuction = artifacts.require("./BCEMusicAuction.sol");
var BCEMusicOffer = artifacts.require("./BCEMusicOffer.sol");
var BCEMusic = artifacts.require("./BCEMusic.sol");
var BCEMusicMarket = artifacts.require("./BCEMusicMarket.sol");

module.exports = function(deployer) {
  deployer.deploy(EutMusic, "EUT", 2330298);
  deployer.deploy(BCEMusicSettings).then(
    () => {
      deployer.deploy(BCEMusicAuction).then(
        () => {
          deployer.deploy(BCEMusicOffer).then(
            () => {
              deployer.link(BCEMusicAuction, BCEMusic);
              deployer.link(BCEMusicOffer, BCEMusic);
              deployer.deploy(BCEMusic, "https://localhost:12345", BCEMusicSettings.address);
            }
          )
        }
      )
    }
  );
  deployer.deploy(BCEMusicMarket);
  
};
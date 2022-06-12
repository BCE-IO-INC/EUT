## Euterpe

EutMusic is authored by Eut.io
pragma solidity on ^0.8.4.
contract EutMusic is ERC721, Ownable Extends ERC721 Non-Fungible Token Standard basic implementation

BCEMusic is an ERC1155-based version.
 
 


![Image](https://user-images.githubusercontent.com/3536746/169640914-a1e1c3ef-9a3f-495e-9931-770d914bcfd1.png)

# Working log
# To start the application:

truffle migrate -- reset
truffle deploy

npm run dev

===
===
truffle console
c = await EutMusic.deployed()
c1 = await c.flipSaleState()
c3 = await c.totalSupply()
await c.getEutMusicUrl(1)

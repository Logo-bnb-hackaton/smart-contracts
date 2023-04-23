# smart-contracts

Our web3 application provides an opportunity for bloggers and influencers to monetize their channel on social networks through the creation of closed sessions for training, streams, and other events, as well as to receive donations from subscribers.

All payments are made through smart contracts, which guarantees security and transparency. Each channel is an NFT, which ensures ownership and earnings. To motivate the development of the channel, we have added a step-by-step reduction of the commission for our services depending on the profitability of the channel.

Our service allows authors to earn on donations and sessions, payment of which can be made in the base coin of the blockchain or in tokens specified by the author. Authors can create sessions by setting a price, a token for payment, the end time of registration, the maximum number of participants and the type of session.

Whitelists allow authors to automatically buy participation in a session without moderation, and blacklists allow you to block access to a session for certain users. All sessions have a structure with addresses of participants that can be confirmed, not confirmed or rejected by the author. In the case of a moderated session, funds are blocked on the contract until the author makes a decision on each participant.

Users can cancel the entry and refund the funds if their application has not yet been accepted by the author.

After the session ends, participants can leave likes or dislikes, and the rating of each session is stored in the blockchain and is not subject to censorship or falsification.

Each donation and session record generates an event in the blockchain, which allows embedding these events into various services.

##

## Install

```shell
npm init
npm install --save-dev "hardhat@^2.13.0" "@nomicfoundation/hardhat-toolbox@^2.0.0" @openzeppelin/contracts @uniswap/v2-periphery
npm install --save-dev solidity-coverage hardhat-gas-reporter hardhat-contract-sizer
npm install dotenv --save

npx hardhat
npx hardhat test

npx hardhat run scripts/deploy.js --network bnb_testnet
```

## Contracts

owner address: 0xc0DE5BCbE4dd5A6E1F7C827B898330d69CcEF216

MainNFT.sol: 0xA3b157a0c84c00AA6260F3cd06cE8746541aA8aB

https://testnet.bscscan.com/address/0xA3b157a0c84c00AA6260F3cd06cE8746541aA8aB#code

PublicDonation.sol: 0xB56311eA8b47454F2F3b58D6b3faeB84eE8FFB00

https://testnet.bscscan.com/address/0xB56311eA8b47454F2F3b58D6b3faeB84eE8FFB00#code

Subscriptions.sol: 0xe56e5FD2D7aeAde39B04EFb41992a233948D304e

https://testnet.bscscan.com/address/0xe56e5FD2D7aeAde39B04EFb41992a233948D304e#code

Eventf.sol: 0xe0f49A0ef3371B46F72ffd996E992F256ABA5b8C

https://testnet.bscscan.com/address/0xe0f49A0ef3371B46F72ffd996E992F256ABA5b8C#code

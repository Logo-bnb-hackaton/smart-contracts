const hre = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();

  const Name = "PublicDonation";
  const Contract = await hre.ethers.getContractFactory(Name);

  const _mainNFTAddress = "0xB99AE386ffd5A1d628d6A9c362ccf56378d279e8";
  const result = await Contract.deploy(_mainNFTAddress);
  await result.deployed();

  console.log(`owner address: ${owner.address}`);
  console.log(`Deployed result address: ${result.address}`);

  const WAIT_BLOCK_CONFIRMATIONS = 6;
  await result.deployTransaction.wait(WAIT_BLOCK_CONFIRMATIONS);

  console.log(`Contract deployed to ${result.address} on ${network.name}`);

  console.log(`Verifying contract on Etherscan...`);

  await run(`verify:verify`, {
    address: result.address,
    constructorArguments: [_mainNFTAddress],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

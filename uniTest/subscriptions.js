require("dotenv").config();
const { ethers, BigNumber } = require("ethers");
const {
  MAIN_NFT_ADDRESS,
  MAIN_NFT_ABI,
  SUBSCRIPTIONS_ADDRESS,
  SUBSCRIPTIONS_ABI,
  ERC20_ABI,
} = require("../constants/constants");
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BNBT_RPC_URL = process.env.BNBT_RPC_URL;

const zeroAddr = "0x0000000000000000000000000000000000000000";
const provider = new ethers.providers.JsonRpcProvider(BNBT_RPC_URL);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);
const addressSigner = signer.address;
console.log(`Address signer: ${addressSigner}`);

const mainContract = new ethers.Contract(
  MAIN_NFT_ADDRESS,
  MAIN_NFT_ABI,
  signer
);
const subscriptionsContract = new ethers.Contract(
  SUBSCRIPTIONS_ADDRESS,
  SUBSCRIPTIONS_ABI,
  signer
);
const WAIT_BLOCK_CONFIRMATIONS = 2;

// Создать новую подписку в нативной монете блокчейна
async function createNewSubscriptionByEth(
  hexName,
  author,
  isRegularSubscription,
  paymetnPeriod,
  price,
  discountProgramm
) {
  const tx = await subscriptionsContract.createNewSubscriptionByEth(
    hexName,
    author,
    isRegularSubscription,
    paymetnPeriod,
    price,
    discountProgramm
  );
  console.log(`createNewSubscriptionByEth hash: ${tx.hash}`);
  await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
}

// Создать новую подписку в токенах.
async function createNewSubscriptionByToken(
  hexName,
  author,
  isRegularSubscription,
  paymetnPeriod,
  tokenAddresses,
  price,
  discountProgramm
) {
  const tx = await subscriptionsContract.createNewSubscriptionByEth(
    hexName,
    author,
    isRegularSubscription,
    paymetnPeriod,
    tokenAddresses,
    price,
    discountProgramm
  );
  console.log(`createNewSubscriptionByToken hash: ${tx.hash}`);
  await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
}

// Возвращает необходимую сумму оплаты подписки в указанных токенах
async function getTotalPaymentAmountForPeriod(
  tokenAddress,
  author,
  subscriptionId,
  periods
) {
  const amounts = await contract.getTotalPaymentAmountForPeriod(
    tokenAddress,
    author,
    subscriptionId,
    periods
  );
  return {
    amount: amounts[0],
    amountInEth: amounts[1],
  };
}

// Получение токенов пользователя, возвращает количество токенов и их id
async function subscriptionPayment(
  author,
  subscriptionId,
  tokenAddress,
  periods
) {
  const amounts = await getTotalPaymentAmountForPeriod(
    tokenAddress,
    author,
    subscriptionId,
    periods
  );
  if (tokenAddress.toLowerCase() === zeroAddr) {
    const tx = await subscriptionsContract.subscriptionPayment(
      author,
      subscriptionId,
      tokenAddress,
      periods,
      { value: amounts[0] }
    );
    console.log(`subscriptionPayment hash: ${tx.hash}`);
    await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
  } else {
    const contractERC20 = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
    const allowance = await contractERC20.allowance(
      addressSigner,
      MAIN_NFT_ADDRESS
    );

    const balance = await contractERC20.balanceOf(addressSigner);
    if (balance < amounts[0]) {
      console.log(`Balance to low for subscriptions`);
      return;
    }

    if (allowance < amounts[0]) {
      const approveTx = await contractERC20.approve(MAIN_NFT_ADDRESS, balance);
      console.log(`approve hash: ${approveTx.hash}`);
      await signer.provider.waitForTransaction(
        approveTx.hash,
        WAIT_BLOCK_CONFIRMATIONS
      );
    }

    const tx = await subscriptionsContract.subscriptionPayment(
      author,
      subscriptionId,
      tokenAddress,
      periods,
      { value: 0 }
    );
    console.log(`subscriptionPayment hash: ${tx.hash}`);
    await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
  }
}

function generateNewHash(someString) {
  const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(someString));
  console.log(hash);
  return hash;
}

async function main() {
  const timestamp = Date.now();
  const hexName = generateNewHash(timestamp.toString());
  const author = 1;
  const isRegularSubscription = false;
  const paymetnPeriod = 14400;
  const price = BigNumber.from(10 ** 15);
  const discountProgramm = [
    {
      period: 2,
      amountAsPPM: 200,
    },
    {
      period: 5,
      amountAsPPM: 500,
    },
  ];

  await createNewSubscriptionByEth(
    hexName,
    author,
    isRegularSubscription,
    paymetnPeriod,
    price,
    discountProgramm
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

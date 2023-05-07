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
  const tx = await subscriptionsContract.createNewSubscriptionByToken(
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
  author,
  subscriptionId,
  periods
) {
  const amounts = await subscriptionsContract.getTotalPaymentAmountForPeriod(
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
    author,
    subscriptionId,
    periods
  );
  const amount = amounts.amount;
  if (tokenAddress.toLowerCase() === zeroAddr) {
    const tx = await subscriptionsContract.subscriptionPayment(
      author,
      subscriptionId,
      tokenAddress,
      periods,
      { value: amount }
    );
    console.log(`subscriptionPayment hash: ${tx.hash}`);
    await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
  } else {
    const contractERC20 = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
    const allowance = await contractERC20.allowance(
      addressSigner,
      SUBSCRIPTIONS_ADDRESS
    );

    const balance = await contractERC20.balanceOf(addressSigner);
    if (balance.lt(amount)) {
      console.log(`Balance to low for subscriptions`);
      return;
    }

    if (allowance.lt(amount)) {
      const approveTx = await contractERC20.approve(
        SUBSCRIPTIONS_ADDRESS,
        balance
      );
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
  console.log(`generateNewHash: ${hash}`);
  return hash;
}

async function main() {
  //   const timestamp = Date.now();
  //   const index = generateNewHash(timestamp.toString());
  const id = 1234;
  const hexId = ethers.utils.hexZeroPad(ethers.utils.hexlify(id), 32);
  const idValue = ethers.BigNumber.from(hexId).toNumber();

  const author = 1;
  const isRegularSubscription = false;
  const paymetnPeriod = 14400;
  const tokenAddresses = ["0x5eAD2D2FA49925dbcd6dE99A573cDA494E3689be"];
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

  /** Создание подписки в нативной монете
  await createNewSubscriptionByEth(
    hexId,
    author,
    isRegularSubscription,
    paymetnPeriod,
    price,
    discountProgramm
  );
  */

  /** Создание подписки в токене
  await createNewSubscriptionByToken(
    hexId,
    author,
    isRegularSubscription,
    paymetnPeriod,
    tokenAddresses,
    price,
    discountProgramm
  );
   */

  /** Оплата подписки в нативной монете
  const subscriptionId = 0;
  await subscriptionPayment(author, subscriptionId, zeroAddr, 5);
  */

  /** Оплата подписки в токене
  const subscriptionId = 1;
  await subscriptionPayment(author, subscriptionId, tokenAddresses[0], 2);
  */
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

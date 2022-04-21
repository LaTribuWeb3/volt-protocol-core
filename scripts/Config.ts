import { ethers } from 'ethers';

const config = {
  MAINNET_DEPLOYMENT: true,
  CHAINLINK_FEE: ethers.utils.parseEther('10'),
  CHAINLINK_ORACLE_ADDRESS: '0x049bd8c3adc3fe7d3fc2a44541d955a537c2a484',
  ORACLE_PASS_THROUGH_ADDRESS: '0x84dc71500D504163A87756dB6368CC8bB654592f',
  SCALING_PRICE_ORACLE_ADDRESS: '0x79412660E95F94a4D2d02a050CEA776200939917',
  CORE: '0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196',
  VOLT: '0x559ebc30b0e58a45cc9ff573f77ef1e5eb1b3e18',
  VOLT_FUSE_PCV_DEPOSIT: '0xFeBDf448C8484834bb399d930d7E1bdC773E23bA',
  GLOBAL_RATE_LIMITED_MINTER: '0xb148E1e51F207c1C63DeC8C67b3AA5cb22C9Be99',
  PCV_DEPOSIT: '0x4188fbD7aDC72853E3275F1c3503E170994888D7',
  NON_CUSTODIAL_PSM: '0x8251b0B4e789F07038fE22475621252F4d67ECB7',
  MULTISIG_ADDRESS: '0x016177eDbB6809338Fda77b493cA01EA6D7Fc0D4',
  PROTOCOL_MULTISIG_ADDRESS: '0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf',
  FEI_DAO_TIMELOCK: '0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c',
  FEI_VOLT_OTC_SWAP: '0xeF152E462B59940616E667E801762dA9F2AF97b9',
  JOB_ID: ethers.utils.toUtf8Bytes('6f7fb4abcedb485ab27eb7bb39caf827'),
  CURRENT_MONTH_INFLATION_DATA: '287504', // March 2022 Inflation Data
  PREVIOUS_MONTH_INFLATION_DATA: '283716', // February 2022 Inflation Data
  MINT_FEE_BASIS_POINTS: 10, // Fee tentatively set at 10 basis points
  REDEEM_FEE_BASIS_POINTS: 0,
  DEPLOYER_VOLT_AMOUNT: ethers.utils.parseEther('40000000'), // 40m
  MAX_BUFFER_CAP: ethers.utils.parseEther('10000000'), // 10m
  VOLT_SWAP_AMOUNT: ethers.utils.parseEther('10000000'), // 10m
  MAX_BUFFER_CAP_MULTI_RATE_LIMITED: ethers.utils.parseEther('100000000'), // 100m
  RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('10000'), // 10k VOLT/s
  MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('100000'), // 100k VOLT/s
  GLOBAL_MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('100000'), // 100k VOLT/s
  PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('15000'), // 15k VOLT/s
  PSM_BUFFER_CAP: ethers.utils.parseEther('10000000'), // 10m VOLT
  FEI: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
  POOL_8_FEI: '0xd8553552f8868C1Ef160eEdf031cF0BCf9686945',
  ZERO_ADDRESS: ethers.constants.AddressZero
};

export default config;

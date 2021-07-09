const UniswapPCVDeposit = artifacts.require('UniswapPCVDeposit');
const UniswapPCVController = artifacts.require('UniswapPCVController');
const BondingCurve = artifacts.require('BondingCurve');
const TribeReserveStabilizer = artifacts.require('TribeReserveStabilizer');
const EthReserveStabilizer = artifacts.require('EthReserveStabilizer');
const PCVDripController = artifacts.require('PCVDripController');
const RatioPCVController = artifacts.require('RatioPCVController');
const Core = artifacts.require('Core');
const Tribe = artifacts.require('Tribe');

async function setup(addresses, oldContractAddresses, logging) {}

async function run(addresses, oldContractAddresses, logging = false) {
  const {
    coreAddress,
    uniswapPCVDepositAddress,
    uniswapPCVControllerAddress,
    bondingCurveAddress,
    ethReserveStabilizerAddress,
    tribeReserveStabilizerAddress,
    ratioPCVControllerAddress,
    pcvDripControllerAddress,
    timelockAddress
  } = addresses;

  const deposit = await UniswapPCVDeposit.at(uniswapPCVDepositAddress);
  const controller = await UniswapPCVController.at(uniswapPCVControllerAddress);
  const bondingCurve = await BondingCurve.at(bondingCurveAddress);
  const tribeReserveStabilizer = await TribeReserveStabilizer.at(tribeReserveStabilizerAddress);
  
  const ratioPCVController = await RatioPCVController.at(ratioPCVControllerAddress);
  const oldRatioPCVController = await RatioPCVController.at(oldContractAddresses.ratioPCVControllerAddress);
  const pcvDripController = await PCVDripController.at(pcvDripControllerAddress);
  const ethReserveStabilizer = await EthReserveStabilizer.at(ethReserveStabilizerAddress);

  const core = await Core.at(coreAddress);
  const tribe = await Tribe.at(await core.tribe());

  logging ? console.log('Granting Burner to new UniswapPCVController') : undefined;
  await core.grantBurner(controller.address);

  logging ? console.log('Granting Minter to new UniswapPCVController') : undefined;
  await core.grantMinter(controller.address);

  logging ? console.log('Granting Minter to new BondingCurve') : undefined;
  await core.grantMinter(bondingCurve.address);

  logging ? console.log('Granting Minter to new UniswapPCVDeposit') : undefined;
  await core.grantMinter(deposit.address);

  logging ? console.log('Granting Burner to new TribeReserveStabilizer') : undefined;
  await core.grantBurner(tribeReserveStabilizer.address);

  // special role
  // check via tribe contract
  logging ? console.log('Transferring TRIBE Minter role to TribeReserveStabilizer') : undefined;
  await tribe.setMinter(tribeReserveStabilizer.address, {from: timelockAddress});

  logging ? console.log('Granting Burner to new EthReserveStabilizer') : undefined;
  await core.grantBurner(ethReserveStabilizer.address);

  logging ? console.log('Granting PCVController to new RatioPCVController') : undefined;
  await core.grantPCVController(ratioPCVController.address);

  logging ? console.log('Granting PCVController to new PCVDripController') : undefined;
  await core.grantPCVController(pcvDripController.address);

  logging ? console.log('Granting Minter to new PCVDripController') : undefined;
  await core.grantMinter(pcvDripController.address);

  await oldRatioPCVController.withdrawRatio(oldContractAddresses.uniswapPCVDepositAddress, uniswapPCVDepositAddress, '10000'); // move 100% of PCV from old -> new
}

/// /  --------------------- NOT RUN ON CHAIN ----------------------
async function teardown(addresses, oldContractAddresses) {
  const core = await Core.at(addresses.coreAddress);

  const {
    uniswapPCVDepositAddress,
    uniswapPCVControllerAddress,
    ethReserveStabilizerAddress,
    ratioPCVControllerAddress,
    bondingCurveAddress,
  } = oldContractAddresses;

  // Revoke controller permissions
  await core.revokeMinter(uniswapPCVControllerAddress);
  await core.revokeMinter(uniswapPCVDepositAddress);
  await core.revokeMinter(bondingCurveAddress);

  await core.revokeBurner(uniswapPCVControllerAddress);
  await core.revokeBurner(ethReserveStabilizerAddress);  

  await core.revokePCVController(ratioPCVControllerAddress);
  await core.revokePCVController(uniswapPCVControllerAddress);
}

module.exports = { setup, run, teardown };

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ScalingPriceOracle} from "../../oracle/ScalingPriceOracle.sol";
import {MockScalingPriceOracle} from "../../mock/MockScalingPriceOracle.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {BasePSM} from "../../peg/BasePSM.sol";
import {IBasePSM} from "../../peg/IBasePSM.sol";
import {VanillaPriceBoundPSM} from "../../peg/VanillaPriceBoundPSM.sol";
import {VanillaPSM} from "../../peg/VanillaPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {Constants} from "../../Constants.sol";

contract IntegrationTestVanillaPSMTest is DSTest {
    using SafeCast for *;

    VanillaPriceBoundPSM private priceBoundPsm;
    VanillaPSM private vanillaPsm;

    ICore private core = ICore(MainnetAddresses.CORE);
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private underlyingToken = usdc;

    address public makerUSDCPSM = MainnetAddresses.MAKER_USDC_PSM;

    uint256 public constant mintAmount = 10_000_000e6;
    uint256 public constant voltMintAmount = 10_000_000e18;

    /// @notice live FEI PCV Deposit
    IPCVDeposit public immutable pcvDeposit =
        IPCVDeposit(MainnetAddresses.VOLT_USDC_PSM);

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint128 voltFloorPrice = 900_000;
    uint128 voltCeilingPrice = 205_0000;

    function setUp() public {
        IBasePSM.OracleParams memory oracleParams;

        oracleParams = IBasePSM.OracleParams({
            coreAddress: address(core),
            oracleAddress: address(oracle),
            backupOracle: address(0),
            decimalsNormalizer: -12,
            doInvert: false
        });

        /// create PSM
        priceBoundPsm = new VanillaPriceBoundPSM(
            voltFloorPrice,
            voltCeilingPrice,
            oracleParams,
            IERC20(address(usdc))
        );

        vanillaPsm = new VanillaPSM(oracleParams, IERC20(address(usdc)));

        uint256 balance = usdc.balanceOf(makerUSDCPSM);
        vm.prank(makerUSDCPSM);
        usdc.transfer(address(this), balance);

        vm.startPrank(MainnetAddresses.GOVERNOR);

        /// grant the PSM the PCV Controller role
        core.grantMinter(MainnetAddresses.GOVERNOR);
        /// mint VOLT to the user
        volt.mint(address(priceBoundPsm), voltMintAmount);
        volt.mint(address(vanillaPsm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);

        vm.stopPrank();

        usdc.transfer(address(priceBoundPsm), balance / 3);
        usdc.transfer(address(vanillaPsm), balance / 3);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(!priceBoundPsm.doInvert());
        assertTrue(priceBoundPsm.isPriceValid());
        assertEq(priceBoundPsm.floor(), voltFloorPrice);
        assertEq(priceBoundPsm.ceiling(), voltCeilingPrice);
        assertEq(address(priceBoundPsm.oracle()), address(oracle));
        assertEq(address(priceBoundPsm.backupOracle()), address(0));
        assertEq(priceBoundPsm.decimalsNormalizer(), -12);
        assertEq(address(priceBoundPsm.underlyingToken()), address(usdc));

        assertTrue(!vanillaPsm.doInvert());
        assertEq(address(vanillaPsm.oracle()), address(oracle));
        assertEq(address(vanillaPsm.backupOracle()), address(0));
        assertEq(vanillaPsm.decimalsNormalizer(), -12);
        assertEq(address(vanillaPsm.underlyingToken()), address(usdc));
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut(uint128 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        assertApproxEq(
            priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );

        assertApproxEq(
            vanillaPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut(uint256 amountUSDCIn) public {
        vm.assume(usdc.balanceOf(address(this)) > amountUSDCIn);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

        uint256 amountOut = (((amountUSDCIn * 1e18) / currentPegPrice));

        assertApproxEq(
            priceBoundPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            vanillaPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            0
        );

        assertApproxEq(
            vanillaPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    function testMintFuzz(uint32 amountStableIn) public {
        uint256 amountVoltOut = vanillaPsm.getMintAmountOut(amountStableIn);

        uint256 amountVoltOutPriceBound = priceBoundPsm.getMintAmountOut(
            amountStableIn
        );

        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        underlyingToken.approve(address(vanillaPsm), amountStableIn);
        vanillaPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance1 = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(vanillaPsm)
        );

        underlyingToken.approve(address(priceBoundPsm), amountStableIn);

        priceBoundPsm.mint(
            address(this),
            amountStableIn,
            amountVoltOutPriceBound
        );

        uint256 endingUserVoltBalance2 = volt.balanceOf(address(this));

        uint256 endingPSMUnderlyingBalancePriceBound = underlyingToken
            .balanceOf(address(priceBoundPsm));

        assertEq(
            endingUserVoltBalance1,
            startingUserVoltBalance + amountVoltOut
        );

        assertEq(
            endingPSMUnderlyingBalance,
            endingPSMUnderlyingBalancePriceBound
        );

        assertEq(
            endingUserVoltBalance2 - endingUserVoltBalance1,
            amountVoltOut
        );

        assertEq(
            endingUserVoltBalance2 - endingUserVoltBalance1,
            amountVoltOutPriceBound
        );
    }

    function testRedeemFuzz(uint32 amountVoltIn) public {
        uint256 amountOut = vanillaPsm.getRedeemAmountOut(amountVoltIn);

        uint256 underlyingOutPriceBound = priceBoundPsm.getRedeemAmountOut(
            amountVoltIn
        );

        uint256 startingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );

        volt.approve(address(vanillaPsm), amountVoltIn);
        vanillaPsm.redeem(address(this), amountVoltIn, amountOut);

        uint256 endingUserUnderlyingBalance1 = underlyingToken.balanceOf(
            address(this)
        );
        uint256 endingPSMVoltBalance = volt.balanceOf(address(vanillaPsm));

        volt.approve(address(priceBoundPsm), amountVoltIn);

        priceBoundPsm.redeem(
            address(this),
            amountVoltIn,
            underlyingOutPriceBound
        );

        uint256 endingUserUnderlyingBalance2 = underlyingToken.balanceOf(
            address(this)
        );

        uint256 endingPSMUnderlyingBalancePriceBound = volt.balanceOf(
            address(priceBoundPsm)
        );

        assertEq(
            endingUserUnderlyingBalance1,
            startingUserUnderlyingBalance + amountOut
        );

        assertEq(endingPSMVoltBalance, endingPSMUnderlyingBalancePriceBound);

        assertEq(
            endingUserUnderlyingBalance2 - endingUserUnderlyingBalance1,
            amountOut
        );

        assertEq(
            endingUserUnderlyingBalance2 - endingUserUnderlyingBalance1,
            underlyingOutPriceBound
        );
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVolt() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = vanillaPsm.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(vanillaPsm)
        );

        underlyingToken.approve(address(vanillaPsm), amountStableIn);
        vanillaPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(vanillaPsm)
        );

        assertEq(
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );
        assertEq(
            startingPSMUnderlyingBalance + amountStableIn,
            endingPSMUnderlyingBalance
        );
    }

    /// @notice redeem fails without approval
    function testSwapVoltForUSDCFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        vanillaPsm.redeem(address(this), mintAmount, mintAmount / 1e12);
    }

    /// @notice redeem fails without approval
    function testMintFailsWhenMintExceedsPSMBalance() public {
        underlyingToken.approve(address(vanillaPsm), type(uint256).max);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 psmVoltBalance = volt.balanceOf(address(vanillaPsm));

        // we get the amount we want to put in by getting the total PSM balance and dividing by the current peg price
        // this lets us get the maximum amount we can deposit
        uint256 amountIn = (psmVoltBalance * currentPegPrice) / 1e6;

        // this will revert (correctly) as the math above is less precise than the PSMs, therefore our amountIn
        // will slightly exceed the balance the PSM can give to us.
        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));

        vanillaPsm.mint(address(this), amountIn, psmVoltBalance);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        vanillaPsm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw succeeds with correct permissions
    function testWithdrawSuccess() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        vanillaPsm.withdraw(address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice withdraw fails without correct permissions
    function testWithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));

        vanillaPsm.withdraw(address(this), 100);
    }

    /// @notice withdraw erc20 fails without correct permissions
    function testERC20WithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));

        vanillaPsm.withdrawERC20(address(underlyingToken), address(this), 100);
    }

    /// @notice withdraw erc20 succeeds with correct permissions
    function testERC20WithdrawSuccess() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        vanillaPsm.withdrawERC20(
            address(underlyingToken),
            address(this),
            mintAmount
        );
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice redeem fails when paused
    function testRedeemFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vanillaPsm.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        vanillaPsm.redeem(address(this), 100, 100);
    }

    /// @notice mint fails when paused
    function testMintFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vanillaPsm.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        vanillaPsm.mint(address(this), 100, 100);
    }
}

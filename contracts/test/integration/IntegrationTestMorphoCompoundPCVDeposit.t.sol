//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {Constants} from "../../Constants.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {MorphoCompoundPCVDeposit} from "../../pcv/morpho/MorphoCompoundPCVDeposit.sol";

contract IntegrationTestMorphoCompoundPCVDeposit is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    MorphoCompoundPCVDeposit private daiDeposit;
    MorphoCompoundPCVDeposit private usdcDeposit;

    PCVGuardian private immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Core private core = Core(MainnetAddresses.CORE);
    PegStabilityModule private daiPSM =
        PegStabilityModule(MainnetAddresses.VOLT_DAI_PSM);

    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private comp = IERC20(MainnetAddresses.COMP);

    uint256 public daiBalance;
    uint256 public usdcBalance;

    uint256 targetDaiBalance = 100_000e18;
    uint256 targetUsdcBalance = 100_000e6;

    uint256 public constant epochLength = 100 days;

    function setUp() public {
        daiDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            MainnetAddresses.CDAI,
            MainnetAddresses.DAI,
            MainnetAddresses.MORPHO,
            MainnetAddresses.MORPHO_LENS
        );

        usdcDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            MainnetAddresses.CUSDC,
            MainnetAddresses.USDC,
            MainnetAddresses.MORPHO,
            MainnetAddresses.MORPHO_LENS
        );

        vm.label(address(daiDeposit), "Morpho DAI Compound PCV Deposit");
        vm.label(address(usdcDeposit), "Morpho USDC Compound PCV Deposit");
        vm.label(address(MainnetAddresses.CDAI), "CDAI");
        vm.label(address(MainnetAddresses.CUSDC), "CUSDC");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67, "Morpho Lens");
        vm.label(0x8888882f8f843896699869179fB6E4f7e3B58888, "Morpho");

        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(daiDeposit), targetDaiBalance);
        usdc.transfer(address(usdcDeposit), targetUsdcBalance);
        vm.stopPrank();

        usdcDeposit.deposit();
        daiDeposit.deposit();

        vm.roll(block.number + 1); /// fast forward 1 block so that profit is positive
    }

    function testSetup() public {
        assertEq(address(daiDeposit.core()), address(core));
        assertEq(address(usdcDeposit.core()), address(core));
        assertEq(daiDeposit.morpho(), MainnetAddresses.MORPHO);
        assertEq(usdcDeposit.morpho(), MainnetAddresses.MORPHO);
        assertEq(daiDeposit.lens(), MainnetAddresses.MORPHO_LENS);
        assertEq(usdcDeposit.lens(), MainnetAddresses.MORPHO_LENS);

        assertEq(daiDeposit.balanceReportedIn(), address(dai));
        assertEq(usdcDeposit.balanceReportedIn(), address(usdc));

        assertEq(address(daiDeposit.cToken()), address(MainnetAddresses.CDAI));
        assertEq(
            address(usdcDeposit.cToken()),
            address(MainnetAddresses.CUSDC)
        );

        assertEq(address(daiDeposit.token()), address(MainnetAddresses.DAI));
        assertEq(address(usdcDeposit.token()), address(MainnetAddresses.USDC));

        assertEq(daiDeposit.lastRecordedBalance(), targetDaiBalance);
        assertEq(usdcDeposit.lastRecordedBalance(), targetUsdcBalance);

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            targetDaiBalance.toInt256(),
            0
        );
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testWithdraw() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), usdcDeposit.balance());
        daiDeposit.withdraw(address(this), daiDeposit.balance());
        vm.stopPrank();

        assertApproxEq(
            dai.balanceOf(address(this)).toInt256(),
            targetDaiBalance.toInt256(),
            0
        );
        assertApproxEq(
            usdc.balanceOf(address(this)).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testHarvest() public {
        /// fast forward block number amount
        vm.roll(block.number + epochLength / 12);

        uint256 startingCompBalance = comp.balanceOf(address(usdcDeposit)) +
            comp.balanceOf(address(daiDeposit));
        usdcDeposit.harvest();
        daiDeposit.harvest();
        uint256 endingCompBalance = comp.balanceOf(address(usdcDeposit)) +
            comp.balanceOf(address(daiDeposit));

        uint256 compDelta = endingCompBalance - startingCompBalance;

        assertTrue(compDelta != 0);
    }

    /// 2**80 / 1e18 = ~1.2m which is above target dai balance
    function testWithdrawDaiFuzz(uint80 amount) public {
        /// 1 fails in some underlying contract, and this isn't a scenario we are going to realistically have
        /// as 1e9 wei of dai would always cost more in gas than the dai is worth
        vm.assume(amount >= 1e9);
        vm.assume(amount <= targetDaiBalance);

        vm.prank(MainnetAddresses.GOVERNOR);
        daiDeposit.withdraw(address(this), amount);

        assertEq(dai.balanceOf(address(this)), amount);

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (targetDaiBalance - amount).toInt256(),
            0
        );
    }

    function testWithdrawUsdcFuzz(uint40 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount <= targetUsdcBalance);

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), amount);

        assertEq(usdc.balanceOf(address(this)), amount);

        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (targetUsdcBalance - amount).toInt256(),
            0
        );
    }

    function testWithdrawAll() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdrawAll(address(this));
        daiDeposit.withdrawAll(address(this));
        vm.stopPrank();

        assertApproxEq(
            dai.balanceOf(address(this)).toInt256(),
            targetDaiBalance.toInt256(),
            0
        );

        assertApproxEq(
            usdc.balanceOf(address(this)).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testDepositNoFundsSucceeds() public {
        usdcDeposit.deposit();
        daiDeposit.deposit();
    }

    function testDepositWhenPausedFails() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.pause();
        vm.expectRevert("Pausable: paused");
        usdcDeposit.deposit();

        vm.prank(MainnetAddresses.GOVERNOR);
        daiDeposit.pause();
        vm.expectRevert("Pausable: paused");
        daiDeposit.deposit();
    }

    function testWithdrawNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdraw(address(this), targetUsdcBalance);

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        daiDeposit.withdraw(address(this), targetDaiBalance);
    }

    function testWithdrawAllNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawAll(address(this));

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        daiDeposit.withdrawAll(address(this));
    }
}

// =============================================================================
// FormosaSoC VexRiscv CPU 產生器
// =============================================================================
// 產生客製化的 VexRiscv RISC-V CPU，配置如下：
//   ISA:       RV32IMC (Integer + Mul/Div + Compressed)
//   匯流排:    Wishbone B4 (iBus + dBus 分離 master)
//   快取:      無 (Simple plugins)
//   特權模式:  Machine Mode only
//   重置向量:  0x00000000
//   中斷:      timerInterrupt, softwareInterrupt, externalInterrupt
//
// 執行方式：
//   cd tools/vexriscv_gen
//   sbt "runMain formosa.GenFormosaVexRiscv"
//
// 輸出：
//   ../../rtl/core/VexRiscv.v
// =============================================================================

package formosa

import spinal.core._
import spinal.lib._
import vexriscv._
import vexriscv.plugin._

object GenFormosaVexRiscv extends App {
  def cpu() = new VexRiscv(
    config = VexRiscvConfig(
      plugins = List(
        // --- 指令擷取 (IBus) ---
        new IBusSimplePlugin(
          resetVector = 0x00000000L,
          cmdForkOnSecondStage = false,
          cmdForkPersistence = false,
          prediction = NONE,
          catchAccessFault = false,
          compressedGen = true
        ),

        // --- 資料存取 (DBus) ---
        new DBusSimplePlugin(
          catchAddressMisaligned = false,
          catchAccessFault = false
        ),

        // --- 整數暫存器檔 ---
        new RegFilePlugin(
          regFileReadyKind = plugin.SYNC,
          zeroBoot = false
        ),

        // --- 解碼器 ---
        new DecoderSimplePlugin(
          catchIllegalInstruction = true
        ),

        // --- 整數 ALU ---
        new IntAluPlugin,

        // --- Shift 指令 ---
        new LightShifterPlugin,

        // --- 分支/跳躍 ---
        new BranchPlugin(
          earlyBranch = false,
          catchAddressMisaligned = false
        ),

        // --- 資料轉發與風險處理 ---
        new HazardSimplePlugin(
          bypassExecute = true,
          bypassMemory = true,
          bypassWriteBack = true,
          bypassWriteBackBuffer = true,
          pessimisticUseSrc = false,
          pessimisticWriteRegFile = false,
          pessimisticAddressMatch = false
        ),

        // --- 乘法/除法 (M 擴展) ---
        new MulPlugin,
        new DivPlugin,

        // --- CSR (Machine Mode) ---
        new CsrPlugin(
          config = CsrPluginConfig(
            catchIllegalAccess = false,
            mvendorid = null,
            marchid = null,
            mimpid = null,
            mhartid = null,
            misaExtensionsInit = 0, // 由 SpinalHDL 自動設定
            misaAccess = CsrAccess.NONE,
            mtvecAccess = CsrAccess.READ_WRITE,
            mtvecInit = 0x00000000L,
            mepcAccess = CsrAccess.READ_WRITE,
            mscratchGen = true,
            mcauseAccess = CsrAccess.READ_ONLY,
            mbadaddrAccess = CsrAccess.READ_ONLY,
            mcycleAccess = CsrAccess.NONE,
            minstretAccess = CsrAccess.NONE,
            ecallGen = true,
            wfiGenAsWait = false,
            ucycleAccess = CsrAccess.NONE
          )
        ),

        // --- Wishbone 匯流排橋接 ---
        new YamlPlugin("cpu0.yaml")
      )
    )
  )

  // --- 產生 Verilog ---
  SpinalConfig(
    mode = Verilog,
    targetDirectory = "../../rtl/core"
  ).generate(cpu())
}

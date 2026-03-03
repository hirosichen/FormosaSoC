// =============================================================================
// FormosaSoC VexRiscv CPU 產生器 — SBT 建構配置
// =============================================================================
// 使用 SpinalHDL 產生客製化的 VexRiscv RISC-V CPU Verilog 檔案。
// 執行方式：sbt "runMain formosa.GenFormosaVexRiscv"
// =============================================================================

name := "FormosaVexRiscv"
version := "1.0"
scalaVersion := "2.12.18"

val spinalVersion = "1.10.2a"

libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion,
  "com.github.spinalhdl" %% "spinalhdl-lib"  % spinalVersion,
  compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion)
)

libraryDependencies += "com.github.spinalhdl" % "vexriscv_2.12" % "2.0.0"

fork := true

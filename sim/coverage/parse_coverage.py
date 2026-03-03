#!/usr/bin/env python3
"""
FormosaSoC - 覆蓋率報告解析器
解析 Verilator 標註報告，產生每模組覆蓋率摘要
"""

import os
import re
import sys

REPORT_DIR = os.path.join(os.path.dirname(__file__), "report")
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "coverage_detail.txt")

MODULES = [
    ("GPIO",    "formosa_gpio.v"),
    ("UART",    "formosa_uart.v"),
    ("SPI",     "formosa_spi.v"),
    ("I2C",     "formosa_i2c.v"),
    ("Timer",   "formosa_timer.v"),
    ("PWM",     "formosa_pwm.v"),
    ("WDT",     "formosa_wdt.v"),
    ("IRQ",     "formosa_irq_ctrl.v"),
    ("DMA",     "formosa_dma.v"),
    ("ADC",     "formosa_adc_if.v"),
]

def parse_annotated_file(filepath):
    """解析 Verilator 標註檔案，計算行覆蓋率"""
    total_points = 0
    covered_points = 0
    uncovered_lines = []

    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        for line_num, line in enumerate(f, 1):
            # 格式: %000001  content  (未覆蓋, 數字表示覆蓋計數應該是多少)
            # 或:   000001  content  (已覆蓋)
            # 帶 %00 前綴 = 未覆蓋
            m = re.match(r'\s*(%?)(\d+)\s+(.*)', line)
            if m:
                is_uncovered = m.group(1) == '%'
                count = int(m.group(2))
                content = m.group(3).rstrip()

                if count > 0 or is_uncovered:
                    total_points += 1
                    if not is_uncovered and count > 0:
                        covered_points += 1
                    elif is_uncovered:
                        uncovered_lines.append((line_num, content[:80]))

    return total_points, covered_points, uncovered_lines

def main():
    results = []

    for name, filename in MODULES:
        filepath = os.path.join(REPORT_DIR, filename)
        if not os.path.exists(filepath):
            results.append((name, filename, 0, 0, []))
            continue

        total, covered, uncovered = parse_annotated_file(filepath)
        results.append((name, filename, total, covered, uncovered))

    # 輸出報告
    lines = []
    lines.append("=" * 72)
    lines.append(" FormosaSoC 程式碼覆蓋率詳細報告")
    lines.append("=" * 72)
    lines.append("")

    # 摘要表格
    lines.append(f"{'模組':<10} {'檔案':<25} {'覆蓋點':<10} {'總點數':<10} {'覆蓋率':<10}")
    lines.append("-" * 72)

    grand_total = 0
    grand_covered = 0

    for name, filename, total, covered, uncovered in results:
        pct = f"{covered/total*100:.1f}%" if total > 0 else "N/A"
        lines.append(f"{name:<10} {filename:<25} {covered:<10} {total:<10} {pct:<10}")
        grand_total += total
        grand_covered += covered

    lines.append("-" * 72)
    grand_pct = f"{grand_covered/grand_total*100:.1f}%" if grand_total > 0 else "N/A"
    lines.append(f"{'合計':<10} {'':<25} {grand_covered:<10} {grand_total:<10} {grand_pct:<10}")
    lines.append("")

    # 各模組未覆蓋行列表
    lines.append("=" * 72)
    lines.append(" 未覆蓋程式碼行 (前 10 行)")
    lines.append("=" * 72)

    for name, filename, total, covered, uncovered in results:
        if uncovered:
            lines.append(f"\n--- {name} ({filename}) ---")
            for line_num, content in uncovered[:10]:
                lines.append(f"  L{line_num:4d}: {content}")
            if len(uncovered) > 10:
                lines.append(f"  ... 還有 {len(uncovered)-10} 行未覆蓋")

    report = "\n".join(lines)
    print(report)

    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write(report + "\n")

    print(f"\n報告已寫入: {OUTPUT_FILE}")

if __name__ == "__main__":
    main()

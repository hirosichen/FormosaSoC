#!/usr/bin/env python3
"""
將二進位檔案轉換為 Verilog $readmemh 格式的 hex 檔案。

用法: python3 bin2hex.py input.bin output.hex

每行輸出一個 32-bit word (8 個十六進位字元)，
以小端序 (little-endian) 從二進位檔案讀取。
"""

import sys
import struct


def bin2hex(input_file, output_file):
    with open(input_file, "rb") as f:
        data = f.read()

    # 補齊到 4 byte 邊界
    while len(data) % 4 != 0:
        data += b"\x00"

    with open(output_file, "w") as f:
        for i in range(0, len(data), 4):
            word = struct.unpack("<I", data[i : i + 4])[0]
            f.write(f"{word:08X}\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"用法: {sys.argv[0]} input.bin output.hex")
        sys.exit(1)
    bin2hex(sys.argv[1], sys.argv[2])

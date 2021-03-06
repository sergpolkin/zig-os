#! /usr/bin/env python3

import sys
import subprocess

KERNEL_OFFSET = 1024 * 512


def _concat(a, b):
    while (True):
        buf = b.read(4*1024)
        if (len(buf) == 0):
            break
        a.write(buf)

def main():
    if len(sys.argv) != 4:
        return -1
    bootloader = sys.argv[1]
    kernel = sys.argv[2]
    image = sys.argv[3]
    # TODO check `bootloader` and `kernel` exists

    # Generate `bootloader` binary
    subprocess.check_call(['objcopy', '-Obinary', bootloader, image])

    with open(image, 'r+b') as image_fd:
        # Get `bootloader` length
        image_fd.seek(0, 2)
        bootloader_len = image_fd.tell()
        print(f"[gen_image] Bootloader size: {bootloader_len} bytes")
        # Append `kernel` ELF file
        image_fd.seek(KERNEL_OFFSET, 0)
        _concat(image_fd, open(kernel, 'rb'))

    return 0


if __name__ == '__main__':
    raise SystemExit(main())

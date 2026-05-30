# ==============================================================================
# PingOS Makefile - Build and Run Bootloader Only
# ==============================================================================

# Tools
ASM     = nasm
QEMU    = qemu-system-i386

# Target: build the bootloader binary
all: boot.bin

# Compile the assembly bootloader
boot.bin: boot.asm
	$(ASM) -f bin $< -o $@

# Run target to instantly test your bootloader inside the QEMU emulator
run: boot.bin
	$(QEMU) -drive format=raw,file=boot.bin

# Clean up build artifacts
clean:
	rm -f boot.bin

.PHONY: all run clean

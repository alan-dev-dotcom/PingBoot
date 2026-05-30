; ==============================================================================
; PingOS Bootloader (PingBoot) - 16-bit / 32-bit Assembly Bootloader
; ==============================================================================
[org 0x7c00]          ; BIOS loads the bootloader at physical memory address 0x7C00

KERNEL_OFFSET equ 0x1000 ; Memory offset where we will load our kernel

jmp boot_start

; --- Bootloader Data and Strings ---
MSG_BOOTING db "PingBoot: Loading PingOS Kernel from disk...", 0x0D, 0x0A, 0
MSG_DISK_ERR db "PingBoot ERROR: Failed to read from disk!", 0x0D, 0x0A, 0
BOOT_DRIVE db 0

boot_start:
    mov [BOOT_DRIVE], dl ; BIOS stores the boot drive number in DL on startup

    ; Set up segments to 0
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000      ; Set stack pointer safely away from the bootloader

    ; Print greeting message
    mov si, MSG_BOOTING
    call print_string_16

    ; Load kernel from disk
    call load_kernel

    ; Switch to 32-bit Protected Mode
    call switch_to_pm

    jmp $               ; Hang if we somehow return

; --- Helper: Print String in 16-bit Real Mode ---
print_string_16:
    pusha
.loop:
    lodsb               ; Load byte from SI into AL, increment SI
    or al, al           ; Check if AL is 0 (Null-terminator)
    jz .done
    mov ah, 0x0E        ; BIOS teletype video function
    int 0x10            ; Call video interrupt
    jmp .loop
.done:
    popa
    ret

; --- Helper: Load Kernel from Disk via BIOS ---
load_kernel:
    pusha
    mov ax, KERNEL_OFFSET ; ES:BX must point to the destination buffer
    mov es, ax
    xor bx, bx          ; Destination buffer = 0x1000:0000 (Physical 0x10000)

    mov ah, 0x02        ; BIOS read sector function
    mov al, 64          ; Read 64 sectors (32KB of kernel code - safe for larger builds)
    mov ch, 0x00        ; Cylinder 0
    mov dh, 0x00        ; Head 0
    mov cl, 0x02        ; Start reading from Sector 2 (Sector 1 is our Bootloader)
    mov dl, [BOOT_DRIVE] ; Load drive number
    int 0x13            ; BIOS Disk Interrupt

    jc disk_error       ; Jump if Carry Flag is set (indicates disk error)
    popa
    ret

disk_error:
    mov si, MSG_DISK_ERR
    call print_string_16
    jmp $               ; Hang on error

; ==============================================================================
; 32-bit Protected Mode Initialization
; ==============================================================================

; Global Descriptor Table (GDT) defining flat memory space
gdt_start:
    ; Null descriptor (required)
    dd 0x0
    dd 0x0

gdt_code:
    ; Code Segment Descriptor
    dw 0xffff           ; Limit (0-15)
    dw 0x0              ; Base (0-15)
    db 0x0              ; Base (16-23)
    db 10011010b        ; 1st flags, Type flags (Present, Ring 0, Code, Exec/Read)
    db 11001111b        ; 2nd flags, Limit (16-19)
    db 0x0              ; Base (24-31)

gdt_data:
    ; Data Segment Descriptor
    dw 0xffff           ; Limit (0-15)
    dw 0x0              ; Base (0-15)
    db 0x0              ; Base (16-23)
    db 10010010b        ; 1st flags, Type flags (Present, Ring 0, Data, Read/Write)
    db 11001111b        ; 2nd flags, Limit (16-19)
    db 0x0              ; Base (24-31)

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1 ; Size of GDT
    dd gdt_start               ; Start address of GDT

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

[bits 16]
switch_to_pm:
    cli                 ; Clear Interrupts (Disable BIOS interrupts)
    lgdt [gdt_descriptor] ; Load Global Descriptor Table pointer
    
    mov eax, cr0
    or eax, 0x1         ; Set protected mode bit in Control Register 0
    mov cr0, eax

    jmp CODE_SEG:init_pm ; Perform a Far Jump to flush CPU pipeline with 32-bit instructions

[bits 32]
init_pm:
    ; Update segment registers to point to 32-bit Data segment descriptor
    mov ax, DATA_SEG
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov ebp, 0x90000    ; Relocate Stack Pointer to top of free space
    mov esp, ebp

    call BEGIN_PM       ; Transfer execution to our 32-bit environment

BEGIN_PM:
    ; Jump to the loaded kernel's entry point address in RAM (0x10000)
    jmp CODE_SEG:0x10000

; Fill remaining space with zeros to ensure this file is exactly 512 bytes
times 510-($-$$) db 0
dw 0xaa55               ; Standard BIOS bootloader signature
; ==============================================================================
; PingOS Bootloader - 16-bit / 32-bit Optimized Assembly
; ==============================================================================
[org 0x7c00]

KERNEL_OFFSET equ 0x1000 ; Segment 0x1000 (0x10000 Physical)

jmp boot_start

; --- Optimized Compact Data (Short strings to save space) ---
MSG_TITLE    db "PingBoot", 0x0D, 0x0A, 0
opt_0       db "Text Mode", 0
opt_1      db "Reboot", 0
MSG_LOAD     db 0x0D, 0x0A, "Booting...", 0x0D, 0x0A, 0
MSG_ERR      db "Error!", 0x0D, 0x0A, 0

BOOT_DRIVE   db 0
selected_opt db 0      ; Current choice (0 to 2)

; Array of pointers to menu strings (for compact loop rendering)
menu_options:
    dw opt_0
    dw opt_1

boot_start:
    mov [BOOT_DRIVE], dl ; Save boot drive

    ; Initialize segments
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

menu_loop:
    call draw_menu

.wait_key:
    mov ah, 0x00
    int 0x16            ; Get key press (AH = Scan code, AL = ASCII)

    cmp ah, 0x48        ; Up Arrow
    je .go_up
    cmp ah, 0x50        ; Down Arrow
    je .go_down
    cmp al, 0x0D        ; Enter
    je .select
    jmp .wait_key

.go_up:
    dec byte [selected_opt]
    jns menu_loop
    mov byte [selected_opt], 2 ; Wrap to bottom
    jmp menu_loop

.go_down:
    inc byte [selected_opt]
    cmp byte [selected_opt], 3
    jl menu_loop
    mov byte [selected_opt], 0 ; Wrap to top
    jmp menu_loop

.select:
    mov al, [selected_opt]
    cmp al, 2
    je reboot_system
    cmp al, 0
    jne .continue_boot
    call setup_vbe

.continue_boot:
    mov si, MSG_LOAD
    call print_string_16

    call detect_memory
    call enable_a20
    call load_kernel
    call switch_to_pm
    jmp $

reboot_system:
    jmp 0xFFFF:0x0000   ; Warm reboot

; --- Render Interactive Menu (Optimized Loop) ---
draw_menu:
    ; Reset screen to standard text mode 3 (clears screen)
    mov ax, 0x0003
    int 0x10

    mov si, MSG_TITLE
    call print_string_16
    call print_newline

    xor cx, cx          ; CX = Current option index

.loop_opts:
    ; Print selection indicator
    mov al, ' '
    cmp cl, [selected_opt]
    jne .no_cursor
    mov al, '>'
.no_cursor:
    call print_char
    mov al, ' '
    call print_char

    ; Get menu option string address from word array
    mov bx, cx
    shl bx, 1           ; Index * 2 (words)
    mov si, [menu_options + bx]
    call print_string_16
    call print_newline

    inc cx
    cmp cx, 3
    jl .loop_opts
    ret

print_char:
    mov ah, 0x0E
    int 0x10
    ret

print_newline:
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    ret

print_string_16:
    pusha
.loop:
    lodsb
    or al, al
    jz .done
    call print_char
    jmp .loop
.done:
    popa
    ret

; --- Get System Memory Map (E820) ---
detect_memory:
    pusha
    mov di, 0x9004
    xor ebx, ebx
    xor bp, bp          ; Entry count
    mov edx, 0x534D4150

.loop:
    mov eax, 0xE820
    mov ecx, 24
    int 0x15
    jc .done
    cmp eax, 0x534D4150
    jne .done
    add di, 24
    inc bp
    test ebx, ebx
    jne .loop

.done:
    mov [0x9000], bp    ; Save count at 0x9000
    popa
    ret

; --- Enable A20 ---
enable_a20:
    pusha
    mov ax, 0x2401
    int 0x15            ; BIOS enable
    in al, 0x92
    or al, 2
    out 0x92, al        ; Fast A20
    popa
    ret

; --- Setup VBE Graphics Mode ---
setup_vbe:
    pusha
    mov ax, 0x4F01
    mov cx, 0x4115      ; VBE Mode 800x600x32bpp with LFB
    mov di, 0x8000      ; Info block destination
    int 0x10
    cmp ax, 0x004F
    jne .err

    mov ax, 0x4F02
    mov bx, 0x4115
    int 0x10
    cmp ax, 0x004F
    je .done

.err:
    mov si, MSG_ERR
    call print_string_16
.done:
    popa
    ret

; --- Load Kernel with Retries ---
load_kernel:
    pusha
    mov cl, 3           ; Retries
.retry:
    push cx
    mov ax, KERNEL_OFFSET
    mov es, ax
    xor bx, bx          ; ES:BX = 0x1000:0000

    mov ax, 0x0240      ; AH = 02 (Read), AL = 64 (Sectors)
    mov cx, 0x0002      ; CH = 0 (Cylinder), CL = 2 (Sector)
    mov dh, 0x00        ; DH = 0 (Head)
    mov dl, [BOOT_DRIVE]
    int 0x13
    jnc .success

    ; Reset disk
    xor ax, ax
    int 0x13
    pop cx
    dec cl
    jnz .retry

    mov si, MSG_ERR
    call print_string_16
    jmp $               ; Hang on failure

.success:
    pop cx
    popa
    ret

; ==============================================================================
; Protected Mode Setup
; ==============================================================================

gdt_start:
    dd 0, 0             ; Null Descriptor
gdt_code:
    dw 0xffff, 0
    db 0, 10011010b, 11001111b, 0
gdt_data:
    dw 0xffff, 0
    db 0, 10010010b, 11001111b, 0
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

[bits 16]
switch_to_pm:
    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp CODE_SEG:init_pm

[bits 32]
init_pm:
    mov ax, DATA_SEG
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ebp, 0x90000
    mov esp, ebp
    jmp CODE_SEG:0x10000

times 510-($-$$) db 0
dw 0xaa55
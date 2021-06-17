; [org  0x7c00]
[bits 16]

extern main

section .start
global _start
_start:
    ; Clear direction flag
    cld

    ; Set the A20 line
    in    al, 0x92
    or    al, 2
    out 0x92, al

; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

read_disk:
    ; Read from disk in LBA mode
    ; BIOS set "Drive Number" in `dl`
    mov ax, lba_struct
    mov si, ax
    mov ah, 0x42
    int 0x13
    ; jc  hang

    ; check number of transfer sectors
    mov cx, [lba_struct + 2]
    cmp cx, 0
    je  lba_read_error

    ; display 'A'
    mov ax, 0xb800
    mov ds, ax
    xor ax, ax
    mov si, ax
    mov ax, 0x0f41
    mov [si], ax

    ; Continue boot (switch to 32-bit mode)
    jmp boot_stage1

lba_read_error:
    ; display 'E'
    mov ax, 0xb800
    mov ds, ax
    xor ax, ax
    mov si, ax
    mov ax, 0x0f45
    mov [si], ax

hang:
    cli
    hlt

align 8
lba_struct:
    db 0x10
    db 0
    ; number of sectors to transfer
    dw 127
    ; destination address (0:7e00)
    dw 0x7e00  ; 16-bit offset
    dw 0       ; 16-bit segment
    ; starting LBA
    dd 1       ; lower 32-bits
    dd 0       ; upper 32-bits

; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

boot_stage1:
    ; Disable interrupts
    cli

    ; Clear DS
    xor ax, ax
    mov ds, ax

    ; Load a 32-bit GDT
    lgdt [gdt]

    ; Enable protected mode
    mov eax, cr0
    or  eax, (1 << 0)
    mov cr0, eax

    ; Transition to 32-bit mode by setting CS to a protected mode selector
    jmp 0x0008:pm_entry

; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[bits 32]

pm_entry:
    ; Set up all data selectors
    mov ax, 0x10
    mov es, ax
    mov ds, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Set up a basic stack
    mov esp, 0x7c00

    jmp entry_point

; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

align 8
gdt_base:
    dq 0x0000000000000000 ; 0x0000 | Null descriptor
    dq 0x00cf9a000000ffff ; 0x0008 | 32-bit, present, code, base 0
    dq 0x00cf92000000ffff ; 0x0010 | 32-bit, present, data, base 0

gdt:
    dw (gdt - gdt_base) - 1
    dd gdt_base

; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

align 8
entry_point:
    ; display 'B'
    mov ax, 0x0f42
    mov word [dword 0xb8002], ax

    mov eax, 0x12345678
    push eax

    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx

    call main

; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    times 510-($-$$) db 0
    dw 0xaa55

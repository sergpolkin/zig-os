[bits 32]

struc register_state
	.eax: resd 1
	.ecx: resd 1
	.edx: resd 1
	.ebx: resd 1
	.esp: resd 1
	.ebp: resd 1
	.esi: resd 1
	.edi: resd 1
	.efl: resd 1

	.es: resw 1
	.ds: resw 1
	.fs: resw 1
	.gs: resw 1
	.ss: resw 1
endstruc

global _invoke_realmode
align 16
_invoke_realmode:
	pushad

	; Set all selectors to data segments
	mov ax, 0x10
	mov es, ax
	mov ds, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax
	jmp 0x0008:(.foop - PROGRAM_BASE)

[bits 16]
.foop:
	; Disable protected mode
	mov eax, cr0
	and eax, ~1
	mov cr0, eax

	; Clear out all segments
	xor ax, ax
	mov es, ax
	mov ds, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax

	; Set up a fake iret to do a long jump to switch to new cs.
	pushfd                                ; eflags
	push dword (PROGRAM_BASE >> 4)        ; cs
	push dword (.new_func - PROGRAM_BASE) ; eip
	iretd

.new_func:
	; Get the arguments passed to this function
	movzx ebx, byte  [esp + (4*0x9)] ; arg1, interrupt number
	shl   ebx, 2
	mov   eax, dword [esp + (4*0xa)] ; arg2, pointer to registers

	; Set up interrupt stack frame. This is what the real mode routine will
	; pop off the stack during its iret.
	mov ebp, (.retpoint - PROGRAM_BASE)
	pushfw
	push cs
	push bp

	; Set up the call for the interrupt by loading the contents of the IVT
	; based on the interrupt number specified
	pushfw
	push word [bx+2]
	push word [bx+0]

	; Load the register state specified
	mov ecx, dword [eax + register_state.ecx]
	mov edx, dword [eax + register_state.edx]
	mov ebx, dword [eax + register_state.ebx]
	mov ebp, dword [eax + register_state.ebp]
	mov esi, dword [eax + register_state.esi]
	mov edi, dword [eax + register_state.edi]
	mov eax, dword [eax + register_state.eax]

	; Perform a long jump to the interrupt entry point, simulating a software
	; interrupt instruction
	iretw

.retpoint:
	; Save off all registers
	push eax
	push ecx
	push edx
	push ebx
	push ebp
	push esi
	push edi
	pushfd
	push es
	push ds
	push fs
	push gs
	push ss

	; Get a pointer to the registers
	mov eax, dword [esp + (4*0xa) + (4*8) + (5*2)] ; arg2, pointer to registers

	; Update the register state with the post-interrupt register state.
	pop  word [eax + register_state.ss]
	pop  word [eax + register_state.gs]
	pop  word [eax + register_state.fs]
	pop  word [eax + register_state.ds]
	pop  word [eax + register_state.es]
	pop dword [eax + register_state.efl]
	pop dword [eax + register_state.edi]
	pop dword [eax + register_state.esi]
	pop dword [eax + register_state.ebp]
	pop dword [eax + register_state.ebx]
	pop dword [eax + register_state.edx]
	pop dword [eax + register_state.ecx]
	pop dword [eax + register_state.eax]

	; Enable protected mode
	mov eax, cr0
	or  eax, 1
	mov cr0, eax

	; Set all segments to data segments
	mov ax, 0x20
	mov es, ax
	mov ds, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax

	; Long jump back to protected mode.
	pushfd             ; eflags
	push dword 0x0018  ; cs
	push dword backout ; eip
	iretd

[bits 32]
backout:
	popad
	ret

ENTRY(_start)

SECTIONS {
    .text 0x7C00 :
    {
        KEEP(*(.start))
        *(.text .text.*)
        . = ALIGN(16);
    }

    .rodata :
    {
        *(.rodata .rodata.*)
        . = ALIGN(16);
    }

    .data :
    {
        *(.data.rel.ro.local*)
        *(.data.rel.ro .data.rel.ro.*)
        *(.data.*)
        . = ALIGN(16);
    }

    .bss :
    {
        *(.bss .bss.*)
        . = ALIGN(16);
    }
}

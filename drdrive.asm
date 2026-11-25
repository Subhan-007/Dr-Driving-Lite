; ============================================================
;  Dr. Driving Lite  -  HI-RES EDITION  (640x400, 256 colours)
;  Phase 1 + 2 + 3.  First-person graphics that follow the
;  figures of the project document.
;
;  NASM, DOS .COM file, real mode, VESA mode 100h (640x400x256).
;  Build :  nasm -f bin drdrive.asm -o drdrive.com   (all .inc files in the same folder)
;  Run   :  drdrive.com      (DOSBox:  cycles=max )
;
;  MENU      1 Highway   2 Parking   ESC quit
;  HIGHWAY   Up accelerate (hold)     Space brake to 0
;            Left / Right change lane Down reverse (speed 0 only)
;  PARKING   Up / Space / Down as above
;            Left / Right slide the car sideways (hold)
;  The steering wheel turns while you steer.
; ============================================================

bits 16
cpu 386
org 100h
    jmp start


%include "palette.inc"


; ---------------- layout / game constants -------------------


; ---- caches of the parts of the screen that never change ----

%macro RECT 5
    mov ax, %1
    mov bx, %2
    mov cx, %3
    mov dx, %4
    mov si, %5
    call rect
%endmacro

; ============================================================
;  MAIN
; ============================================================
start:
    cld
    mov ax, cs
    add ax, 1000h
    mov [bufseg], ax            ; 4 x 64K back buffer after our segment
    add ax, 4000h
    mov [dashseg], ax           ; cockpit cache
    add ax, 1000h
    mov [pkseg0], ax            ; parking background cache (2 segments)
    add ax, 1000h
    mov [pkseg1], ax

    mov ax, 1130h               ; BIOS 8x16 font -> fontbuf
    mov bh, 6
    int 10h
    push ds
    mov ax, es
    mov ds, ax
    mov si, bp
    push cs
    pop es
    mov di, fontbuf
    mov cx, 2048
    rep movsw
    pop ds

    push cs
    pop es
    mov ax, 4F01h               ; mode info -> window granularity
    mov cx, 100h
    mov di, modeinfo
    int 10h
    cmp ax, 004Fh
    jne novbe
    mov cx, [modeinfo+4]
    or cx, cx
    jnz .g
    mov cx, 64
.g: mov ax, 64
    xor dx, dx
    div cx
    mov [bank_unit], ax
    mov ax, 4F02h               ; 640x400x256
    mov bx, 100h
    int 10h
    cmp ax, 004Fh
    jne novbe

    push cs
    pop es
    xor bx, bx
    mov cx, 128
    mov dx, palette
    mov ax, 1012h
    int 10h

    call init_tables
    call init_caches

    mov ax, 3509h               ; keyboard interrupt
    int 21h
    mov [old9], bx
    mov [old9+2], es
    mov dx, int9
    mov ax, 2509h
    int 21h

    mov ax, 3508h               ; timer interrupt -> 70 Hz game clock
    int 21h
    mov [old8], bx
    mov [old8+2], es
    mov dx, int8
    mov ax, 2508h
    int 21h
    cli
    mov al, 36h
    out 43h, al
    mov ax, [pit_div]
    out 40h, al
    mov al, ah
    out 40h, al
    sti

main_menu:
    call menu                   ; AL = 0 quit, 1 highway, 2 parking
    or al, al
    jz quit
    cmp al, 1
    jne .park
    call run_highway
    jmp main_menu
.park:
    call run_parking
    jmp main_menu

novbe:
    mov ax, 0003h
    int 10h
    mov dx, s_novbe
    mov ah, 9
    int 21h
    mov ax, 4C01h
    int 21h

quit:
    cli                         ; timer back to 18.2 Hz
    mov al, 36h
    out 43h, al
    xor al, al
    out 40h, al
    out 40h, al
    sti
    push ds
    mov dx, [old8]
    mov ds, [old8+2]
    mov ax, 2508h
    int 21h
    pop ds
    push ds
    mov dx, [old9]
    mov ds, [old9+2]
    mov ax, 2509h
    int 21h
    pop ds
    mov ax, 0003h
    int 10h
    mov ax, 4C00h
    int 21h

; ============================================================
;  KEYBOARD INTERRUPT   keys[] = held, keys_new[] = just pressed
; ============================================================
int9:
    push ax
    push bx
    push ds
    mov ax, cs
    mov ds, ax
    in al, 60h
    cmp al, 0E0h
    je .eoi
    mov bl, al
    and bl, 7Fh
    xor bh, bh
    test al, 80h
    jnz .up
    cmp byte [keys+bx], 0
    jne .held
    mov byte [keys_new+bx], 1
    mov byte [any_key], 1
.held:
    mov byte [keys+bx], 1
    jmp .eoi
.up:
    mov byte [keys+bx], 0
.eoi:
    mov al, 20h
    out 20h, al
    pop ds
    pop bx
    pop ax
    iret

; ============================================================
;  TIMER INTERRUPT  70 Hz.  Counts game ticks and still calls the
;  old BIOS handler 18.2 times a second so the DOS clock is right.
; ============================================================
int8:
    push ax
    push ds
    mov ax, cs
    mov ds, ax
    inc word [ticks]
    mov ax, [pit_div]
    add [pit_acc], ax
    jc .chain
    mov al, 20h
    out 20h, al
    pop ds
    pop ax
    iret
.chain:
    pop ds
    pop ax
    jmp far [cs:old8]

; take_ticks  -> CX = game updates to run this frame (1..4)
take_ticks:
    cli
    mov cx, [ticks]
    cmp cx, 1
    jge .a
    mov cx, 1
.a: cmp cx, 4
    jle .b
    mov word [ticks], 4         ; far behind: drop the rest
    mov cx, 4
.b: sub [ticks], cx
    sti
    ret

clear_edges:
    push ax
    push cx
    push di
    push es
    push cs
    pop es
    mov di, keys_new
    mov cx, 128
    xor al, al
    rep stosb
    mov byte [any_key], 0
    pop es
    pop di
    pop cx
    pop ax
    ret

%include "gfx.inc"
%include "text.inc"
%include "tables.inc"
%include "cockpit.inc"
%include "road.inc"
%include "highway.inc"
%include "menu.inc"
%include "parking.inc"
%include "data.inc"

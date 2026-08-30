; Separate PH2 sprite-asset laboratory.  The source bank contains a static
; black/white scene built from the original game's atlas; the two screen banks
; are restored only beneath the actor, then composed with real idle frames.

        ORG 0x8000

START:
        DI
        LD SP,0xBFF0
        LD HL,0xBB00
        LD (HL),'P'
        INC HL
        LD (HL),'H'
        INC HL
        LD (HL),'2'
        INC HL
        LD (HL),'A'
        XOR A
        LD (STATUS_FRAMES),A
        LD (STATUS_FRAMES+1),A
        LD (STATUS_SCREEN),A
        LD (STATUS_IRQ),A
        LD (FRAME_INDEX),A
        LD (FRAME_TICKS),A
        LD A,1
        LD (RENDER_TO_7),A
        LD A,0xB9
        LD I,A
        IM 2
        EI

FRAME:
        CALL WAIT_IRQ
        CALL UPDATE_IDLE
        CALL DRAW_HIDDEN_SCREEN
        LD HL,(STATUS_FRAMES)
        INC HL
        LD (STATUS_FRAMES),HL
        JP FRAME

WAIT_IRQ:
        LD A,(STATUS_IRQ)
.wait:  HALT
        LD HL,STATUS_IRQ
        CP (HL)
        JR Z,.wait
        RET

DRAW_HIDDEN_SCREEN:
        LD A,(RENDER_TO_7)
        OR A
        JP NZ,DRAW_TO_7

; Bank 7 is displayed.  Bank 5 is in its fixed 0x4000 mapping.
DRAW_TO_5:
        CALL RESTORE_5
        CALL COMPOSE_5
        XOR A
        CALL PAGE_VALUE
        LD (STATUS_SCREEN),A
        LD A,1
        LD (RENDER_TO_7),A
        RET

; Bank 5 is displayed.  Bank 7 is paged at 0xC000 without selecting it for
; display; source pixels remain available through fixed bank 2 at 0xA000.
DRAW_TO_7:
        LD A,7
        CALL PAGE_VALUE
        CALL RESTORE_7
        CALL COMPOSE_7
        LD A,8
        CALL PAGE_VALUE
        LD A,1
        LD (STATUS_SCREEN),A
        XOR A
        LD (RENDER_TO_7),A
        RET

PAGE_VALUE:
        LD C,0xFD
        LD B,0x7F
        OUT (C),A
        RET

; Copy the exact 4-byte-wide player rectangle from the static source image.
; It is deliberately a tiny restore, not a full-screen redraw.
RESTORE_5:
        LD IY,SPRITE_ROWS_5
        JR RESTORE_BACKGROUND
RESTORE_7:
        LD IY,SPRITE_ROWS_7
RESTORE_BACKGROUND:
        LD IX,SPRITE_ROWS_SOURCE
        LD B,40
.row:   LD L,(IX+0)
        LD H,(IX+1)
        LD E,(IY+0)
        LD D,(IY+1)
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC IX
        INC IX
        INC IY
        INC IY
        DJNZ .row
        RET

COMPOSE_5:
        LD IX,SPRITE_ROWS_5
        JR COMPOSE_SPRITE
COMPOSE_7:
        LD IX,SPRITE_ROWS_7
COMPOSE_SPRITE:
        LD A,(FRAME_INDEX)
        ADD A,A
        LD E,A
        LD D,0
        LD HL,SPRITE_FRAME_TABLE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD B,40
.row:   LD L,(IX+0)
        LD H,(IX+1)
        LD A,(DE)
        INC DE
        AND (HL)
        LD C,A
        LD A,(DE)
        INC DE
        OR C
        LD (HL),A
        INC HL
        LD A,(DE)
        INC DE
        AND (HL)
        LD C,A
        LD A,(DE)
        INC DE
        OR C
        LD (HL),A
        INC HL
        LD A,(DE)
        INC DE
        AND (HL)
        LD C,A
        LD A,(DE)
        INC DE
        OR C
        LD (HL),A
        INC HL
        LD A,(DE)
        INC DE
        AND (HL)
        LD C,A
        LD A,(DE)
        INC DE
        OR C
        LD (HL),A
        INC IX
        INC IX
        DJNZ .row
        RET

; The sequence is authored source frames, held for eight complete presents.
UPDATE_IDLE:
        LD A,(FRAME_TICKS)
        INC A
        LD (FRAME_TICKS),A
        AND 7
        RET NZ
        LD A,(FRAME_INDEX)
        INC A
        CP 5
        JR C,.store
        XOR A
.store: LD (FRAME_INDEX),A
        RET

FRAME_INDEX:    DB 0
FRAME_TICKS:    DB 0
RENDER_TO_7:    DB 0

STATUS_FRAMES:  EQU 0xBB04
STATUS_SCREEN:  EQU 0xBB07
STATUS_IRQ:     EQU 0xBB08

        INCLUDE "generated_asset_lab.inc"

; Static source image: bank-2 raw offset 0x2000, fixed at 0xA000.
        ASSERT $ < 0xA000
        DEFS 0xA000-$,0
LAB_BACKGROUND:
        INCBIN "generated_asset_lab_background.bin"
        ASSERT $ <= 0xB800
        DEFS 0xB900-$,0
IM2_VECTORS:
        DEFS 257,0xBA
        DEFS 0xBABA-$,0
IM2_HANDLER:
        PUSH AF
        LD A,(STATUS_IRQ)
        INC A
        LD (STATUS_IRQ),A
        POP AF
        EI
        RETI
        ASSERT $ < 0xBB00

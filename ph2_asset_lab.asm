; Single-screen PH2 source-asset animation laboratory.
; Bank 5 remains visible.  Each independently timed object restores only its
; own background rectangle and then applies a conventional mask/ink blit.

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
        LD (HL),'M'
        XOR A
        LD (STATUS_FRAMES),A
        LD (STATUS_FRAMES+1),A
        LD (STATUS_SCREEN),A
        LD (STATUS_IRQ),A
        LD (PLAYER_FRAME),A
        LD (PLAYER_TICK),A
        LD (DINO_FRAME),A
        LD (DINO_TICK),A
        LD (FROG_FRAME),A
        LD (FROG_TICK),A
        LD (BUSH_FRAME),A
        LD (BUSH_TICK),A
        LD (CHECKPOINT_FRAME),A
        LD (CHECKPOINT_TICK),A
        LD A,1
        LD (DINO_TICK),A
        LD A,3
        LD (FROG_TICK),A
        LD A,2
        LD (BUSH_TICK),A
        LD A,5
        LD (CHECKPOINT_TICK),A
        CALL PAGE_BANK5
        CALL DRAW_PLAYER
        CALL DRAW_DINO
        CALL DRAW_FROG
        CALL DRAW_BUSH
        CALL DRAW_CHECKPOINT
        LD A,0xB9
        LD I,A
        IM 2
        EI

FRAME_LOOP:
        CALL WAIT_IRQ
        CALL UPDATE_PLAYER
        CALL UPDATE_DINO
        CALL UPDATE_FROG
        CALL UPDATE_BUSH
        CALL UPDATE_CHECKPOINT
        LD HL,(STATUS_FRAMES)
        INC HL
        LD (STATUS_FRAMES),HL
        JP FRAME_LOOP

WAIT_IRQ:
        LD A,(STATUS_IRQ)
.wait:  HALT
        LD HL,STATUS_IRQ
        CP (HL)
        JR Z,.wait
        RET

PAGE_BANK5:
        XOR A
        LD C,0xFD
        LD B,0x7F
        OUT (C),A
        RET

UPDATE_PLAYER:
        LD A,(PLAYER_TICK)
        INC A
        CP 8
        JR C,.store_tick
        XOR A
        LD (PLAYER_TICK),A
        LD A,(PLAYER_FRAME)
        INC A
        CP 5
        JR C,.store_frame
        XOR A
.store_frame:
        LD (PLAYER_FRAME),A
        JP DRAW_PLAYER
.store_tick:
        LD (PLAYER_TICK),A
        RET

UPDATE_DINO:
        LD A,(DINO_TICK)
        INC A
        CP 12
        JR C,.store_tick
        XOR A
        LD (DINO_TICK),A
        LD A,(DINO_FRAME)
        XOR 1
        LD (DINO_FRAME),A
        JP DRAW_DINO
.store_tick:
        LD (DINO_TICK),A
        RET

UPDATE_FROG:
        LD A,(FROG_TICK)
        INC A
        CP 10
        JR C,.store_tick
        XOR A
        LD (FROG_TICK),A
        LD A,(FROG_FRAME)
        XOR 1
        LD (FROG_FRAME),A
        JP DRAW_FROG
.store_tick:
        LD (FROG_TICK),A
        RET

UPDATE_BUSH:
        LD A,(BUSH_TICK)
        INC A
        CP 16
        JR C,.store_tick
        XOR A
        LD (BUSH_TICK),A
        LD A,(BUSH_FRAME)
        XOR 1
        LD (BUSH_FRAME),A
        JP DRAW_BUSH
.store_tick:
        LD (BUSH_TICK),A
        RET

UPDATE_CHECKPOINT:
        LD A,(CHECKPOINT_TICK)
        INC A
        CP 25
        JR C,.store_tick
        XOR A
        LD (CHECKPOINT_TICK),A
        LD A,(CHECKPOINT_FRAME)
        XOR 1
        LD (CHECKPOINT_FRAME),A
        JP DRAW_CHECKPOINT
.store_tick:
        LD (CHECKPOINT_TICK),A
        RET

DRAW_PLAYER:
        LD IX,PLAYER_ROWS_SOURCE
        LD IY,PLAYER_ROWS_SCREEN
        LD B,40
        LD C,4
        CALL RESTORE_RECT
        LD A,(PLAYER_FRAME)
        LD HL,PLAYER_FRAME_TABLE
        CALL SELECT_FRAME
        LD IX,PLAYER_ROWS_SCREEN
        LD B,40
        LD C,4
        JP COMPOSE_RECT

DRAW_DINO:
        LD IX,DINO_ROWS_SOURCE
        LD IY,DINO_ROWS_SCREEN
        LD B,32
        LD C,6
        CALL RESTORE_RECT
        LD A,(DINO_FRAME)
        LD HL,DINO_FRAME_TABLE
        CALL SELECT_FRAME
        LD IX,DINO_ROWS_SCREEN
        LD B,32
        LD C,6
        JP COMPOSE_RECT

DRAW_FROG:
        LD IX,FROG_ROWS_SOURCE
        LD IY,FROG_ROWS_SCREEN
        LD B,32
        LD C,6
        CALL RESTORE_RECT
        LD A,(FROG_FRAME)
        LD HL,FROG_FRAME_TABLE
        CALL SELECT_FRAME
        LD IX,FROG_ROWS_SCREEN
        LD B,32
        LD C,6
        JP COMPOSE_RECT

DRAW_BUSH:
        LD IX,BUSH_ROWS_SOURCE
        LD IY,BUSH_ROWS_SCREEN
        LD B,24
        LD C,7
        CALL RESTORE_RECT
        LD A,(BUSH_FRAME)
        LD HL,BUSH_FRAME_TABLE
        CALL SELECT_FRAME
        LD IX,BUSH_ROWS_SCREEN
        LD B,24
        LD C,7
        JP COMPOSE_RECT

DRAW_CHECKPOINT:
        LD IX,CHECKPOINT_ROWS_SOURCE
        LD IY,CHECKPOINT_ROWS_SCREEN
        LD B,72
        LD C,6
        CALL RESTORE_RECT
        LD A,(CHECKPOINT_FRAME)
        LD HL,CHECKPOINT_FRAME_TABLE
        CALL SELECT_FRAME
        LD IX,CHECKPOINT_ROWS_SCREEN
        LD B,72
        LD C,6
        JP COMPOSE_RECT

; A = zero-based frame, HL = pointer table.  Return selected frame in DE.
SELECT_FRAME:
        ADD A,A
        LD E,A
        LD D,0
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        RET

; IX = source-row address table, IY = screen-row address table,
; B = height, C = width in bytes.
RESTORE_RECT:
.row:  PUSH BC
        LD L,(IX+0)
        LD H,(IX+1)
        LD E,(IY+0)
        LD D,(IY+1)
        LD B,C
.byte: LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ .byte
        POP BC
        INC IX
        INC IX
        INC IY
        INC IY
        DJNZ .row
        RET

; IX = screen-row address table, DE = interleaved mask/ink frame,
; B = height, C = width in bytes.
COMPOSE_RECT:
.row:  PUSH BC
        LD L,(IX+0)
        LD H,(IX+1)
        LD B,C
.byte: LD A,(DE)
        INC DE
        AND (HL)
        LD C,A
        LD A,(DE)
        INC DE
        OR C
        LD (HL),A
        INC HL
        DJNZ .byte
        POP BC
        INC IX
        INC IX
        DJNZ .row
        RET

PLAYER_FRAME:       DB 0
PLAYER_TICK:        DB 0
DINO_FRAME:         DB 0
DINO_TICK:          DB 0
FROG_FRAME:         DB 0
FROG_TICK:          DB 0
BUSH_FRAME:         DB 0
BUSH_TICK:          DB 0
CHECKPOINT_FRAME:   DB 0
CHECKPOINT_TICK:    DB 0

STATUS_FRAMES:      EQU 0xBB04
STATUS_SCREEN:      EQU 0xBB07
STATUS_IRQ:         EQU 0xBB08

        INCLUDE "generated_asset_lab.inc"

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

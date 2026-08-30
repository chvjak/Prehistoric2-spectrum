; Stock 128K monochrome scrolling reference slice. Source pixels are unshifted,
; while two 8x256 lookup tables join the left/right byte halves for each X mod 8
; phase. Both screen banks use permanent white-on-black attributes: all per-frame
; work is bitmap-only.

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
        LD (HL),'L'
        XOR A
        LD (STATUS_FRAMES),A
        LD (STATUS_FRAMES+1),A
        LD (STATUS_LEVEL),A
        LD (STATUS_SCREEN),A
        LD (STATUS_IRQ),A
        LD (STATUS_MODE),A
        LD (STATUS_STEP),A
        LD (POSITION),A
        LD (POSITION+1),A
        LD (DIRECTION),A
        LD (DISPLAY_BIT),A
        LD (LEVEL_INDEX),A
        LD (LEVEL_BANK),A
        LD (CAMERA_MODE),A
        LD (MODE_TICKS),A
        LD (SPRITE_FRAME),A
        LD (SPRITE_TICKS),A
        LD A,1
        LD (DIRECTION),A
        LD (RENDER_TO_7),A
        LD A,0xB9
        LD I,A
        IM 2
        EI

FRAME:
        CALL WAIT_IRQ
        CALL UPDATE_SPRITE_ANIMATION
        CALL CALCULATE_OFFSET
        CALL DRAW_LEVEL
        CALL ADVANCE_SCROLL
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

; phase = x & 7, coarse = x >> 3.
CALCULATE_OFFSET:
        LD HL,(POSITION)
        LD A,L
        AND 7
        LD (PHASE),A
        SRL H
        RR L
        SRL H
        RR L
        SRL H
        RR L
        LD (COARSE),HL
        RET

DRAW_LEVEL:
        LD A,(RENDER_TO_7)
        OR A
        JP NZ,DRAW_TO_7

; Page 7 is visible; fill bank 5 through its fixed 0x4000 mapping.
DRAW_TO_5:
        LD A,(LEVEL_BANK)
        LD B,A
        LD A,(DISPLAY_BIT)
        OR B
        CALL PAGE_VALUE
        LD IX,ROW_TABLE
        LD A,LEVEL_HEIGHT
        LD (ROWS_LEFT),A
.row:   CALL LOAD_SOURCE
        LD C,(IX+2)
        LD B,(IX+3)
        CALL RENDER_PHASE
        CALL NEXT_ROW
        JR NZ,.row
        CALL COMPOSE_SPRITE_5
        XOR A
        LD (DISPLAY_BIT),A
        LD (STATUS_SCREEN),A
        LD A,1
        LD (RENDER_TO_7),A
        XOR A
        JP PAGE_VALUE

; Page 5 is visible. Build each row in fixed RAM, then page bank 7 briefly
; to commit it, keeping the displayed image untouched for the full render.
DRAW_TO_7:
        LD IX,ROW_TABLE
        LD A,LEVEL_HEIGHT
        LD (ROWS_LEFT),A
.row:   LD A,(LEVEL_BANK)
        CALL PAGE_VALUE
        CALL LOAD_SOURCE
        LD BC,SCRATCH_ROW
        CALL RENDER_PHASE
        LD A,7
        CALL PAGE_VALUE
        LD HL,SCRATCH_ROW
        LD E,(IX+2)
        LD D,(IX+3)
        SET 7,D
        LD BC,32
        LDIR
        CALL NEXT_ROW
        JR NZ,.row
        CALL COMPOSE_SPRITE_7
        LD A,8
        LD (DISPLAY_BIT),A
        LD A,1
        LD (STATUS_SCREEN),A
        XOR A
        LD (RENDER_TO_7),A
        LD A,15
        JP PAGE_VALUE

; Read source pointer from the row table and add the current whole-byte X.
; Returns source in DE; BC and IX remain available for the pixel phase routine.
LOAD_SOURCE:
        LD E,(IX+0)
        LD D,(IX+1)
        LD HL,(COARSE)
        ADD HL,DE
        EX DE,HL
        RET

NEXT_ROW:
        INC IX
        INC IX
        INC IX
        INC IX
        LD A,(ROWS_LEFT)
        DEC A
        LD (ROWS_LEFT),A
        RET

; DE = source, BC = destination. Phase routines are generated as 32 unrolled
; byte joins. Phase zero is the direct, fast copy case.
RENDER_PHASE:
        LD A,(PHASE)
        OR A
        JR NZ,.shifted
        EX DE,HL
        LD D,B
        LD E,C
        LD BC,32
        LDIR
        RET
.shifted:
        CP 1
        JP Z,PHASE_1
        CP 2
        JP Z,PHASE_2
        CP 3
        JP Z,PHASE_3
        CP 4
        JP Z,PHASE_4
        CP 5
        JP Z,PHASE_5
        CP 6
        JP Z,PHASE_6
        JP PHASE_7

PAGE_VALUE:
        LD C,0xFD
        LD B,0x7F
        OUT (C),A
        RET

; Proper monochrome software compositor. Sprite frames use (mask, ink) byte
; pairs: destination = (destination AND mask) OR ink. The two screen paths keep
; the physical displayed bank untouched until composition has finished.
COMPOSE_SPRITE_5:
        LD IX,SPRITE_ROWS_5
        JR COMPOSE_SPRITE
COMPOSE_SPRITE_7:
        LD IX,SPRITE_ROWS_7
COMPOSE_SPRITE:
        LD A,(SPRITE_FRAME)
        ADD A,A
        LD E,A
        LD D,0
        LD HL,SPRITE_FRAME_TABLE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD B,20
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
        INC IX
        INC IX
        DJNZ .row
        RET

; Advance a three-pose breathing/arm idle cycle every eight presented frames.
UPDATE_SPRITE_ANIMATION:
        LD A,(SPRITE_TICKS)
        INC A
        LD (SPRITE_TICKS),A
        AND 7
        RET NZ
        LD A,(SPRITE_FRAME)
        INC A
        CP 3
        JR C,.store
        XOR A
.store: LD (SPRITE_FRAME),A
        RET

; Benchmark three camera strides without changing the renderer:
; mode 0 = 8 pixels (phase 0 only), mode 1 = 4 pixels (phases 0 and 4),
; mode 2 = 1 pixel (all eight phases). Each is held for 64 complete presents.
; Scroll level 1 right then left. At its left edge start level 2, which then
; bounces continuously. Status bytes expose mode and stride to the capture tool.
ADVANCE_SCROLL:
        CALL UPDATE_CAMERA_MODE
        LD A,(DIRECTION)
        OR A
        JR Z,.left
.right:  LD HL,(POSITION)
        LD DE,(CAMERA_STEP)
        ADD HL,DE
        LD A,H
        CP 3
        JR C,.store_right
        JR NZ,.right_end
        LD A,L
        OR A
        JR Z,.store_right
.right_end:
        LD HL,0x0300
        XOR A
        LD (DIRECTION),A
.store_right:
        LD (POSITION),HL
        RET
.left:  LD HL,(POSITION)
        LD A,H
        OR L
        JR Z,.at_left
        LD DE,(CAMERA_STEP)
        OR A
        SBC HL,DE
        LD (POSITION),HL
        RET
.at_left:
        LD A,(LEVEL_INDEX)
        OR A
        JR NZ,.bounce_level2
        LD A,1
        LD (LEVEL_INDEX),A
        LD (LEVEL_BANK),A
        LD (STATUS_LEVEL),A
.bounce_level2:
        LD A,1
        LD (DIRECTION),A
        RET

UPDATE_CAMERA_MODE:
        LD A,(MODE_TICKS)
        INC A
        LD (MODE_TICKS),A
        CP 64
        JR C,.set_step
        XOR A
        LD (MODE_TICKS),A
        LD A,(CAMERA_MODE)
        INC A
        CP 3
        JR C,.store_mode
        XOR A
.store_mode:
        LD (CAMERA_MODE),A
        LD (STATUS_MODE),A
.set_step:
        LD A,(CAMERA_MODE)
        OR A
        JR NZ,.not_8
        LD HL,8
        JR .store_step
.not_8:
        DEC A
        JR NZ,.one_pixel
        LD HL,4
        JR .store_step
.one_pixel:
        LD HL,1
.store_step:
        LD (CAMERA_STEP),HL
        LD A,L
        LD (STATUS_STEP),A
        RET

POSITION:        DW 0
COARSE:          DW 0
PHASE:           DB 0
DIRECTION:       DB 0
LEVEL_INDEX:     DB 0
LEVEL_BANK:      DB 0
CAMERA_MODE:     DB 0
MODE_TICKS:      DB 0
CAMERA_STEP:     DW 8
SPRITE_FRAME:     DB 0
SPRITE_TICKS:     DB 0
DISPLAY_BIT:     DB 0
RENDER_TO_7:     DB 0
ROWS_LEFT:       DB 0
SCRATCH_ROW:     DEFS 32

STATUS_FRAMES:   EQU 0xBB04
STATUS_LEVEL:    EQU 0xBB06
STATUS_SCREEN:   EQU 0xBB07
STATUS_IRQ:      EQU 0xBB08
STATUS_MODE:     EQU 0xBB09
STATUS_STEP:     EQU 0xBB0A
LEVEL_HEIGHT     EQU 128

        INCLUDE "generated_rows.inc"

; Tables are inserted by the Python builder at 0xA800..0xB7FF.
        ASSERT $ < 0xA800
        DEFS 0xB800-$,0
        INCLUDE "generated_sprite.inc"
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

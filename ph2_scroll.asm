; Prehistorik 2-inspired stock ZX Spectrum 128K scrolling strip.
; The source is stored pre-shifted for all eight pixel phases.  The Z80 only
; selects the phase/coarse-byte offset and copies each 32-byte raster line.

        ORG 0x8000

START:
        DI
        LD SP,0xBFF0
        LD HL,0xBE00
        LD (HL),'P'
        INC HL
        LD (HL),'H'
        INC HL
        LD (HL),'2'
        INC HL
        LD (HL),'S'
        XOR A
        LD (STATUS_FRAMES),A
        LD (STATUS_FRAMES+1),A
        LD (STATUS_POSITION),A
        LD (STATUS_DIRECTION),A
        LD (STATUS_IRQ),A
        LD (STATUS_SCREEN),A
        LD (POSITION),A
        LD (DIRECTION),A
        LD (DISPLAY_BIT),A     ; bank 5 initially displayed
        LD A,1
        LD (RENDER_TO_7),A
        LD A,0xA0
        LD I,A
        IM 2
        EI

FRAME:
        CALL WAIT_IRQ           ; begin a refresh-aligned update
        CALL DRAW_LEVEL
        CALL ADVANCE_SCROLL
        LD A,(POSITION)
        LD (STATUS_POSITION),A
        LD A,(DIRECTION)
        LD (STATUS_DIRECTION),A
        LD HL,(STATUS_FRAMES)
        INC HL
        LD (STATUS_FRAMES),HL
        JP FRAME

WAIT_IRQ:
        LD A,(STATUS_IRQ)
.wait:
        HALT
        LD HL,STATUS_IRQ
        CP (HL)
        JR Z,.wait
        RET

; POSITION is 0..64 pixel positions.  Offset into one source row is
; (POSITION & 7) * 40 + (POSITION >> 3).  40 source bytes cover 320 pixels;
; a 32-byte, 256-pixel viewport is copied from that start.
DRAW_LEVEL:
        LD A,(POSITION)
        LD E,A
        AND 7
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL              ; phase * 8
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL              ; phase * 32
        ADD HL,DE              ; phase * 40
        LD A,(POSITION)
        SRL A
        SRL A
        SRL A
        LD E,A
        LD D,0
        ADD HL,DE
        LD (SOURCE_OFFSET),HL

        LD A,(RENDER_TO_7)
        OR A
        JP NZ,DRAW_TO_7

; Bank 7 is on screen while bank 5 is updated through its fixed 0x4000 map.
DRAW_TO_5:
        LD IX,ROW_TABLE
        LD A,LEVEL_HEIGHT
        LD (ROWS_LEFT),A
.row:
        LD A,(IX+0)
        LD B,A
        LD A,(DISPLAY_BIT)
        OR B
        CALL PAGE_VALUE        ; source at 0xC000, screen 7 remains visible
        LD L,(IX+1)
        LD H,(IX+2)
        LD DE,(SOURCE_OFFSET)
        ADD HL,DE
        LD E,(IX+3)
        LD D,(IX+4)
        LD BC,32
        LDIR
        CALL NEXT_ROW
        JR NZ,.row
        XOR A
        LD (DISPLAY_BIT),A
        LD (STATUS_SCREEN),A
        LD A,1
        LD (RENDER_TO_7),A
        XOR A
        JP PAGE_VALUE          ; show the complete bank-5 frame

; Bank 5 is on screen. Source and bank 7 both occupy 0xC000, so each 32-byte
; row is staged through fixed bank-2 RAM before being committed to bank 7.
; This is deliberately slower but eliminates visible partial line updates.
DRAW_TO_7:
        LD IX,ROW_TABLE
        LD A,LEVEL_HEIGHT
        LD (ROWS_LEFT),A
.row:
        LD A,(IX+0)
        LD B,A
        LD A,(DISPLAY_BIT)
        OR B
        CALL PAGE_VALUE        ; source bank at 0xC000, bank 5 still visible
        LD L,(IX+1)
        LD H,(IX+2)
        LD DE,(SOURCE_OFFSET)
        ADD HL,DE
        LD DE,SCRATCH_ROW
        LD BC,32
        LDIR
        LD A,7
        CALL PAGE_VALUE        ; target bank 7 at 0xC000, still not displayed
        LD HL,SCRATCH_ROW
        LD E,(IX+3)
        LD D,(IX+4)
        SET 7,D
        LD BC,32
        LDIR
        CALL NEXT_ROW
        JR NZ,.row
        LD A,8
        LD (DISPLAY_BIT),A
        XOR A
        LD (RENDER_TO_7),A
        LD A,1
        LD (STATUS_SCREEN),A
        LD A,15
        JP PAGE_VALUE          ; map and show the complete bank-7 frame

NEXT_ROW:
        INC IX
        INC IX
        INC IX
        INC IX
        INC IX
        LD A,(ROWS_LEFT)
        DEC A
        LD (ROWS_LEFT),A
        RET

PAGE_VALUE:
        LD C,0xFD
        LD B,0x7F
        OUT (C),A
        RET

ADVANCE_SCROLL:
        LD A,(DIRECTION)
        OR A
        JR Z,.left
.right:
        LD A,(POSITION)
        INC A
        CP 65
        JR NZ,.store_right
        LD A,64
        LD (POSITION),A
        XOR A
        LD (DIRECTION),A
        RET
.store_right:
        LD (POSITION),A
        RET
.left:
        LD A,(POSITION)
        OR A
        JR NZ,.store_left
        LD A,1
        LD (DIRECTION),A
        RET
.store_left:
        DEC A
        LD (POSITION),A
        RET

POSITION:      DB 0
DIRECTION:     DB 0
ROWS_LEFT:     DB 0
SOURCE_OFFSET: DW 0
DISPLAY_BIT:   DB 0
RENDER_TO_7:   DB 0
SCRATCH_ROW:   DEFS 32

STATUS_FRAMES:    EQU 0xBE04
STATUS_POSITION:  EQU 0xBE06
STATUS_DIRECTION: EQU 0xBE07
STATUS_IRQ:       EQU 0xBE08
STATUS_SCREEN:    EQU 0xBE09

LEVEL_HEIGHT EQU 136

        INCLUDE "generated_rows.inc"

        ASSERT $ < 0xA000

; A fully populated IM2 table means the bus-supplied low byte is irrelevant.
        DEFS 0xA000-$,0
IM2_VECTORS:
        DEFS 257,0xA1
        DEFS 0xA1A1-$,0
IM2_HANDLER:
        PUSH AF
        LD A,(STATUS_IRQ)
        INC A
        LD (STATUS_IRQ),A
        POP AF
        EI
        RETI

        ASSERT $ < 0xBE00

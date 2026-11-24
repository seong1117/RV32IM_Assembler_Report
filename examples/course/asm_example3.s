# 예제 3: 공 튀기기 (CPUlator RISC-V DE10-Lite, rv32-de10-lite) — RV32IM 어셈블리
#
#  - VGA 픽셀 버퍼(160x120, RGB565) 에 8x8 공이 벽에 튕기며 움직인다
#  - SW2-0 : 속도 (프레임당 이동 픽셀 수 = SW2-0 + 1)
#  - KEY0  : 공 색 바꾸기 (6가지 순환),  KEY1 : 튕긴 횟수 0 으로 리셋
#  - 더블 버퍼링: 뒷 버퍼(SDRAM 0x03F00000)에 그린 뒤 swap, Status.S 로 수직 동기 대기
#  - 문자 버퍼(80x60)에 튕긴 횟수와 속도를 표시한다
#  - 매 프레임 전체를 지우지 않고, 그 버퍼에 두 프레임 전 그려 둔 공만 지운다
#  - 0x00010000 에 적재되는 것을 전제로 링크한다. 주소 참조는 la(pc 상대)만 쓴다
#
#  주 프로그램의 s 레지스터 배치
#    s0 = 픽셀 버퍼 DMA 컨트롤러(0xFF203020)   s1 = x      s2 = y      s3 = dx(+1/-1)  s4 = dy
#    s5 = 뒷 버퍼 번호(0/1)  s6 = 튕긴 횟수  s7 = 색 번호  s8 = 속도  s9 = SW 포트  s10 = KEY 포트
#    PIXBUF(메모리) = 지금 그리는 뒷 버퍼의 시작 주소

.equ PIXEL_BUF_CTRL_BASE, 0xFF203020
.equ CHAR_BUF_BASE,       0x09000000
.equ SDRAM_BACKBUF,       0x03F00000
.equ SW_BASE,             0xFF200040
.equ KEY_BASE,            0xFF200050
.equ STACK_TOP,           0x04000000
.equ SCREEN_W,            160
.equ SCREEN_H,            120
.equ BALL,                8
.equ MAX_X,               152             # SCREEN_W - BALL
.equ MAX_Y,               112             # SCREEN_H - BALL

        .text
        .global _start
_start:
        li      sp, STACK_TOP
        li      s0, PIXEL_BUF_CTRL_BASE
        li      s9, SW_BASE
        li      s10, KEY_BASE
        li      s1, 40                  # x
        li      s2, 30                  # y
        li      s3, 1                   # dx
        li      s4, 1                   # dy
        li      s5, 0                   # buf
        li      s6, 0                   # bounces
        li      s7, 0                   # color_idx

        # 두 버퍼 모두 지우기 (SDRAM 초기값은 0 이 아니므로 반드시 지운다)
        li      t0, SDRAM_BACKBUF
        sw      t0, 4(s0)               # Backbuffer = SDRAM 영역
        lw      t0, 4(s0)
        la      t1, PIXBUF
        sw      t0, 0(t1)               # PIXBUF = 뒷 버퍼(SDRAM)
        jal     CLEAR_SCREEN
        jal     WAIT_VSYNC              # swap: 앞 = SDRAM, 뒤 = 0x08000000
        lw      t0, 4(s0)
        la      t1, PIXBUF
        sw      t0, 0(t1)               # PIXBUF = 0x08000000
        jal     CLEAR_SCREEN

        la      t0, OLDX                # 두 버퍼의 '옛 공' 위치 = 시작 위치
        sw      s1, 0(t0)
        sw      s1, 4(t0)
        la      t0, OLDY
        sw      s2, 0(t0)
        sw      s2, 4(t0)

        li      a0, 1
        li      a1, 1
        la      a2, STR_BOUNCE
        jal     WRITE_TEXT
        li      a0, 1
        li      a1, 2
        la      a2, STR_SPEED
        jal     WRITE_TEXT
        li      a0, 1
        li      a1, 3
        la      a2, STR_HELP
        jal     WRITE_TEXT
        li      t0, 0xF
        sw      t0, 12(s10)             # KEY 에지 지우기

MAIN_LOOP:
        # ---- 입력: 속도 = SW2-0 + 1, KEY 에지 처리 ----
        lw      s8, 0(s9)
        andi    s8, s8, 0x7
        addi    s8, s8, 1
        lw      t0, 12(s10)             # Edgecapture
        beqz    t0, MOVE
        sw      t0, 12(s10)             # 에지 지우기
        andi    t1, t0, 0x1
        beqz    t1, CHK_KEY1
        addi    s7, s7, 1               # KEY0: 다음 색
        li      t1, 6
        bltu    s7, t1, CHK_KEY1
        li      s7, 0
CHK_KEY1:
        andi    t1, t0, 0x2
        beqz    t1, MOVE
        li      s6, 0                   # KEY1: 튕긴 횟수 리셋

MOVE:   # ---- 공 이동과 벽 충돌 ----
        mul     t0, s3, s8
        add     s1, s1, t0              # x += dx * speed
        mul     t0, s4, s8
        add     s2, s2, t0              # y += dy * speed
        bgtz    s1, X_MAX               # x <= 0 ?
        li      s1, 0
        li      s3, 1
        addi    s6, s6, 1
X_MAX:  li      t0, MAX_X
        blt     s1, t0, Y_MIN           # x >= MAX_X ?
        mv      s1, t0
        li      s3, -1
        addi    s6, s6, 1
Y_MIN:  bgtz    s2, Y_MAX               # y <= 0 ?
        li      s2, 0
        li      s4, 1
        addi    s6, s6, 1
Y_MAX:  li      t0, MAX_Y
        blt     s2, t0, DRAW            # y >= MAX_Y ?
        mv      s2, t0
        li      s4, -1
        addi    s6, s6, 1

DRAW:   # ---- 뒷 버퍼: 이 버퍼의 옛 공을 지우고 새 공을 그린다 ----
        slli    t0, s5, 2               # buf * 4
        la      t1, OLDX
        add     t1, t1, t0
        lw      a0, 0(t1)
        la      t2, OLDY
        add     t2, t2, t0
        lw      a1, 0(t2)
        li      a2, 0                   # 검정
        jal     DRAW_BOX
        mv      a0, s1
        mv      a1, s2
        la      t0, COLORS
        slli    t1, s7, 1
        add     t0, t0, t1
        lhu     a2, 0(t0)               # colors[color_idx]
        jal     DRAW_BOX
        slli    t0, s5, 2
        la      t1, OLDX
        add     t1, t1, t0
        sw      s1, 0(t1)               # old_x[buf] = x
        la      t1, OLDY
        add     t1, t1, t0
        sw      s2, 0(t1)               # old_y[buf] = y

        li      a0, 9                   # 튕긴 횟수 (4자리)
        li      a1, 1
        mv      a2, s6
        li      a3, 4
        jal     WRITE_DEC
        li      a0, 9                   # 속도 (1자리)
        li      a1, 2
        mv      a2, s8
        li      a3, 1
        jal     WRITE_DEC

        jal     WAIT_VSYNC              # swap + 수직 동기 대기
        lw      t0, 4(s0)
        la      t1, PIXBUF
        sw      t0, 0(t1)               # 새 뒷 버퍼
        xori    s5, s5, 1
        j       MAIN_LOOP

# ---------------------------------------------------------------------------
# DRAW_BOX: (a0, a1) 에 BALL x BALL 사각형을 a2 색으로. 픽셀 주소 = PIXBUF + (y << 9) + (x << 1)
# ---------------------------------------------------------------------------
DRAW_BOX:
        la      t0, PIXBUF
        lw      t0, 0(t0)
        slli    t1, a1, 9
        add     t0, t0, t1
        slli    t1, a0, 1
        add     t0, t0, t1              # t0 = 왼쪽 위 픽셀 주소
        li      t2, BALL                # 남은 행 수
DB_ROW:
        li      t3, BALL                # 남은 열 수
        mv      t4, t0
DB_COL:
        sh      a2, 0(t4)
        addi    t4, t4, 2
        addi    t3, t3, -1
        bnez    t3, DB_COL
        addi    t0, t0, 512             # 다음 행 (stride 512 바이트)
        addi    t2, t2, -1
        bnez    t2, DB_ROW
        ret

# ---------------------------------------------------------------------------
# CLEAR_SCREEN: 현재 PIXBUF 의 120행 x 512바이트 를 0 으로 (워드 단위)
# ---------------------------------------------------------------------------
CLEAR_SCREEN:
        la      t0, PIXBUF
        lw      t0, 0(t0)
        li      t1, SCREEN_H * 512 / 4  # 워드 수
CS_LOOP:
        sw      zero, 0(t0)
        addi    t0, t0, 4
        addi    t1, t1, -1
        bnez    t1, CS_LOOP
        ret

# ---------------------------------------------------------------------------
# WRITE_TEXT: 문자 버퍼 (a0, a1) 부터 a2 의 문자열. 주소 = 0x09000000 + (y << 7) + x
# ---------------------------------------------------------------------------
WRITE_TEXT:
        li      t0, CHAR_BUF_BASE
        slli    t1, a1, 7
        add     t0, t0, t1
        add     t0, t0, a0
WT_LOOP:
        lbu     t1, 0(a2)
        beqz    t1, WT_DONE
        sb      t1, 0(t0)
        addi    t0, t0, 1
        addi    a2, a2, 1
        j       WT_LOOP
WT_DONE:
        ret

# ---------------------------------------------------------------------------
# WRITE_DEC: 문자 버퍼 (a0, a1) 에 a2 를 a3 자리 10진수로 (앞자리는 0 으로 채움)
# ---------------------------------------------------------------------------
WRITE_DEC:
        li      t0, CHAR_BUF_BASE
        slli    t1, a1, 7
        add     t0, t0, t1
        add     t0, t0, a0
        add     t0, t0, a3
        addi    t0, t0, -1              # 마지막 자리부터 거꾸로
        li      t3, 10
WD_LOOP:
        remu    t1, a2, t3
        addi    t1, t1, '0'
        sb      t1, 0(t0)
        divu    a2, a2, t3
        addi    t0, t0, -1
        addi    a3, a3, -1
        bnez    a3, WD_LOOP
        ret

# ---------------------------------------------------------------------------
# WAIT_VSYNC: Buffer 레지스터에 1 (swap 요청) -> Status.S 가 0 이 될 때까지 대기
# ---------------------------------------------------------------------------
WAIT_VSYNC:
        li      t0, PIXEL_BUF_CTRL_BASE
        li      t1, 1
        sw      t1, 0(t0)
WV_LOOP:
        lw      t1, 12(t0)
        andi    t1, t1, 1
        bnez    t1, WV_LOOP
        ret

# ---------------------------------------------------------------------------
        .data
        .align 2
PIXBUF:     .word 0                     # 지금 그리는 뒷 버퍼 시작 주소
OLDX:       .word 40, 40                # 버퍼 0, 1 에 마지막으로 그린 공의 x
OLDY:       .word 30, 30
COLORS:     .half 0xF800, 0x07E0, 0x001F, 0xFFE0, 0xF81F, 0xFFFF
STR_BOUNCE: .asciz "BOUNCE:"
STR_SPEED:  .asciz "SPEED :"
STR_HELP:   .asciz "KEY0 color  KEY1 reset  SW2-0 speed"
        .align 2

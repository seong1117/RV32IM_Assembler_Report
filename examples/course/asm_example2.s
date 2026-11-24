# 예제 2: 반응 속도 측정기 (CPUlator RISC-V DE10-Lite, rv32-de10-lite) — RV32IM 어셈블리
#
#  1. KEY0 을 눌렀다 떼면 측정이 시작된다 (터미널에 안내 출력)
#  2. 임의의 시간(1 ~ 4 초, mtime 하위 비트로 난수) 뒤에 LEDR9 가 켜진다
#  3. LEDR9 가 켜진 뒤 KEY0 을 눌렀다 떼기까지의 시간을 ms 단위로 HEX3-0 과 JTAG UART 에 출력한다
#  4. LEDR9 가 켜지기 전에 KEY0 을 누르면 HEX 에 "FAIL" 을 표시하고 처음으로 돌아간다
#
#  - 시간은 mtime(0xFF202100, 50 MHz) 하위 32비트로 재고, 차이를 부호 없이 계산한다
#  - KEY 는 Edgecapture 폴링 (CPUlator 는 버튼을 '뗄 때' 에지가 잡힌다). 인터럽트는 쓰지 않는다
#  - 0x00010000 에 적재되는 것을 전제로 링크한다. 주소 참조는 la(pc 상대)만 쓴다
#
#  레지스터 사용 규칙
#    PUT_JTAG      : t0, t1 만 사용 (다른 서브루틴이 t2~t6 을 보존한 채 호출할 수 있게)
#    그 밖의 서브루틴: t 레지스터 자유 사용, s 레지스터는 쓰지 않음
#    주 프로그램     : s0 = 시작 시각, s1 = 지연 틱 수

.equ LEDR_BASE,      0xFF200000
.equ HEX3_HEX0_BASE, 0xFF200020
.equ HEX5_HEX4_BASE, 0xFF200030
.equ KEY_BASE,       0xFF200050
.equ JTAG_UART_BASE, 0xFF201000
.equ MTIME_BASE,     0xFF202100
.equ STACK_TOP,      0x04000000
.equ TICKS_PER_MS,   50000
.equ LEDR9,          0x200
.equ SEG_DASH4,      0x40404040        # "----"
.equ SEG_FAIL,       0x71770638        # "FAIL" : F=71 A=77 I=06 L=38

        .text
        .global _start
_start:
        li      sp, STACK_TOP
        li      t0, HEX5_HEX4_BASE
        sw      zero, 0(t0)             # HEX5-4 끄기
        li      t0, HEX3_HEX0_BASE
        li      t1, SEG_DASH4
        sw      t1, 0(t0)               # HEX3-0 = "----"
        la      a0, STR_BANNER
        jal     PUT_STR

ROUND:
        li      t0, LEDR_BASE
        sw      zero, 0(t0)             # LED 끄기
        li      t0, KEY_BASE
        li      t1, 0xF
        sw      t1, 12(t0)              # 남아 있는 에지 모두 지우기
        la      a0, STR_PRESS
        jal     PUT_STR
WAIT_START:
        jal     KEY0_RELEASED           # KEY0 을 눌렀다 뗄 때까지 대기
        beqz    a0, WAIT_START

        # 임의 지연 = 1000 + (mtime % 3000) ms  ->  틱 수 = ms x 50000
        li      t0, MTIME_BASE
        lw      t1, 0(t0)               # mtime 하위 32비트 (난수 역할)
        li      t2, 3000
        remu    t1, t1, t2
        addi    t1, t1, 1000            # 1000 ~ 3999 ms
        li      t2, TICKS_PER_MS
        mul     s1, t1, t2              # s1 = 지연 틱 수
        lw      s0, 0(t0)               # s0 = 시작 시각
        li      t0, HEX3_HEX0_BASE
        sw      zero, 0(t0)             # HEX 끄기 (준비 중)
        la      a0, STR_WAIT
        jal     PUT_STR
WAIT_DELAY:
        li      t0, MTIME_BASE
        lw      t1, 0(t0)
        sub     t1, t1, s0              # 경과 틱 (부호 없음, 넘어가도 정확)
        bgeu    t1, s1, LED_ON          # 지연 시간이 지났으면 LED 켜기
        jal     KEY0_RELEASED
        bnez    a0, FAIL                # 너무 일찍 눌렀다
        j       WAIT_DELAY

LED_ON:
        li      t0, LEDR_BASE
        li      t1, LEDR9
        sw      t1, 0(t0)               # LEDR9 켜기
        li      t0, MTIME_BASE
        lw      s0, 0(t0)               # 측정 시작 시각
WAIT_REACT:
        jal     KEY0_RELEASED
        beqz    a0, WAIT_REACT
        li      t0, MTIME_BASE
        lw      t1, 0(t0)
        sub     t1, t1, s0              # 경과 틱
        li      t2, TICKS_PER_MS
        divu    s0, t1, t2              # s0 = 경과 ms
        li      t0, LEDR_BASE
        sw      zero, 0(t0)             # LED 끄기

        mv      a0, s0
        jal     HEX_SHOW_DEC            # HEX3-0 에 ms 표시
        la      a0, STR_RESULT
        jal     PUT_STR
        mv      a0, s0
        jal     PUT_DEC
        la      a0, STR_MS
        jal     PUT_STR
        j       ROUND

FAIL:
        li      t0, HEX3_HEX0_BASE
        li      t1, SEG_FAIL
        sw      t1, 0(t0)               # "FAIL"
        la      a0, STR_FAIL
        jal     PUT_STR
        j       ROUND

# ---------------------------------------------------------------------------
# KEY0_RELEASED: KEY0 의 Edgecapture 비트가 1 이면 지우고 a0 = 1, 아니면 a0 = 0
# ---------------------------------------------------------------------------
KEY0_RELEASED:
        li      t0, KEY_BASE
        lw      t1, 12(t0)              # Edgecapture
        andi    a0, t1, 1
        beqz    a0, KR_DONE
        li      t1, 1
        sw      t1, 12(t0)              # 비트 0 만 지운다
KR_DONE:
        ret

# ---------------------------------------------------------------------------
# HEX_SHOW_DEC: a0 = 0 ~ 9999 를 HEX3-0 에 10진수 4자리로 표시
# ---------------------------------------------------------------------------
HEX_SHOW_DEC:
        li      t0, 9999
        bleu    a0, t0, HSD_OK
        mv      a0, t0                  # 9999 로 제한
HSD_OK:
        la      t5, SEG7
        li      t1, 10
        remu    t2, a0, t1              # 일의 자리
        divu    a0, a0, t1
        add     t2, t2, t5
        lbu     t6, 0(t2)               # 결과 워드 (HEX0)
        remu    t2, a0, t1              # 십의 자리
        divu    a0, a0, t1
        add     t2, t2, t5
        lbu     t2, 0(t2)
        slli    t2, t2, 8
        or      t6, t6, t2
        remu    t2, a0, t1              # 백의 자리
        divu    a0, a0, t1
        add     t2, t2, t5
        lbu     t2, 0(t2)
        slli    t2, t2, 16
        or      t6, t6, t2
        add     t2, a0, t5              # 천의 자리 (a0 < 10)
        lbu     t2, 0(t2)
        slli    t2, t2, 24
        or      t6, t6, t2
        li      t0, HEX3_HEX0_BASE
        sw      t6, 0(t0)
        ret

# ---------------------------------------------------------------------------
# PUT_JTAG: a0 의 문자를 보낸다. 보낼 공간(WSPACE)이 생길 때까지 기다린다. t0, t1 만 사용
# ---------------------------------------------------------------------------
PUT_JTAG:
        li      t0, JTAG_UART_BASE
PJ_WAIT:
        lw      t1, 4(t0)               # control 레지스터
        srli    t1, t1, 16              # WSPACE
        beqz    t1, PJ_WAIT
        sw      a0, 0(t0)
        ret

# ---------------------------------------------------------------------------
# PUT_STR: a0 = 0 으로 끝나는 문자열의 주소
# ---------------------------------------------------------------------------
PUT_STR:
        addi    sp, sp, -8
        sw      ra, 4(sp)
        mv      t2, a0                  # t2 = 문자열 포인터 (PUT_JTAG 이 보존)
PS_LOOP:
        lbu     a0, 0(t2)
        beqz    a0, PS_DONE
        jal     PUT_JTAG
        addi    t2, t2, 1
        j       PS_LOOP
PS_DONE:
        lw      ra, 4(sp)
        addi    sp, sp, 8
        ret

# ---------------------------------------------------------------------------
# PUT_DEC: a0 = 부호 없는 정수를 10진수로 출력 (스택의 12바이트 버퍼에 거꾸로 만든 뒤 출력)
# ---------------------------------------------------------------------------
PUT_DEC:
        addi    sp, sp, -32
        sw      ra, 28(sp)
        mv      t3, a0                  # 남은 값
        li      t4, 0                   # 자릿수
        li      t5, 10
PD_CONV:
        remu    t6, t3, t5
        addi    t6, t6, '0'
        add     t2, sp, t4
        sb      t6, 0(t2)               # buf[t4] = 숫자 문자
        addi    t4, t4, 1
        divu    t3, t3, t5
        bnez    t3, PD_CONV
PD_OUT:
        addi    t4, t4, -1
        add     t2, sp, t4
        lbu     a0, 0(t2)
        jal     PUT_JTAG                # t2~t6 보존됨
        bnez    t4, PD_OUT
        lw      ra, 28(sp)
        addi    sp, sp, 32
        ret

# ---------------------------------------------------------------------------
        .data
SEG7:       .byte 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F
STR_BANNER: .asciz "\n=== Reaction time tester ===\n"
STR_PRESS:  .asciz "Press KEY0 to start.\n"
STR_WAIT:   .asciz "Wait for LEDR9...\n"
STR_RESULT: .asciz "Reaction time: "
STR_MS:     .asciz " ms\n"
STR_FAIL:   .asciz "FAIL: too early!\n"
        .align 2

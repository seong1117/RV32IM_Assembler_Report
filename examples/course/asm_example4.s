# 예제 4: 간단한 명령 해석기 (CPUlator RISC-V DE10-Lite, rv32-de10-lite) — RV32IM 어셈블리
#
#  JTAG UART 터미널에서 한 줄 명령을 받아 처리한다 (터미널 창을 클릭한 뒤 입력, Enter 로 실행)
#  명령어는 대문자 다섯 개다 (소문자로 쳐도 받아 주지만 기준은 대문자)
#    HELP            : 명령 목록
#    LED <value>     : LEDR8-0 에 값 표시 (10진수 또는 0x 로 시작하는 16진수)  예) LED 0x155
#    HEX <digits>    : 입력한 16진수 숫자(최대 6자리)를 HEX5-0 에 그대로 표시      예) HEX 1234
#    SW              : 현재 SW9-0 값을 16진수와 10진수로 출력
#    TIMER <ms>      : <ms> 밀리초마다 LEDR9 를 토글 (인터벌 타이머 인터럽트), 0 이면 정지
#
#  - 수신은 폴링(RVALID), 타이머는 인터럽트(IRQ 16). 글자 에코와 백스페이스(0x08, 0x7F) 지원
#  - 0x00010000 에 적재되는 것을 전제로 링크한다. 주소 참조는 la(pc 상대)만 쓴다
#
#  호출 규약: 인수 a0~a3, 반환 a0(a1). t 레지스터는 자유 사용(PUT_JTAG 만 t0, t1 로 제한),
#            s 레지스터를 쓰는 서브루틴은 스택에 저장/복원한다

.equ LEDR_BASE,      0xFF200000
.equ HEX3_HEX0_BASE, 0xFF200020
.equ HEX5_HEX4_BASE, 0xFF200030
.equ SW_BASE,        0xFF200040
.equ JTAG_UART_BASE, 0xFF201000
.equ TIMER_BASE,     0xFF202000
.equ STACK_TOP,      0x04000000
.equ IRQ_TIMER,      16
.equ TICKS_PER_MS,   50000
.equ LINE_MAX,       64

        .text
        .global _start
_start:
        li      sp, STACK_TOP
        la      t0, HANDLER
        csrw    mtvec, t0
        li      t0, 1 << IRQ_TIMER
        csrs    mie, t0
        csrsi   mstatus, 0x8

        li      t0, HEX3_HEX0_BASE
        sw      zero, 0(t0)
        li      t0, HEX5_HEX4_BASE
        sw      zero, 0(t0)
        jal     UPDATE_LEDS
        la      a0, STR_BANNER
        jal     PUT_STR
MAIN_LOOP:
        la      a0, STR_PROMPT
        jal     PUT_STR
        la      a0, LINE
        li      a1, LINE_MAX
        jal     READ_LINE
        la      a0, LINE
        jal     EXECUTE
        j       MAIN_LOOP

# ---------------------------------------------------------------------------
# 트랩 핸들러: 인터벌 타이머(IRQ 16) 만 처리. TO 해제 -> LED9 토글 -> UPDATE_LEDS
# ---------------------------------------------------------------------------
        .align 2
HANDLER:
        addi    sp, sp, -16
        sw      ra, 12(sp)
        sw      t0, 8(sp)
        sw      t1, 4(sp)
        sw      t2, 0(sp)
        csrr    t0, mcause
        li      t1, 0x80000000 | IRQ_TIMER
        bne     t0, t1, UNEXPECTED
        li      t0, TIMER_BASE
        sw      zero, 0(t0)             # TO 지우기
        la      t0, LED9
        lw      t1, 0(t0)
        xori    t1, t1, 1
        sw      t1, 0(t0)
        jal     UPDATE_LEDS
        lw      t2, 0(sp)
        lw      t1, 4(sp)
        lw      t0, 8(sp)
        lw      ra, 12(sp)
        addi    sp, sp, 16
        mret
UNEXPECTED:
        j       UNEXPECTED

# ---------------------------------------------------------------------------
# EXECUTE: a0 = 명령 줄. 첫 단어를 명령어로, 나머지를 인수로 나눈다
#   s0 = 명령어 포인터, s1 = 인수 포인터, s2 = 값
# ---------------------------------------------------------------------------
EXECUTE:
        addi    sp, sp, -16
        sw      ra, 12(sp)
        sw      s0, 8(sp)
        sw      s1, 4(sp)
        sw      s2, 0(sp)
        jal     SKIP_SPACES
        mv      s0, a0                  # cmd
        mv      s1, a0                  # arg 탐색
EX_FIND_END:
        lbu     t0, 0(s1)
        beqz    t0, EX_NO_ARG
        li      t1, ' '
        beq     t0, t1, EX_SPLIT
        addi    s1, s1, 1
        j       EX_FIND_END
EX_SPLIT:
        sb      zero, 0(s1)             # 명령어 끝에 0
        addi    s1, s1, 1
        mv      a0, s1
        jal     SKIP_SPACES
        mv      s1, a0                  # arg
EX_NO_ARG:
        lbu     t0, 0(s0)
        beqz    t0, EX_DONE             # 빈 줄

        mv      a0, s0
        la      a1, CMDS_HELP
        jal     STR_EQ
        bnez    a0, EX_HELP
        mv      a0, s0
        la      a1, CMDS_LED
        jal     STR_EQ
        bnez    a0, EX_LED
        mv      a0, s0
        la      a1, CMDS_HEX
        jal     STR_EQ
        bnez    a0, EX_HEX
        mv      a0, s0
        la      a1, CMDS_SW
        jal     STR_EQ
        bnez    a0, EX_SW
        mv      a0, s0
        la      a1, CMDS_TIMER
        jal     STR_EQ
        bnez    a0, EX_TIMER
        la      a0, STR_UNKNOWN1        # 모르는 명령
        jal     PUT_STR
        mv      a0, s0
        jal     PUT_STR
        la      a0, STR_UNKNOWN2
        jal     PUT_STR
        j       EX_DONE

EX_HELP:
        la      a0, STR_HELP
        jal     PUT_STR
        j       EX_DONE

EX_LED:
        mv      a0, s1
        jal     PARSE_NUMBER            # a0 = 성공, a1 = 값
        beqz    a0, EX_LED_USAGE
        andi    s2, a1, 0x1FF
        la      t0, LED_VALUE
        sw      s2, 0(t0)
        jal     UPDATE_LEDS
        la      a0, STR_LED_RES
        jal     PUT_STR
        mv      a0, s2
        jal     PUT_HEX
        la      a0, STR_NL
        jal     PUT_STR
        j       EX_DONE
EX_LED_USAGE:
        la      a0, STR_LED_USAGE
        jal     PUT_STR
        j       EX_DONE

EX_HEX:
        mv      a0, s1
        jal     CMD_HEX_DISPLAY
        j       EX_DONE

EX_SW:
        li      t0, SW_BASE
        lw      s2, 0(t0)
        andi    s2, s2, 0x3FF
        la      a0, STR_SW_RES
        jal     PUT_STR
        mv      a0, s2
        jal     PUT_HEX
        la      a0, STR_PAREN
        jal     PUT_STR
        mv      a0, s2
        jal     PUT_DEC
        la      a0, STR_CPAREN
        jal     PUT_STR
        j       EX_DONE

EX_TIMER:
        mv      a0, s1
        jal     PARSE_NUMBER
        beqz    a0, EX_TIMER_USAGE
        li      t0, 60000
        bgtu    a1, t0, EX_TIMER_USAGE
        mv      a0, a1
        jal     CMD_TIMER
        j       EX_DONE
EX_TIMER_USAGE:
        la      a0, STR_TIMER_USAGE
        jal     PUT_STR
EX_DONE:
        lw      s2, 0(sp)
        lw      s1, 4(sp)
        lw      s0, 8(sp)
        lw      ra, 12(sp)
        addi    sp, sp, 16
        ret

# ---------------------------------------------------------------------------
# CMD_HEX_DISPLAY: a0 = 16진수 문자열. 1~6 자리를 HEX5-0 에 오른쪽 정렬로 표시
#   s0 = 문자열, s1 = 자릿수 n, s2 = i, 스택 0(sp)~7(sp) = seg[0..5]
# ---------------------------------------------------------------------------
CMD_HEX_DISPLAY:
        addi    sp, sp, -32
        sw      ra, 28(sp)
        sw      s0, 24(sp)
        sw      s1, 20(sp)
        sw      s2, 16(sp)
        sw      zero, 0(sp)             # seg[0..3] = 0
        sw      zero, 4(sp)             # seg[4..5] = 0
        mv      s0, a0
        li      s1, 0
CH_COUNT:                               # 16진수 자릿수 세기
        add     t0, s0, s1
        lbu     a0, 0(t0)
        jal     HEX_DIGIT
        bltz    a0, CH_COUNTED
        addi    s1, s1, 1
        j       CH_COUNT
CH_COUNTED:
        beqz    s1, CH_USAGE
        li      t0, 6
        bgtu    s1, t0, CH_USAGE
        li      s2, 0
CH_FILL:                                # seg[i] = SEG7[digit(n-1-i)]
        sub     t0, s1, s2
        addi    t0, t0, -1
        add     t0, s0, t0
        lbu     a0, 0(t0)
        jal     HEX_DIGIT
        la      t0, SEG7
        add     t0, t0, a0
        lbu     t1, 0(t0)
        add     t0, sp, s2
        sb      t1, 0(t0)
        addi    s2, s2, 1
        bltu    s2, s1, CH_FILL
        lw      t0, 0(sp)               # seg[3]<<24 | seg[2]<<16 | seg[1]<<8 | seg[0]  (리틀 엔디언)
        li      t1, HEX3_HEX0_BASE
        sw      t0, 0(t1)
        lhu     t0, 4(sp)               # seg[5]<<8 | seg[4]
        li      t1, HEX5_HEX4_BASE
        sw      t0, 0(t1)
        j       CH_DONE
CH_USAGE:
        la      a0, STR_HEX_USAGE
        jal     PUT_STR
CH_DONE:
        lw      s2, 16(sp)
        lw      s1, 20(sp)
        lw      s0, 24(sp)
        lw      ra, 28(sp)
        addi    sp, sp, 32
        ret

# ---------------------------------------------------------------------------
# CMD_TIMER: a0 = ms. 0 이면 정지, 아니면 ms 주기로 인터럽트 (ITO)
# ---------------------------------------------------------------------------
CMD_TIMER:
        addi    sp, sp, -16
        sw      ra, 12(sp)
        sw      s0, 8(sp)
        mv      s0, a0
        li      t0, TIMER_BASE
        li      t1, 0x8
        sw      t1, 4(t0)               # STOP
        sw      zero, 0(t0)             # TO 지우기
        bnez    s0, CT_START
        la      a0, STR_TIMER_STOP
        jal     PUT_STR
        j       CT_DONE
CT_START:
        li      t1, TICKS_PER_MS
        mul     t1, s0, t1
        addi    t1, t1, -1              # 틱 수 - 1
        sw      t1, 8(t0)               # Periodl
        srli    t1, t1, 16
        sw      t1, 12(t0)              # Periodh
        li      t1, 0x7                 # START | CONT | ITO
        sw      t1, 4(t0)
        la      a0, STR_TIMER_RES1
        jal     PUT_STR
        mv      a0, s0
        jal     PUT_DEC
        la      a0, STR_TIMER_RES2
        jal     PUT_STR
CT_DONE:
        lw      s0, 8(sp)
        lw      ra, 12(sp)
        addi    sp, sp, 16
        ret

# ---------------------------------------------------------------------------
# UPDATE_LEDS: LEDR = LED9 << 9 | (LED_VALUE & 0x1FF).  t0~t2 사용
# ---------------------------------------------------------------------------
UPDATE_LEDS:
        la      t0, LED9
        lw      t1, 0(t0)
        slli    t1, t1, 9
        la      t0, LED_VALUE
        lw      t2, 0(t0)
        andi    t2, t2, 0x1FF
        or      t1, t1, t2
        li      t0, LEDR_BASE
        sw      t1, 0(t0)
        ret

# ---------------------------------------------------------------------------
# READ_LINE: a0 = 버퍼, a1 = 최대 길이. Enter 까지 읽어 0 으로 끝낸다 (에코, 백스페이스)
#   s0 = 버퍼, s1 = 최대 길이 - 1, s2 = 현재 길이 n
# ---------------------------------------------------------------------------
READ_LINE:
        addi    sp, sp, -16
        sw      ra, 12(sp)
        sw      s0, 8(sp)
        sw      s1, 4(sp)
        sw      s2, 0(sp)
        mv      s0, a0
        addi    s1, a1, -1
        li      s2, 0
RL_LOOP:
        jal     GET_JTAG
        bltz    a0, RL_LOOP             # 문자가 올 때까지 대기
        li      t0, '\r'
        beq     a0, t0, RL_ENTER
        li      t0, '\n'
        beq     a0, t0, RL_ENTER
        li      t0, 0x08
        beq     a0, t0, RL_BS
        li      t0, 0x7F
        beq     a0, t0, RL_BS
        li      t0, 0x20
        bltu    a0, t0, RL_LOOP         # 제어 문자 무시
        li      t0, 0x7F
        bgeu    a0, t0, RL_LOOP
        bgeu    s2, s1, RL_LOOP         # 버퍼가 가득 참
        add     t0, s0, s2
        sb      a0, 0(t0)               # 저장
        addi    s2, s2, 1
        jal     PUT_JTAG                # 에코
        j       RL_LOOP
RL_BS:
        beqz    s2, RL_LOOP
        addi    s2, s2, -1
        la      a0, STR_BS              # "\b \b"
        jal     PUT_STR
        j       RL_LOOP
RL_ENTER:
        la      a0, STR_NL
        jal     PUT_STR
        add     t0, s0, s2
        sb      zero, 0(t0)             # 문자열 끝
        lw      s2, 0(sp)
        lw      s1, 4(sp)
        lw      s0, 8(sp)
        lw      ra, 12(sp)
        addi    sp, sp, 16
        ret

# ---------------------------------------------------------------------------
# STR_EQ: a0(입력), a1(대문자 명령어) 문자열이 같으면 a0 = 1, 아니면 0. 입력 쪽 소문자는 대문자로 바꿔 비교
# ---------------------------------------------------------------------------
STR_EQ:
        lbu     t0, 0(a0)
        lbu     t1, 0(a1)
        li      t2, 'a'
        bltu    t0, t2, SE_CMP
        li      t2, 'z'
        bgtu    t0, t2, SE_CMP
        addi    t0, t0, -32             # 'a'~'z' -> 'A'~'Z'
SE_CMP:
        bne     t0, t1, SE_NO
        beqz    t0, SE_YES
        addi    a0, a0, 1
        addi    a1, a1, 1
        j       STR_EQ
SE_YES: li      a0, 1
        ret
SE_NO:  li      a0, 0
        ret

# SKIP_SPACES: a0 가 가리키는 공백을 건너뛴 주소를 a0 로
SKIP_SPACES:
        lbu     t0, 0(a0)
        li      t1, ' '
        bne     t0, t1, SS_DONE
        addi    a0, a0, 1
        j       SKIP_SPACES
SS_DONE:
        ret

# HEX_DIGIT: a0 = 문자 -> a0 = 0~15, 16진수 숫자가 아니면 -1
HEX_DIGIT:
        li      t0, '0'
        bltu    a0, t0, HD_NO
        li      t0, '9'
        bgtu    a0, t0, HD_AF
        addi    a0, a0, -'0'
        ret
HD_AF:  ori     a0, a0, 0x20            # 소문자로
        li      t0, 'a'
        bltu    a0, t0, HD_NO
        li      t0, 'f'
        bgtu    a0, t0, HD_NO
        addi    a0, a0, -'a' + 10
        ret
HD_NO:  li      a0, -1
        ret

# ---------------------------------------------------------------------------
# PARSE_NUMBER: a0 = 문자열 -> a0 = 성공(1/0), a1 = 값. 10진수 또는 0x16진수. 뒤에는 끝(0) 또는 공백만 허용
#   s0 = 포인터, s1 = 값, s2 = 숫자가 하나라도 있었는가
# ---------------------------------------------------------------------------
PARSE_NUMBER:
        addi    sp, sp, -16
        sw      ra, 12(sp)
        sw      s0, 8(sp)
        sw      s1, 4(sp)
        sw      s2, 0(sp)
        mv      s0, a0
        li      s1, 0
        li      s2, 0
        lbu     t0, 0(s0)
        li      t1, '0'
        bne     t0, t1, PN_DEC
        lbu     t0, 1(s0)
        ori     t0, t0, 0x20
        li      t1, 'x'
        bne     t0, t1, PN_DEC
        addi    s0, s0, 2               # "0x" 건너뜀
PN_HEX:
        lbu     a0, 0(s0)
        jal     HEX_DIGIT
        bltz    a0, PN_END
        slli    s1, s1, 4
        add     s1, s1, a0
        li      s2, 1
        addi    s0, s0, 1
        j       PN_HEX
PN_DEC:
        lbu     t0, 0(s0)
        li      t1, '0'
        bltu    t0, t1, PN_END
        li      t1, '9'
        bgtu    t0, t1, PN_END
        addi    t0, t0, -'0'
        li      t1, 10
        mul     s1, s1, t1
        add     s1, s1, t0
        li      s2, 1
        addi    s0, s0, 1
        j       PN_DEC
PN_END:
        mv      a1, s1
        li      a0, 0
        beqz    s2, PN_RET              # 숫자가 없었다
        lbu     t0, 0(s0)
        beqz    t0, PN_OK
        li      t1, ' '
        bne     t0, t1, PN_RET          # 숫자 뒤에 이상한 문자
PN_OK:  li      a0, 1
PN_RET:
        lw      s2, 0(sp)
        lw      s1, 4(sp)
        lw      s0, 8(sp)
        lw      ra, 12(sp)
        addi    sp, sp, 16
        ret

# ---------------------------------------------------------------------------
# JTAG UART 입출력
# ---------------------------------------------------------------------------
PUT_JTAG:                               # a0 = 문자. t0, t1 만 사용
        li      t0, JTAG_UART_BASE
PJ_WAIT:
        lw      t1, 4(t0)
        srli    t1, t1, 16              # WSPACE
        beqz    t1, PJ_WAIT
        sw      a0, 0(t0)
        ret

GET_JTAG:                               # a0 = 수신 문자, 없으면 -1
        li      t0, JTAG_UART_BASE
        lw      t1, 0(t0)
        li      t0, 0x8000
        and     t0, t1, t0              # RVALID
        beqz    t0, GJ_NONE
        andi    a0, t1, 0xFF
        ret
GJ_NONE:
        li      a0, -1
        ret

PUT_STR:                                # a0 = 문자열
        addi    sp, sp, -8
        sw      ra, 4(sp)
        mv      t2, a0
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

PUT_DEC:                                # a0 = 부호 없는 정수 -> 10진수 출력
        addi    sp, sp, -32
        sw      ra, 28(sp)
        mv      t3, a0
        li      t4, 0
        li      t5, 10
PD_CONV:
        remu    t6, t3, t5
        addi    t6, t6, '0'
        add     t2, sp, t4
        sb      t6, 0(t2)
        addi    t4, t4, 1
        divu    t3, t3, t5
        bnez    t3, PD_CONV
PD_OUT:
        addi    t4, t4, -1
        add     t2, sp, t4
        lbu     a0, 0(t2)
        jal     PUT_JTAG
        bnez    t4, PD_OUT
        lw      ra, 28(sp)
        addi    sp, sp, 32
        ret

PUT_HEX:                                # a0 -> "0x" + 16진수 (최소 1자리)
        addi    sp, sp, -32
        sw      ra, 28(sp)
        mv      t3, a0
        li      t4, 0
        la      t5, HEXCHARS
PH_CONV:
        andi    t6, t3, 0xF
        add     t6, t5, t6
        lbu     t6, 0(t6)
        add     t2, sp, t4
        sb      t6, 0(t2)
        addi    t4, t4, 1
        srli    t3, t3, 4
        bnez    t3, PH_CONV
        li      a0, '0'
        jal     PUT_JTAG
        li      a0, 'x'
        jal     PUT_JTAG
PH_OUT:
        addi    t4, t4, -1
        add     t2, sp, t4
        lbu     a0, 0(t2)
        jal     PUT_JTAG
        bnez    t4, PH_OUT
        lw      ra, 28(sp)
        addi    sp, sp, 32
        ret

# ---------------------------------------------------------------------------
        .data
        .align 2
LED_VALUE:  .word 0
LED9:       .word 0
LINE:       .space LINE_MAX
SEG7:       .byte 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71
HEXCHARS:   .ascii "0123456789ABCDEF"
CMDS_HELP:  .asciz "HELP"
CMDS_LED:   .asciz "LED"
CMDS_HEX:   .asciz "HEX"
CMDS_SW:    .asciz "SW"
CMDS_TIMER: .asciz "TIMER"
STR_BANNER: .asciz "\n=== RISC-V DE10-Lite command shell ===\ntype HELP for commands\n"
STR_PROMPT: .asciz "> "
STR_NL:     .asciz "\n"
STR_BS:     .asciz "\b \b"
STR_HELP:   .asciz "commands: HELP | LED <value> | HEX <digits> | SW | TIMER <ms>\n"
STR_LED_USAGE:   .asciz "usage: LED <value>   e.g. LED 0x155\n"
STR_LED_RES:     .asciz "LEDR8-0 = "
STR_HEX_USAGE:   .asciz "usage: HEX <1-6 hex digits>\n"
STR_SW_RES:      .asciz "SW9-0 = "
STR_PAREN:       .asciz " ("
STR_CPAREN:      .asciz ")\n"
STR_TIMER_USAGE: .asciz "usage: TIMER <ms>  (0 = stop)\n"
STR_TIMER_STOP:  .asciz "timer stopped\n"
STR_TIMER_RES1:  .asciz "LEDR9 toggles every "
STR_TIMER_RES2:  .asciz " ms\n"
STR_UNKNOWN1:    .asciz "unknown command: "
STR_UNKNOWN2:    .asciz "  (type HELP)\n"
        .align 2

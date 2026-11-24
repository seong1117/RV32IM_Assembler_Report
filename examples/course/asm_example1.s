# 예제 1: 스톱워치 (CPUlator RISC-V DE10-Lite, rv32-de10-lite) — RV32IM 어셈블리
#
#  - HEX5-4 = 분(00~99), HEX3-2 = 초(00~59), HEX1-0 = 1/100초(00~99)
#  - KEY0: 시작 / 정지 토글,  KEY1: 0 으로 리셋 (정지 상태로)
#  - 인터벌 타이머(0xFF202000, 50 MHz) 10 ms 인터럽트(IRQ 16)로 시간을 센다
#  - KEY 포트(0xFF200050) 인터럽트(IRQ 18)로 버튼을 처리한다
#    (CPUlator 에서는 버튼을 눌렀다 '뗄 때' Edgecapture 가 세팅된다)
#  - 0x00010000 에 적재되어 실행되는 것을 전제로 링크한다 (text 뒤에 data 가 이어짐)
#    주소 참조는 모두 la(pc 상대) 를 쓰므로 적재 주소가 바뀌어도 동작한다

.equ LEDR_BASE,      0xFF200000
.equ HEX3_HEX0_BASE, 0xFF200020
.equ HEX5_HEX4_BASE, 0xFF200030
.equ KEY_BASE,       0xFF200050
.equ TIMER_BASE,     0xFF202000
.equ STACK_TOP,      0x04000000        # SDRAM 끝 바로 다음 (스택은 아래로 성장)
.equ TIMER_PERIOD,   500000            # 50 MHz x 10 ms
.equ IRQ_TIMER,      16
.equ IRQ_KEY,        18

        .text
        .global _start
_start:
        li      sp, STACK_TOP           # 스택 설정 (핸들러도 이 스택을 쓴다)
        la      t0, HANDLER
        csrw    mtvec, t0               # 1. 트랩 핸들러 등록 (direct 모드)

        li      t0, TIMER_BASE          # 2. 인터벌 타이머: 10 ms, 연속, 인터럽트
        li      t1, TIMER_PERIOD
        sw      t1, 8(t0)               #    Periodl (하위 16비트만 저장됨)
        srli    t1, t1, 16
        sw      t1, 12(t0)              #    Periodh
        li      t1, 0x7                 #    START | CONT | ITO
        sw      t1, 4(t0)

        li      t0, KEY_BASE            #    KEY: 에지 지우고 KEY1, KEY0 마스크
        li      t1, 0xF
        sw      t1, 12(t0)              #    Edgecapture 지우기
        li      t1, 0x3
        sw      t1, 8(t0)               #    Interruptmask

        jal     UPDATE_DISPLAY          #    00 00 00 표시

        li      t0, (1 << IRQ_TIMER) | (1 << IRQ_KEY)
        csrs    mie, t0                 # 3. IRQ 16, 18 허용
        csrsi   mstatus, 0x8            # 4. mstatus.MIE = 1
IDLE:
        j       IDLE                    # 모든 일은 인터럽트로 처리된다

# ---------------------------------------------------------------------------
# 트랩 핸들러: 호출자 보존 레지스터 중 사용하는 것(ra, t0~t3, a0~a2)을 저장한다
#              (서브루틴 UPDATE_DISPLAY / TWO_DIGITS 가 쓰는 레지스터 포함)
# ---------------------------------------------------------------------------
        .align 2
HANDLER:
        addi    sp, sp, -32
        sw      ra, 28(sp)
        sw      t0, 24(sp)
        sw      t1, 20(sp)
        sw      t2, 16(sp)
        sw      t3, 12(sp)
        sw      a0, 8(sp)
        sw      a1, 4(sp)
        sw      a2, 0(sp)

        csrr    t0, mcause              # 원인: 0x80000000 | IRQ
        li      t1, 0x80000000 | IRQ_TIMER
        beq     t0, t1, DO_TIMER
        li      t1, 0x80000000 | IRQ_KEY
        beq     t0, t1, DO_KEY
UNEXPECTED:
        j       UNEXPECTED              # 예상 밖의 트랩이면 멈춤
DO_TIMER:
        jal     TIMER_ISR
        j       EXIT_TRAP
DO_KEY:
        jal     KEY_ISR
EXIT_TRAP:
        lw      a2, 0(sp)
        lw      a1, 4(sp)
        lw      a0, 8(sp)
        lw      t3, 12(sp)
        lw      t2, 16(sp)
        lw      t1, 20(sp)
        lw      t0, 24(sp)
        lw      ra, 28(sp)
        addi    sp, sp, 32
        mret

# ---------------------------------------------------------------------------
# TIMER_ISR: 10 ms 마다. TO 해제 -> running 이면 시간 증가 -> 표시 갱신
# ---------------------------------------------------------------------------
TIMER_ISR:
        addi    sp, sp, -4
        sw      ra, 0(sp)
        li      t0, TIMER_BASE
        sw      zero, 0(t0)             # Status 에 쓰기 = TO(인터럽트 요청) 해제

        la      t0, RUNNING
        lw      t1, 0(t0)
        beqz    t1, TIMER_DONE          # 정지 상태면 아무것도 안 함

        la      t0, CENTIS              # ++centis
        lw      t1, 0(t0)
        addi    t1, t1, 1
        li      t2, 100
        bne     t1, t2, TIMER_STORE_CS
        sw      zero, 0(t0)             # centis = 0
        la      t0, SECONDS             # ++seconds
        lw      t1, 0(t0)
        addi    t1, t1, 1
        li      t2, 60
        bne     t1, t2, TIMER_STORE_SEC
        sw      zero, 0(t0)             # seconds = 0
        la      t0, MINUTES             # ++minutes
        lw      t1, 0(t0)
        addi    t1, t1, 1
        li      t2, 100
        bne     t1, t2, TIMER_STORE_MIN
        li      t1, 0                   # minutes = 0 (99:59.99 다음은 00:00.00)
TIMER_STORE_MIN:
        sw      t1, 0(t0)
        j       TIMER_SHOW
TIMER_STORE_SEC:
        sw      t1, 0(t0)
        j       TIMER_SHOW
TIMER_STORE_CS:
        sw      t1, 0(t0)
TIMER_SHOW:
        jal     UPDATE_DISPLAY
TIMER_DONE:
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# ---------------------------------------------------------------------------
# KEY_ISR: Edgecapture 읽어 되써서 지우고, KEY1 = 리셋, KEY0 = 시작/정지
# ---------------------------------------------------------------------------
KEY_ISR:
        addi    sp, sp, -4
        sw      ra, 0(sp)
        li      t0, KEY_BASE
        lw      t1, 12(t0)              # Edgecapture
        sw      t1, 12(t0)              # 같은 값을 써서 지우기 (요청 해제)

        andi    t2, t1, 0x2             # KEY1 ?
        beqz    t2, KEY_CHECK0
        la      t0, RUNNING             # 리셋: running = 0, 시간 = 0
        sw      zero, 0(t0)
        la      t0, CENTIS
        sw      zero, 0(t0)
        la      t0, SECONDS
        sw      zero, 0(t0)
        la      t0, MINUTES
        sw      zero, 0(t0)
        j       KEY_SHOW
KEY_CHECK0:
        andi    t2, t1, 0x1             # KEY0 ?
        beqz    t2, KEY_SHOW
        la      t0, RUNNING             # running ^= 1
        lw      t1, 0(t0)
        xori    t1, t1, 1
        sw      t1, 0(t0)
KEY_SHOW:
        jal     UPDATE_DISPLAY
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# ---------------------------------------------------------------------------
# UPDATE_DISPLAY: HEX3-0 <- 초:1/100초, HEX5-4 <- 분, LEDR0 <- running
#   사용 레지스터: a0, a1, a2, t0, t1, t2, t3 (t 는 TWO_DIGITS 안에서)
# ---------------------------------------------------------------------------
UPDATE_DISPLAY:
        addi    sp, sp, -4
        sw      ra, 0(sp)
        la      t0, SECONDS
        lw      a0, 0(t0)
        jal     TWO_DIGITS              # a0 <- seg(초)
        slli    a2, a0, 16              # 상위 하프워드에 초
        la      t0, CENTIS
        lw      a0, 0(t0)
        jal     TWO_DIGITS              # a0 <- seg(1/100초)
        or      a2, a2, a0
        li      t0, HEX3_HEX0_BASE
        sw      a2, 0(t0)
        la      t0, MINUTES
        lw      a0, 0(t0)
        jal     TWO_DIGITS              # a0 <- seg(분)
        li      t0, HEX5_HEX4_BASE
        sw      a0, 0(t0)
        la      t0, RUNNING
        lw      a1, 0(t0)
        li      t0, LEDR_BASE
        sw      a1, 0(t0)               # LEDR0 = 동작 중 표시
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# ---------------------------------------------------------------------------
# TWO_DIGITS: a0 = 0~99  ->  a0 = (seg[십의 자리] << 8) | seg[일의 자리]
#   RV32M 의 divu / remu 사용. 사용 레지스터: t1, t2, t3
# ---------------------------------------------------------------------------
TWO_DIGITS:
        li      t1, 10
        divu    t2, a0, t1              # 십의 자리
        remu    t3, a0, t1              # 일의 자리
        la      t1, SEG7
        add     t2, t2, t1
        lbu     t2, 0(t2)               # seg[십]
        add     t3, t3, t1
        lbu     t3, 0(t3)               # seg[일]
        slli    a0, t2, 8
        or      a0, a0, t3
        ret

# ---------------------------------------------------------------------------
        .data
        .align 2
RUNNING: .word 0                        # 1 이면 시간이 흐른다
CENTIS:  .word 0                        # 0 ~ 99
SECONDS: .word 0                        # 0 ~ 59
MINUTES: .word 0                        # 0 ~ 99
SEG7:    .byte 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F
        .align 2

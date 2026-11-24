.macro LOAD_PAIR base
    flw fa0, 0(\base)
    flw fa1, 4(\base)
.endm

.include "f_helpers.inc"
.section .text
_start:
    la t0, values
    LOAD_PAIR t0
    fadd.s fa2, fa0, fa1, rtz
    fsub.s fa2, fa0, fa1
    fmul.s fa2, fa0, fa1
    fdiv.s fa2, fa0, fa1
    fsqrt.s fa2, fa0
    fmin.s fa2, fa0, fa1
    fmax.s fa2, fa0, fa1
    fmadd.s fa2, fa0, fa1, fa3
    fmsub.s fa2, fa0, fa1, fa3
    fnmsub.s fa2, fa0, fa1, fa3
    fnmadd.s fa2, fa0, fa1, fa3
    feq.s t1, fa0, fa1
    flt.s t1, fa0, fa1
    fle.s t1, fa0, fa1
    fcvt.w.s t1, fa0, rtz
    fcvt.wu.s t1, fa0, rdn
    fcvt.s.w fa2, t1, rup
    fcvt.s.wu fa2, t1, rmm
    fmv.x.w t1, fa0
    fmv.w.x fa2, t1
    fclass.s t1, fa0
    fsgnj.s fa2, fa0, fa1
    fsgnjn.s fa2, fa0, fa1
    fsgnjx.s fa2, fa0, fa1
    fmv.s fa2, fa0
    fneg.s fa2, fa0
    fabs.s fa2, fa0
    fsw fa2, 8(t0)
    j 1f
    nop
1:  j 1b
1:  j 1b
.data
.balign 8
values: .float 1.5, 2.25, 0.0, -0.0
.double -2.5
.dword 0xFEDCBA9876543210, -9223372036854775808

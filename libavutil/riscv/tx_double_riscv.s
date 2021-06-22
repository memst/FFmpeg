#*
#* This file is part of FFmpeg.
#*
#* FFmpeg is free software; you can redistribute it and/or
#* modify it under the terms of the GNU Lesser General Public
#* License as published by the Free Software Foundation; either
#* version 2.1 of the License, or (at your option) any later version.
#*
#* FFmpeg is distributed in the hope that it will be useful,
#* but WITHOUT ANY WARRANTY; without even the implied warranty of
#* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#* Lesser General Public License for more details.
#*
#* You should have received a copy of the GNU Lesser General Public
#* License along with FFmpeg; if not, write to the Free Software
#* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#*

    .text                       # Start text section
    .align 2                    # align 4 byte instructions by 2**2 bytes
    .global ff_fft4_double_riscv
    .global ff_fft8_double_riscv
    .global ff_fft16_double_riscv
    
    .global ff_fft4_double_riscv_v128
    .global ff_fft8_double_riscv_v128

#Load part of complex and permute it with revtab
# a0 - pointer to AVTXContext
# v0 - permuted vector
# n  - number of samples
.macro PERMUTE_REVTAB_I n
    vsetivli t0, \n, e32, m4, ta, ma
    lw t1, 56(a0)                       #*revtab
    vle32.v v0, 0(t1)                   # revtab
    li t1, 16
    vwmul.vx v8, v0, t1                 #multiply revtab indices by 16 (building byte offsets)
    vsetivli t0, \n*2, e64, m8, ta, ma
    la t1, double_up_ladder
    vle64.v v0, (t1)
    vrgather.vv v16, v8, v0             #spread revtab over two doubles for re+im
    la t1, zero_eight_repeating
    vle64.v v8, (t1)
    vfadd.vv v16, v16, v8               #increment every 2nd offset
    vloxei64.v v0, (a2), v16            #permuted vector
.endm

#Load part of complex and permute it with revtab
# av0 - permuted vector (m8 grouping)
# ar0 - FFT size (changed by the macro)
# ar1 - pointer to context
# ar2 - pointer to samples
# temporary scalars:
# tt0 - (number of complexes worked on per iteration)
# tt1 - (*revtab)
# tt2 - ()
# tt3 - ()
# tt4 - (moving pointer to samples)
# temporary vectors (m8 grouping):
# av8  - ()
# av16 - ()
.macro PERMUTE_REVTAB_R av0, ar0, ar1, ar2, tt0, tt1, tt2, tt3, tt4, av8, av16
    # TO-DO: add a subroutine in case the register length exceeds double-up ladder
    lw \tt1, 56(\ar1)                   #*revtab
    addi \tt4, \ar2, 0

    vsetvli \tt0, \ar0, e32, m4, ta, ma
    vle32.v \av0, 0(\tt1)               # revtab
    li \tt2, 16
    vwmul.vx \av8, \av0, \tt2           #multiply revtab indices by 16 (building byte offsets)
                                        #and widen them to 64bit
    slli \tt2, \ar0, 1                  #the number of doules is twice the FFT size
    vsetvli zero, \tt2, e64, m8, ta, ma
    la \tt2, double_up_ladder           #double-up duplicates the indices for both
    vle64.v \av0, (\tt2)                #re and im. Revtab indices go from i0, i1, i2... to
    vrgather.vv \av16, \av8, \av0       #i0, i0, i1, i1, i2, i2...
    la \tt2, zero_eight_repeating       #zero_eight_repeating adds 8 bytes to every 2nd offset to load im values
    vle64.v \av8, (\tt2)
    vfadd.vv \av16, \av16, \av8         #increment every 2nd offset
    vloxei64.v \av0, (\tt4), \av16      #permuted vector
.endm


# av0 - source/output vector
# av2, av4, av6, av8 - temp vectors (m2 grouping)
# at0 - temp scalar
.macro FFT4 av0, av2, av4, av6, av8, at0
    vsetivli        \at0, 8, e64, m2, ta, ma        #16 registers of 8 doubles each
    vslidedown.vi   \av2, \av0, 4                   #4567
    vsetivli        \at0, 4, e64, m2, ta, ma        #16 registers of 4 doubles each
    vfsub.vv        \av4, \av0, \av2                #r1234
    vfadd.vv        \av2, \av0, \av2                #t1234
    vsetivli        \at0, 8, e64, m2, ta, ma        #16 registers of 8 doubles each
    vslideup.vi     \av4, \av2, 4                   #r1234 t1234
    la              \at0, fft4_shufs                #Load shufs
    vle64.v         \av6, 0(\at0)                   
    addi            \at0, \at0, 64
    vle64.v         \av8, 0(\at0)
    vrgather.vv     \av0, \av4, \av6                #t12r12 t12r12
    vrgather.vv     \av2, \av4, \av8                #t34r43 t34r43
    addi            \at0, \at0, 64                  #Load 'shuf'
    vle64.v         \av8, 0(\at0)
    vfmul.vv        \av2, \av2, \av8                #v8 - PPPN NNNP
    vfadd.vv        \av0, \av0, \av2                #v0 - Final result
.endm

# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft4_double_riscv:
    #PERMUTE_REVTAB_I 4                             #Load array through revtab (unnecessary as it's just 0123)
    vsetivli        t0, 8, e64, m2, ta, ma          #16 registers of 8 doubles each
    vle64.v         v0, (a2)                        #Load array directly

    FFT4 v0, v2, v4, v6, v8, t0                     #FFT4

    #Arrange samples in final order
    la t0,          fft4_shufs_end
    vle64.v         v2, 0(t0)
    vsoxei64.v      v0, (a1), v2
    ret

# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft4_double_riscv_v128:
    PERMUTE_REVTAB_I 4
    vsetivli t0, 4, e64, m2
    vfsub.vv v4, v0, v2         #r1234
    vfadd.vv v6, v0, v2         #t1234

    vsetivli t0, 16, e64, m8
    la t1, fft4_v128_shufs
    vle64.v v16, 0(t1)
    vrgather.vv v8, v0, v16     #t12r12 t12r12 t34r43 t34r43    v16 - cd89 cd89 efba efba
    vsetivli t0, 8, e64, m4
    addi t1, t1, 128
    vle64.v v24, 0(t1)
    vfmul.vv v12, v12, v24      #v24 - PPPN NNNP
    vfadd.vv v0, v8, v12        #a12 b12 a34 b34
    vse64.v v0, 0(a1)
    ret

#TO-DO: It's possible convert FFT8 and FFT4 to dual strie
.macro FFT8
    vsetivli        t0, 8, e64, m2, ta, ma
    #Could use segmented loads to accomplish these loads with less instructions
    # (may be slower)
    la              t4, fft8_shufs
    vle64.v         v16, 0(t4)
    addi            t4, t4, 64
    vle64.v         v20, 0(t4)
    addi            t4, t4, 64
    vle64.v         v24, 0(t4)
    addi            t4, t4, 64
    vle64.v         v28, 0(t4)

    vslidedown.vi   v4, v0, 8                       #4567

    vfadd.vv        v8, v0, v4                      #q1234 k1234
    vfsub.vv        v0, v0, v4                      #r1234 j1234

    vrgather.vv     v12, v8, v16                    #q12 k32 q34 k14    v16 - 01652347 
    vrgather.vv     v4, v0, v20                     #r1212 r4343        v20 - 01013232 
    vrgather.vv     v8, v0, v24                     #j4321 j3412        v24 - 76546745 
    vfmul.vv        v8, v8, v28                     #j'    v28 - sqrt(1/2) - PNNP NNPP

    vsetivli        t0, 4, e64, m1, ta, ma
    addi            t4, t4, 64
    vle64.v         v16, 0(t4)
    addi            t4, t4, 32
    vle64.v         v18, 0(t4)
    addi            t4, t4, 32
    vle64.v         v20, 0(t4)
    addi            t4, t4, 32
    vle64.v         v22, 0(t4)

    vslidedown.vi   v6, v4, 4                       #r4343
    vfmacc.vv       v4, v6, v16                     #z1234              v16 - 1, -1, -1, 1 

    vslidedown.vi   v10, v8, 4                      #j3412
    vfadd.vv        v6, v8, v10                     #l3412
    vrgather.vv     v0, v6, v18                     #l2143              v18 - 3210 
    vfmacc.vv       v6, v0, v20                     #t1234              v20 - -1, 1, -1, 1 

    vslidedown.vi   v14, v12, 4                     #q34 k14
    vfadd.vv        v0, v12, v14                    #s12 g12
    vfsub.vv        v2, v12, v14                    #s34 g43

    vfadd.vv        v14, v4, v6                     #o1234 (out)
    vfsub.vv        v12, v4, v6                     #u1234 (out)

    vsetivli        t0, 8, e64, m2
    vslideup.vi     v0, v2, 4
    addi            t4, t4, 32
    vle64.v         v24, 0(t4)
    vrgather.vv     v4, v0, v24                     #s1234 g1234        v24 - 01452376 
    vsetivli        t0, 4, e64, m1                  #16 registers v0, v2, v4... of 4 doubles each

    vslidedown.vi   v6, v4, 4
    vfadd.vv        v0, v4, v6                      #w1234 (out)
    vfsub.vv        v10, v4, v6                     #h1234 (out)

    vsetivli        t0, 8, e64, m2                  #3 registers v0, v8, v16, v24 of 16 doubles each
    vslideup.vi     v0, v10, 4
    vslideup.vi     v12, v14, 4
    vsetivli        t0, 16, e64, m4
    vslideup.vi     v0, v12, 8
.endm

# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft8_double_riscv:
    PERMUTE_REVTAB_I 8
    FFT8

    la t4, fft8_shufs_end        #rearrange the groups back in original order
    vle64.v v4, 0(t4)
    vsoxei64.v v0, (a1), v4
    ret


# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft8_double_riscv_v128:
    PERMUTE_REVTAB_I 8
    vsetivli t0, 16, e64, m8    #4 registers v0, v8, v16, v24 of 16 doubles each
    la t4, fft8_shufs           #load indices needed for shuffles
    vle64.v v16, 0(t4)
    addi t4, t4, 128
    vle64.v v24, 0(t4)
    vsetivli t0, 8, e64, m4     #8 registers v0, v4, v8... of 8 doubles each

    vfadd.vv v8, v0, v4         #q1234 k1234
    vfsub.vv v0, v0, v4         #r1234 j1234

    vrgather.vv v12, v8, v16    #q12 k32 q34 k14    v16 - 01652347 
    vrgather.vv v4, v0, v20     #r1212 r4343        v20 - 01013232 
    vrgather.vv v8, v0, v24     #j4321 j3412        v24 - 76546745 
    vfmul.vv v8, v8, v28        #j'                 v28 - sqrt(1/2) - PNNP NNPP

    vsetivli t0, 16, e64, m8    #enlarge registers for effective loading
    addi t4, t4, 128            #load 2nd set of indices needed for shuffles
    vle64.v v16, 0(t4)
    addi t4, t4, 128            
    vle64.v v24, 0(t4)
    vsetivli t0, 4, e64, m2      #16 registers v0, v2, v4... of 4 doubles each

    vfmacc.vv   v4, v6, v16     #z1234              v16 - 1, -1, -1, 1 

    vfadd.vv    v6, v8, v10     #l3412
    vrgather.vv v0, v6, v18     #l2143              v18 - 3210 
    vfmacc.vv   v6, v0, v20     #t1234              v20 - -1, 1, -1, 1 

    vfadd.vv    v0, v12, v14    #s12 g12
    vfsub.vv    v2, v12, v14    #s34 g43

    vfadd.vv    v14, v4, v6     #o1234 (out)
    vfsub.vv    v12, v4, v6     #u1234 (out)

    vsetivli t0, 8, e64, m4     #8 registers v0, v4, v8... of 8 doubles each
    vrgather.vv v4, v0, v24     #s1234 g1234        v24 - 01452376 
    vsetivli t0, 4, e64, m2     #16 registers v0, v2, v4... of 4 doubles each
    vfadd.vv v8, v4, v6         #w1234 (out)
    vfsub.vv v10, v4, v6        #h1234 (out)
    #fft8_m operates as the example asm where it takes ordered input and returns it split into odd/even groups
    vsetivli t0, 16, e64, m8     #3 registers v0, v8, v16, v24 of 16 doubles each

    la t4, fft8_v128_rearrange        #rearrange the groups back in original order
    vle64.v v16, 0(t4)            
    vrgather.vv v0, v8, v16
    vse64.v v0, 0(a1)
    ret

.macro FFT16
    FFT8
    vse64.v         v0, (a1)

    vsetivli        t0, 8, e64, m2, ta, ma

    # The FFT4s could be combined into a dual FFT, would drastically reduce 
    # the number of memory accesses
    addi            t1, a1, 128
    vle64.v         v0, (t1)
    FFT4            v0, v2, v4, v6, v8, t0
    vse64.v         v0, (t1)

    addi            t1, a1, 192
    vle64.v         v0, (t1)
    FFT4            v0, v2, v4, v6, v8, t0
    vse64.v         v0, (t1)

    vsetivli        t0, 16, e64, m4, ta, ma
    addi            t1, a1, 128
    vle64.v         v0, (t1)

    la t1, fft16_shufs
    vle64.v        v16, (t1)
    addi           t1, t1, 128
    vle64.v        v20, (t1)
    addi           t1, t1, 128
    vle64.v        v24, (t1)
    addi           t1, t1, 128
    vle64.v        v28, (t1)

    vrgather.vv     v4, v0, v16     #rearranging the 2nd terms for s[0..15] sum
    vfmul.vv        v4, v4, v24     #scaled 2nd terms for sum
    vfmul.vv        v0, v0, v20     #scaled 1st terms for sum
    vfadd.vv        v0, v0, v4      #s[0..15]

    vslidedown.vi   v4, v0, 8
    vslideup.vi     v4, v0, 8       #s[8..15] s[0..7]
    vxor.vv         v4, v4, v28     #mask for addition/subtraction
    vfadd.vv        v0, v0, v4      #w56 x56 y56 u56 w34 x34 y34 u34

    vsetivli        t0, 8, e64, m4, ta, ma
    addi            t1, t1, 128
    vle64.v         v20, (t1)       # Load shuf
    vrgather.vv     v4, v0, v20     # w5 w6 x5 x6 w4 w3 x4 x3
    vadd.vi         v20, v20, 4     # Offset the same shuf
    vrgather.vv     v8, v0, v20     # y5 y6 u5 u6 y4 y3 u4 u3
    addi            t1, a1, 64
    vle64.v         v0, (a1)        #z[0..3]
    vle64.v         v12, (t1)       #z[4..7]

    vfsub.vv        v16, v0, v4     #o 17 18 21 22 25 26 29 30
    vfadd.vv        v0 , v0, v4     #o  1  2  5  6  9 10 13 14

    vfadd.vv        v4, v12, v8     #o  3  4  7  8 11 12 15 16
    vfsub.vv        v8, v12, v8     #o 19 20 23 24 27 28 31 32

    vsetivli        t0, 16, e64, m4, ta, ma

    vslideup.vi     v0, v16, 8      #even (out)
    vslideup.vi     v4, v8 , 8      #odd  (out)
.endm

# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft16_double_riscv:
    li              t2, 16
    PERMUTE_REVTAB_R v0, t2, a0, a2, t0, t1, t2, t3, t4, v8, v16
    vse64.v         v0, (a1)

    FFT16

    la              t0, fft16_shufs_end
    vle64.v         v8, (t0)
    addi            t0, t0, 128
    vle64.v         v12, (t0)

    vsoxei64.v      v0, (a1), v8
    vsoxei64.v      v4, (a1), v12
    ret

    .section .rodata            # Start read-only data section
    .balign 4                   # align to 4 bytes

.equ n_zero, 0x8000000000000000

.equ p_one, 0x3FF0000000000000
.equ n_one, 0xBFF0000000000000
.equ p_sqrt_1_2, 0x3FE6A09E667F3BCD
.equ n_sqrt_1_2, 0xBFE6A09E667F3BCD

#Indices used in REVTAB
double_up_ladder:
    .dword 0x0, 0x0, 0x1, 0x1
    .dword 0x2, 0x2, 0x3, 0x3
    .dword 0x4, 0x4, 0x5, 0x5
    .dword 0x6, 0x6, 0x7, 0x7
    .dword 0x8, 0x8, 0x9, 0x9
    .dword 0xa, 0xa, 0xb, 0xb
    .dword 0xc, 0xc, 0xd, 0xd
    .dword 0xe, 0xe, 0xf, 0xf

zero_eight_repeating:
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8

fft4_shufs:
    .dword 0x4, 0x5, 0x4, 0x5
    .dword 0x0, 0x1, 0x0, 0x1

    .dword 0x6, 0x7, 0x6, 0x7
    .dword 0x3, 0x2, 0x3, 0x2

    .dword p_one, p_one, n_one, n_one
    .dword p_one, n_one, n_one, p_one

fft4_shufs_end:
    .dword 0x00, 0x08, 0x20, 0x28
    .dword 0x10, 0x18, 0x30, 0x38

fft4_v128_shufs:
    .dword 0xc, 0xd, 0x8, 0x9
    .dword 0xc, 0xd, 0x8, 0x9

    .dword 0xe, 0xf, 0xb, 0xa
    .dword 0xe, 0xf, 0xb, 0xa

    .dword p_one, p_one, p_one, n_one
    .dword n_one, n_one, n_one, p_one

    #.dword
    #.dword

fft8_shufs:
    .dword 0x0, 0x1, 0x6, 0x5
    .dword 0x2, 0x3, 0x4, 0x7

    .dword 0x0, 0x1, 0x0, 0x1
    .dword 0x3, 0x2, 0x3, 0x2

    .dword 0x7, 0x6, 0x5, 0x4
    .dword 0x6, 0x7, 0x4, 0x5

    .dword p_sqrt_1_2, n_sqrt_1_2, n_sqrt_1_2, p_sqrt_1_2
    .dword n_sqrt_1_2, n_sqrt_1_2, p_sqrt_1_2, p_sqrt_1_2
#fft8_shufs2:
    .dword p_one, n_one, n_one, p_one
    .dword 0x3, 0x2, 0x1, 0x0

    .dword n_one, p_one, n_one, p_one
    .dword 0x0, 0x0, 0x0, 0x0

    .dword 0x0, 0x1, 0x4, 0x5
    .dword 0x2, 0x3, 0x7, 0x6

fft8_shufs_end:
    .dword 0x00, 0x08, 0x20, 0x28
    .dword 0x40, 0x48, 0x60, 0x68
    .dword 0x10, 0x18, 0x30, 0x38
    .dword 0x50, 0x58, 0x70, 0x78

fft8_v128_rearrange:
    .dword 0x0, 0x1, 0x8, 0x9, 0x2, 0x3, 0xa, 0xb, 0x4, 0x5, 0xc, 0xd, 0x6, 0x7, 0xe, 0xf

.equ p_cos_16_1, 0x3fed906bcf328d46
.equ p_cos_16_2, 0x3fe6a09e667f3bcd
.equ p_cos_16_3, 0x3fd87de2a6aea964

.equ n_cos_16_1, 0xbfed906bcf328d46
.equ n_cos_16_2, 0xbfe6a09e667f3bcd
.equ n_cos_16_3, 0xbfd87de2a6aea964

fft16_shufs:
    #1st load
    .dword 0x1, 0x0, 0x3, 0x2, 0x5, 0x4, 0x7, 0x6
    .dword 0x9, 0x8, 0xb, 0xa, 0xd, 0xc, 0xf, 0xe

    .dword p_one, p_one, p_cos_16_2, p_cos_16_2, p_cos_16_1, p_cos_16_1, p_cos_16_3, p_cos_16_3
    .dword p_one, n_one, p_cos_16_2, n_cos_16_2, p_cos_16_1, n_cos_16_1, p_cos_16_3, n_cos_16_3

    .dword 0x0, 0x0, p_cos_16_2, n_cos_16_2, p_cos_16_3, n_cos_16_3, p_cos_16_1, n_cos_16_1
    .dword 0x0, 0x0, n_cos_16_2, n_cos_16_2, n_cos_16_3, n_cos_16_3, n_cos_16_1, n_cos_16_1

    .dword    0x0, n_zero,    0x0, n_zero
    .dword    0x0, n_zero,    0x0, n_zero
    .dword n_zero,    0x0, n_zero,    0x0
    .dword n_zero,    0x0, n_zero,    0x0

    #2nd load
    .dword 0x0, 0x1, 0x2, 0x3, 0x9, 0x8, 0xb, 0xa

fft16_shufs_end:
    .dword 0x00, 0x08, 0x20, 0x28, 0x40, 0x48, 0x60, 0x68
    .dword 0x80, 0x88, 0xa0, 0xa8, 0xc0, 0xc8, 0xe0, 0xe8

    .dword 0x10, 0x18, 0x30, 0x38, 0x50, 0x58, 0x70, 0x78
    .dword 0x90, 0x98, 0xb0, 0xb8, 0xd0, 0xd8, 0xf0, 0xf8
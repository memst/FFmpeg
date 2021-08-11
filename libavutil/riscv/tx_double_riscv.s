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
    vrgather.vv v16, v8, v0              #spread revtab over two doubles for re+im
    la t1, zero_eight_repeating
    vle64.v v8, (t1)
    vfadd.vv v16, v16, v8                 #increment every 2nd offset
    vloxei64.v v0, (a2), v16             #permuted vector
.endm

# vsetivli t0, 8, e64, m2, ta, ma
# av0 - source/output vector
# av1, av2, av3, av4 - temp vectors
# at0 - temp scalar
.macro FFT4 av0, av1, av2, av3, av4, at0
    vslidedown.vi \av1, \av0, 4
    vsetivli \at0, 4, e64, m2, ta, ma
    vfsub.vv \av2, \av0, \av1                 #r1234
    vfadd.vv \av1, \av0, \av1                 #t1234
    vsetivli \at0, 8, e64, m2, ta, ma
    vslideup.vi \av2, \av1, 4               #r1234 t1234
    la \at0, fft4_shufs
    vle64.v \av3, 0(\at0)
    addi \at0, \at0, 64
    vle64.v \av4, 0(\at0)
    vrgather.vv \av0, \av2, \av3              #t12r12 t12r12
    vrgather.vv \av1, \av2, \av4              #t34r43 t34r43
    addi \at0, \at0, 64
    vle64.v \av4, 0(\at0)
    vfmul.vv \av1, \av1, \av4                 #v16 - PPPN NNNP
    vfadd.vv \av0, \av0, \av1
.endm

# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft4_double_riscv:
    PERMUTE_REVTAB_I 4
    #Do and store FFT4
    vsetivli t0, 8, e64, m2, ta, ma
    FFT4 v0, v2, v4, v6, v8, t0
    vse64.v v0, 0(a1)
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

.macro FFT8
    #TO-DO: Optimise register use
    vsetivli t0, 8, e64, m2, ta, ma
    #TO-DO: Investigate using segmented loads to accomplish this with less instructions
    la t4, fft8_shufs
    vle64.v v16, 0(t4)
    addi t4, t4, 64
    vle64.v v20, 0(t4)
    addi t4, t4, 64
    vle64.v v24, 0(t4)
    addi t4, t4, 64
    vle64.v v28, 0(t4)

    vslidedown.vi v4, v0, 8     #4567

    vfadd.vv v8, v0, v4         #q1234 k1234
    vfsub.vv v0, v0, v4         #r1234 j1234

    vrgather.vv v12, v8, v16    #q12 k32 q34 k14    v16 - 01652347 
    vrgather.vv v4, v0, v20     #r1212 r4343        v20 - 01013232 
    vrgather.vv v8, v0, v24     #j4321 j3412        v24 - 76546745 
    vfmul.vv v8, v8, v28        #j'                 v28 - sqrt(1/2) - PNNP NNPP

    vsetivli t0, 4, e64, m1, ta, ma
    addi t4, t4, 64
    vle64.v v16, 0(t4)
    addi t4, t4, 32
    vle64.v v18, 0(t4)
    addi t4, t4, 32
    vle64.v v20, 0(t4)
    addi t4, t4, 32
    vle64.v v22, 0(t4)

    vslidedown.vi v6, v4, 4     #r4343
    vfmacc.vv v4, v6, v16        #z1234              v16 - 1, -1, -1, 1 

    vslidedown.vi v10, v8, 4    #j3412
    vfadd.vv v6, v8, v10        #l3412
    vrgather.vv v0, v6, v18      #l2143              v18 - 3210 
    vfmacc.vv v6, v0, v20       #t1234              v20 - -1, 1, -1, 1 

    vslidedown.vi v14, v12, 4   #q34 k14
    vfadd.vv    v0, v12, v14    #s12 g12
    vfsub.vv    v2, v12, v14    #s34 g43

    vfadd.vv    v14, v4, v6     #o1234 (out)
    vfsub.vv    v12, v4, v6     #u1234 (out)

    vsetivli t0, 8, e64, m2
    vslideup.vi v0, v2, 4
    addi t4, t4, 32
    vle64.v v24, 0(t4)
    vrgather.vv v4, v0, v24     #s1234 g1234        v24 - 01452376 
    vsetivli t0, 4, e64, m1     #16 registers v0, v2, v4... of 4 doubles each

    vslidedown.vi v6, v4, 4
    vfadd.vv v8, v4, v6         #w1234 (out)
    vfsub.vv v10, v4, v6        #h1234 (out)

    vsetivli t0, 8, e64, m2     #3 registers v0, v8, v16, v24 of 16 doubles each
    vslideup.vi v8, v10, 4
    vslideup.vi v12, v14, 4
    vsetivli t0, 16, e64, m4
    vslideup.vi v8, v12, 8

    la t4, fft8_rearrange        #rearrange the groups back in original order
    vle64.v v16, 0(t4)            
    vrgather.vv v0, v8, v16
.endm

# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft8_double_riscv:
    PERMUTE_REVTAB_I 8
    FFT8
    vse64.v v0, 0(a1)
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
#fft8_e: 
    vsetivli t0, 16, e64, m8     #3 registers v0, v8, v16, v24 of 16 doubles each

    la t4, fft8_rearrange        #rearrange the groups back in original order
    vle64.v v16, 0(t4)            
    vrgather.vv v0, v8, v16
    vse64.v v0, 0(a1)
    ret

# a0- AVTXContext
# a1- FFTComplex out
# a2- FFTComplex in
# a4- tmp
ff_fft16_double_riscv:
    li t2, 64
    li t3, 32
    vsetvli t0, t2, e64, m8
    la t1, fft16_shufs
    vle64.v v24, (t1)
    vsetvli t0, t3, e64, m4
    vle64.v v0, (a2)                #Load the complex
    #Call Smaller FFTs here
    vrgather.vv v4, v0, v28
    vfmul.vv v4, v4, v24
    vsetivli t0, 16, e64, m2
    vfadd.vv v4, v4, v6
    vsetivli t0, 8, e64, m1
    vfadd.vv v6, v4, v5
    vfsub.vv v4, v4, v5
    la t1, fft16_shufs2
    vle64.v v31, (t1)
    vrgather.vv v7, v4, v31
    vsetivli t0, 16, e64, m2
    vfsub.vv v2, v0, v6
    vfadd.vv v0, v0, v6
    vsetvli t0, t3, e64, m4
    vse64.v v0, (a1)
    ret
    

    .section .rodata            # Start read-only data section
    .balign 4                   # align to 4 bytes

.equ p_one, 0x3FF0000000000000
.equ n_one, 0xBFF0000000000000
.equ p_sqrt_1_2, 0x3FE6A09E667F3BCD
.equ n_sqrt_1_2, 0xBFE6A09E667F3BCD

double_up_ladder:
    .dword 0x0, 0x0, 0x1, 0x1
    .dword 0x2, 0x2, 0x3, 0x3
    .dword 0x4, 0x4, 0x5, 0x5
    .dword 0x6, 0x6, 0x7, 0x7
    #.dword 0x8, 0x8, 0x9, 0x9
    #.dword 0xa, 0xa, 0xb, 0xb
    #.dword 0xc, 0xc, 0xd, 0xd
    #.dword 0xe, 0xe, 0xf, 0xf

zero_eight_repeating:
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    .dword 0x0, 0x8, 0x0, 0x8
    #.dword 0x0, 0x8, 0x0, 0x8
    #.dword 0x0, 0x8, 0x0, 0x8
    #.dword 0x0, 0x8, 0x0, 0x8
    #.dword 0x0, 0x8, 0x0, 0x8

fft4_shufs:
    .dword 0x4, 0x5, 0x0, 0x1
    .dword 0x4, 0x5, 0x0, 0x1

    .dword 0x6, 0x7, 0x3, 0x2
    .dword 0x6, 0x7, 0x3, 0x2

    .dword p_one, p_one, p_one, n_one
    .dword n_one, n_one, n_one, p_one

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
fft8_shufs2:
    .dword p_one, n_one, n_one, p_one
    .dword 0x3, 0x2, 0x1, 0x0

    .dword n_one, p_one, n_one, p_one
    .dword 0x0, 0x0, 0x0, 0x0

    .dword 0x0, 0x1, 0x4, 0x5
    .dword 0x2, 0x3, 0x7, 0x6

fft8_rearrange:
    .dword 0x0, 0x1, 0x8, 0x9, 0x2, 0x3, 0xa, 0xb, 0x4, 0x5, 0xc, 0xd, 0x6, 0x7, 0xe, 0xf

.equ p_cos_16_1, 0x3fed906bcf328d46
.equ p_cos_16_2, 0x3fe6a09e667f3bcd
.equ p_cos_16_3, 0x3fd87de2a6aea964

.equ n_cos_16_1, 0xbfed906bcf328d46
.equ n_cos_16_2, 0xbfe6a09e667f3bcd
.equ n_cos_16_3, 0xbfd87de2a6aea964

fft16_shufs:
    .dword p_one, p_one, p_cos_16_1, n_cos_16_3, p_cos_16_2, n_cos_16_2, p_cos_16_3, n_cos_16_1
    .dword p_one, p_one, p_cos_16_1, p_cos_16_3, p_cos_16_2, p_cos_16_2, p_cos_16_3, p_cos_16_1

    .dword 0x0, 0x0, n_cos_16_3, p_cos_16_1, n_cos_16_2, p_cos_16_2, n_cos_16_1, p_cos_16_3
    .dword 0x0, 0x0, p_cos_16_3, p_cos_16_1, p_cos_16_2, p_cos_16_2, p_cos_16_1, p_cos_16_3

    #.dword 0x18, 0x11, 0x1a, 0x12, 0x1c, 0x14, 0x1e, 0x16 
    #.dword 0x10, 0x19, 0x14, 0x1c, 0x12, 0x1a, 0x17, 0x1f

    #.dword 0x0, 0x0, 0x1b, 0x13, 0x1d, 0x15, 0x1f, 0x17
    #.dword 0x0, 0x0, 0x15, 0x1d, 0x13, 0x1b, 0x16, 0x1e

    .dword 0x18, 0x11, 0x1a, 0x12, 0x1c, 0x14, 0x1e, 0x16
    .dword 0x10, 0x19, 0x12, 0x1a, 0x14, 0x1c, 0x16, 0x1e

    .dword 0x00, 0x00, 0x1b, 0x13, 0x1d, 0x15, 0x1f, 0x17
    .dword 0x00, 0x00, 0x13, 0x1b, 0x15, 0x1d, 0x17, 0x1f
fft16_shufs2:
    .dword 0x1, 0x0, 0x3, 0x2, 0x5, 0x4, 0x7, 0x6
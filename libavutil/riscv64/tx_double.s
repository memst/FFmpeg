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
    .global ff_fft8_double      # define global function symbol
    
# a1 - FFTComplex
ff_fft8_double:
    addi t1, zero, 4
    addi t2, zero, 8
    addi t3, zero, 16
    vsetvli t0, t3, e64, m8     #4 registers v0, v8, v16, v24 of 16 doubles each
    vle64.v v0, (a1)            #load fftcomplex to register
fft8_m:
    la t4, shufs                #load indices needed for shuffles
    vle64.v v16, 0(t4)
    addi t4, t4, 128
    vle64.v v24, 0(t4)
    vsetvli t0, t2, e64, m4     #8 registers v0, v4, v8... of 8 doubles each

    vfadd.vv v8, v0, v4         #q1234 k1234
    vfsub.vv v0, v0, v4         #r1234 j1234

    vrgather.vv v12, v8, v16    #q12 k32 q34 k14    v16 - 01652347 
    vrgather.vv v4, v0, v20     #r1212 r4343        v20 - 01013232 
    vrgather.vv v8, v0, v24     #j4321 j3412        v24 - 76546745 
    vfmul.vv v8, v8, v28        #j'                 v28 - sqrt(1/2) - PNNP NNPP

    vsetvli t0, t3, e64, m8     #enlarge registers for effective loading
    addi t4, t4, 128            #load 2nd set of indices needed for shuffles
    vle64.v v16, 0(t4)
    addi t4, t4, 128            
    vle64.v v24, 0(t4)
    vsetvli t0, t1, e64, m2     #16 registers v0, v2, v4... of 4 doubles each

    vfmacc.vv   v4, v6, v16     #z1234              v16 - 1, -1, -1, 1 

    vfadd.vv    v6, v8, v10     #l3412
    vrgather.vv v0, v6, v18     #l2143              v18 - 3210 
    vfmacc.vv   v6, v0, v20     #t1234              v20 - -1, 1, -1, 1 

    vfadd.vv    v0, v12, v14    #s12 g12
    vfsub.vv    v2, v12, v14    #s34 g43

    vfadd.vv    v14, v4, v6     #o1234 (out)
    vfsub.vv    v12, v4, v6     #u1234 (out)

    vsetvli t0, t2, e64, m4     #8 registers v0, v4, v8... of 8 doubles each
    vrgather.vv v4, v0, v24     #s1234 g1234        v24 - 01452376 
    vsetvli t0, t1, e64, m2     #16 registers v0, v2, v4... of 4 doubles each
    vfadd.vv v8, v4, v6         #w1234 (out)
    vfsub.vv v10, v4, v6        #h1234 (out)
    #fft8_m operates as the example asm where it takes ordered input and returns it split into odd/even groups
fft8_e: 
    vsetvli t0, t3, e64, m8     #3 registers v0, v8, v16, v24 of 16 doubles each

    la t4, rearrange            #rearrange the groups back in original order
    vle64.v v16, 0(t4)            
    vrgather.vv v0, v8, v16
    vse64.v v0, 0(a1)
    ret

    .section .rodata            # Start read-only data section
    .balign 4                   # align to 4 bytes

fft8_shufs:
    .dword 0x0, 0x1, 0x6, 0x5
    .dword 0x2, 0x3, 0x4, 0x7

    .dword 0x0, 0x1, 0x0, 0x1
    .dword 0x3, 0x2, 0x3, 0x2

    .dword 0x7, 0x6, 0x5, 0x4
    .dword 0x6, 0x7, 0x4, 0x5

    #pos sqrt(1/2) 0x3FE6A09E667F3BCD
    #neg sqrt(1/2) 0xBFE6A09E667F3BCD
    .dword 0x3FE6A09E667F3BCD, 0xBFE6A09E667F3BCD, 0xBFE6A09E667F3BCD, 0x3FE6A09E667F3BCD
    .dword 0xBFE6A09E667F3BCD, 0xBFE6A09E667F3BCD, 0x3FE6A09E667F3BCD, 0x3FE6A09E667F3BCD
fft8_shufs2:
    # 1 0x3FF0000000000000
    #-1 0xBFF0000000000000
    .dword 0x3FF0000000000000, 0xBFF0000000000000, 0xBFF0000000000000, 0x3FF0000000000000
    .dword 0x3, 0x2, 0x1, 0x0

    .dword 0xBFF0000000000000, 0x3FF0000000000000, 0xBFF0000000000000, 0x3FF0000000000000
    .dword 0x0, 0x0, 0x0, 0x0

    .dword 0x0, 0x1, 0x4, 0x5
    .dword 0x2, 0x3, 0x7, 0x6

fft8_rearrange:
    .dword 0x0, 0x1, 0x8, 0x9, 0x2, 0x3, 0xa, 0xb, 0x4, 0x5, 0xc, 0xd, 0x6, 0x7, 0xe, 0xf
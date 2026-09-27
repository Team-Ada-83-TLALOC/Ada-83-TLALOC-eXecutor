# Ada_83_TLALOC_eXecutor — executing the LLIR of TLALOC (tx_run)

`tx_run` executes programs produced by the Ada 83 compiler TLALOC without going through x86 code. It accepts two image formats, recognised by the signature in their header:

- **TX** (`TLALOCTX`), produced by `codi_TX.finc`: one 16-byte record per LLIR instruction. This is the study format, which gives the interpreter every field of every instruction.
- **HX** (`TLALOCHX`), produced by `codi_HX.finc`: the **exact binary of the TAHX machine**, as specified in `LLIR_hardware_support_V3.txt`. One-byte opcode, 0 to 8 bytes of complement, 2.41 bytes per executed instruction on TLALOC.

Both codis keep the macro names and parameters of `codi_x86_64L.finc`. The front end's `.FINC` files therefore assemble unchanged with either one: only the codi include in the main `.FAS` file changes.

With TLALOC compiling `expander-expressions.adb`, the TX and HX runs produce an `EXPANDER-EXPRESSIONS.FINC` identical to that of the native compiler.

## Building

    gnatmake -gnat83 -O2 -gnatn tx_run.adb           (development)
    gnatmake -gnat83 -O2 -gnatn -gnatp tx_run.adb    (production)

Everything is compiled in Ada 83 mode, with two exceptions, each hidden behind an Ada 83 specification:
- the body of `Args` (`pragma Ada_95`): Ada 83 has no standard access to the command line or the exit code;
- the body of `Hote` (`pragma Ada_2012`): it binds write, read, open, close, lseek, unlink, ioctl and clock_gettime directly. This is the only way to reproduce exactly the semantics of the codi_x86 SYS_ macros (flags 0x242, mode 0700, -errno values, non-canonical terminal mode for GET_CHAR).

**Units**

| unit | role |
|---|---|
| `Mots` | 64-bit types and conversions |
| `TX_Codes` | TX codes and TRAP services (numbering identical to codi_TX) |
| `HX_Codes` | decoding table for the 256 HX opcode bytes: **generated** from the specification by `outils/gen_hx_codes.py`, not to be edited by hand |
| `Memoire` | image + co-stack, data stack and heap regions; checked accesses; loading of TX and HX images |
| `Decodeur_HX` | decoding of HX instructions into the 16-byte canonical form |
| `Machine`, `Machine.Trap` | architectural state, execution loop, common semantics, system services |
| `Profil` | dynamic profile (`-p`) |
| `Limites` | limit study of available parallelism (`-l`) |
| `Frontal` | HX code layout and fetch model, computed from a TX image (`-f`) |
| `Hote`, `Args`, `TX_Run` | system binding, command line, main program |

## Assembling images

fasmg **g.l8vn** (or later) is required. With g.k3dc, `codi_HX` was about ten times slower: its `calminstruction` definitions are the part of fasmg that improved the most.

    fasmg PROG.TXFAS PROG.tx          (includes codi_TX.finc)
    fasmg PROG.HXFAS PROG.hx          (includes codi_HX.finc)

On TLALOC (611,512 LLIR instructions), with fasmg g.l8vn:

| codi | passes | time | image |
|---|---|---|---|
| codi_HX | 17 | 37 s | 4.29 MB, of which 1.57 MB of code and 2.45 MB of instruction table |
| codi_TX | 16 | 42 s | 12.5 MB |
| codi_x86_64L | 18 | 62 s | 11.3 MB |

Most passes come from the lazy assembly of procedures: a procedure called forward is only discovered in the next pass.

`HX_SANS_TABLE = 1`, placed before the include of `codi_HX.finc`, removes the instruction table: the image then contains only the header, the code and the data (about 1.84 MB for TLALOC). This is the image of the real machine, and its code is byte-for-byte identical. `tx_run` executes it too, but without checking instruction starts, and with an LLIR count equal to the HX count.

## Usage

    tx_run [-p report|-] [-l] [-f] [-n limit] [-c costack_MiB] [-t heap_MiB] [-d stack_MiB] image

| option | effect |
|---|---|
| `-p report` | dynamic profile written to the file (`-`: standard error) |
| `-l` | limit study of available parallelism (IPC of idealised models, branch prediction) |
| `-f` | HX code layout (single or dual stream) and fetch model; **TX images of format 3 only** |
| `-n limit` | stops execution after this number of instructions |
| `-c`, `-t`, `-d` | sizes of the co-stack (64 MiB), heap (64 MiB) and data stack (4 MiB) |

Standard output is that of the LLIR program. The exit code is that of SYS_EXIT, or 70 on a fault. A fault is reported with the PC, the instruction and the number of instructions executed. The faults detected are: division by zero, access outside a region, stack overflow, UNLINK 0, level outside the display, illegal code, `-n` limit, and for HX, a reserved opcode or a PC that is not an instruction start. The display has 15 levels (0..14).

## TX format

Little-endian 16-byte record: `op` (1 byte), `lvl` (int8, −1 = address on the stack), 2 reserved bytes, `ofs` (int32), `val` (64 bits: disp, immediate, size, absolute target address or TRAP number).

The image is loaded at 0x400000. A 0x78-byte header precedes the code, which starts at 0x400078 as in x86. The co-stack is placed above the image.

| header | content |
|---|---|
| +0 | `TLALOCTX` |
| +8 | version (1, 2 or 3) |
| +16 | base 0x400000 |
| +24 | entry point 0x400078 |
| +32 | size of code and data |
| +40 | 16 (record size) |
| +48 | CEV: target of failing CHKs (version ≥ 2) |
| +56, +64 | instruction table and number of entries (version 3) |

## HX format

The header has the same layout, with the signature `TLALOCHX`, version 1 and a 0 at +40. The code follows `LLIR_hardware_support_V3.txt`:

- **One-byte opcode**, 0 to 8 bytes of complement. The length depends on the opcode only.
- **Complement stored most significant byte first**, in the order of the format notation. The lvl field is thus always in bits 7..4 of the byte following the opcode.
- **Minimal formats**: FMT 00, then B16/B24 and C24/C32; LI imm4 (0..15, unsigned), then D8 to D64.
- **Branches BR8 to BR32**, relaxed by fasmg. For a forward target, the distance accounts for the size the branch had in the previous pass, a size stored under the target's name.
- **Fallback sequences** for ofs outside 0..255 (ofs > 255 or negative), and replacement sequences for out-of-format CHKs.
- **Differences from TX**: `SYS_EXIT code` assembles to `LI code ; TRAP 0`. `LVA -1, 0` is emitted by no codi, even when its displacement is a symbol that evaluates to 0 at assembly time.

**Instruction table**, at the end of the image: one 32-bit word per HX instruction. Bits 29..0 hold the address relative to 0x400000. Bit 31 (SUITE) marks an instruction that continues the preceding LLIR instruction: fallback sequence, `SYS_EXIT`, CHK sequence. Bit 30 (VIDE) is reserved; it is no longer produced, but is still read for older images. The machine ignores this table. It allows the executor:
- to check that every PC reached is an instruction start; in HX, byte 0x00 is a valid opcode (ET);
- to count the **LLIR** instructions executed: an HX instruction represents 0 (SUITE) or 1.

## Executing HX images

`Decodeur_HX` decodes each instruction once, on its first execution, into a 16-byte record of the TX form (TX code, lvl, ofs, val). It stores the record in a cache indexed by the instruction's address. `Machine` then executes that record with the common semantics. At decoding:
- lvl = 1111 becomes −1, and FMT 00 gives lvl = −1, disp = 0, ofs = 0;
- branch and CALL displacements become absolute addresses;
- for UBFXI, SBFXI and BFII, val = lsb and ofs = w; for LEXCMP, ofs = size and lvl = 1 if the components are signed.

For TLALOC, 611,711 distinct instructions are decoded for 5.27 billion executions. HX execution costs within 4% of TX (100.6 s against 96.7 s).

A few TX instructions share the same HX encoding, and the HX report shows them under a single name: LA, SA and LIA appear as LQ, SQ and LIQ; LCA, LSPA and LIF as LI; LIVA −1,0,0 as LQ.

## Profile (`-p`)

The report gives:
- the dynamic mix per code and the adjacent pairs;
- the candidate fusions and peephole reductions;
- the B, C, immediate, branch and CHK formats;
- accesses per level, TRAP services and maximum depths;
- conditional branches taken and not taken;
- diagnostics (non-normalised booleans, shifts ≥ 64, fields of width 0 or 64).

For a TX image, byte counts and formats are those of the encoding model, and branch ranges are estimated. For an HX image, the report adds **exact measurements**: LLIR instructions represented, code bytes actually read, argument bytes, and the actual branch format (BR8 to BR32).

## Tools (outils/)

| tool | role |
|---|---|
| `hx_verif.py SPEC PROG.tx PROG.hx codi_TX.finc [-l]` | Independent checker of codi_HX: it builds its decoding table from the specification. It checks the length and minimal format of every instruction, the targets, the table flags, and the instruction-by-instruction correspondence with the TX image. `-l` gives a disassembled listing. |
| `gen_hx_codes.py SPEC tx_codes.ads > hx_codes.ads` | Regenerates the Ada decoding table after a change to the opcode table. |
| `banc_hx.sh tx_run test…` | Runs each test in TX and in HX, and compares outputs, exit codes and counts (LLIR count of HX = TX count). |
| `llir_reecrire.py file.FINC…` | Rewritings the front end will have to perform itself: range checks into CHK, narrow loads, immediate forms of bit fields, address peephole, removal of the textual null LVA. |

## Validation

- **TX/HX test bench**: 16 tests (`CORPS`, `CHK`, `BRANCH`, `EXPO`, `REPLIS`, `BANC`, `PROF`, `ECARTS`, `NOMS`, `SSET`, `ENCODAGE`, `INSERTION`, `LCA`, `RELAX`, `VIDE`, `ZERO`). All pass `hx_verif.py`. Outputs, exit codes and TX/HX counts are identical.
- **Tests with a specific purpose**: `ENCODAGE` covers the boundaries of every format; `REPLIS` the fallback sequences, executed and compared with x86 (`REPLIS.attendu`); `INSERTION` and `RELAX` branch relaxation with lazy assembly; `ZERO` the LVA whose symbol evaluates to 0.
- **x86 reference**: `CORPS` (81 lines, `TEST.attendu`), `CHK` and `REPLIS` give the same outputs in x86, TX and HX. `DIS_BONJOUR` is byte-for-byte identical to the x86 ELF.
- **Random programs**: 750 random programs (lazy procedures, nested branches) assembled in TX and in HX; all pass, with minimal branches.
- **TLALOC**: `hx_verif` reports CONFORME (611,512 TX instructions, 611,711 HX). The TX and HX runs produce the same `.FINC`. TX executes 5,264,323,193 instructions, and HX 5,270,937,767 instructions representing as many LLIR instructions, with the exception described below.

TLALOC prints its compilation time ("Ok NNNNN msec"): a run longer than 100 s prints one more digit and executes 57 more instructions. Two runs therefore compare exactly only if they fall on the same side of this threshold.

## Known differences from codi_x86_64 (to be fixed in the reference)

1. **CVTFIR**: `cvtsd2si` rounds to even, whereas Ada requires rounding away from zero. 2.5 gives 2 in x86 and 3 in TX and HX.
2. **Comparisons** (CEQ … FCLE): `setcc [rbp]` only writes the low byte of the top of stack. This has no effect as long as the boolean is only consumed by BT/BF or SB. Suggested fix: `setcc al` / `movzx eax, al` / `mov [rbp], rax`.
3. **Open points of the specification**, settled as follows by the interpreter:
   - FEXP with n < 0 returns 1/x**|n| (Ada RM 4.5.6);
   - UBFX and BFI of width 64 return the whole field;
   - shift counts remain modulo 64;
   - division by zero is a reported fault.

## Limitations

- `-f` rejects HX images: it models the HX layout from a TX image.
- The formats in the profile remain those of the TX model (estimates), except for the exact measurements specific to HX.
- GET_CHAR follows x86: ICANON and ECHO are switched off for the duration of the read.

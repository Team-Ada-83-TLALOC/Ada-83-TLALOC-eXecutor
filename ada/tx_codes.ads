--  Codes d'operation du format d'execution TX.
--  Numerotation IDENTIQUE a celle de codi_TX.finc (verifiee a la generation).
package TX_Codes is

   OP_DROP        : constant := 1;
   OP_DUP         : constant := 2;
   OP_OVER        : constant := 3;
   OP_LI          : constant := 4;
   OP_LIF         : constant := 5;
   OP_LCA         : constant := 6;
   OP_LSPA        : constant := 7;
   OP_LVA         : constant := 8;
   OP_LIVA        : constant := 9;
   OP_LB          : constant := 10;
   OP_LW          : constant := 11;
   OP_LD          : constant := 12;
   OP_LQ          : constant := 13;
   OP_LA          : constant := 14;
   OP_ULB         : constant := 15;
   OP_ULW         : constant := 16;
   OP_ULD         : constant := 17;
   OP_LIB         : constant := 18;
   OP_LIW         : constant := 19;
   OP_LID         : constant := 20;
   OP_LIQ         : constant := 21;
   OP_LIA         : constant := 22;
   OP_ULIB        : constant := 23;
   OP_ULIW        : constant := 24;
   OP_ULID        : constant := 25;
   OP_SB          : constant := 26;
   OP_SW          : constant := 27;
   OP_SD          : constant := 28;
   OP_SQ          : constant := 29;
   OP_SA          : constant := 30;
   OP_SIB         : constant := 31;
   OP_SIW         : constant := 32;
   OP_SID         : constant := 33;
   OP_SIQ         : constant := 34;
   OP_SIA         : constant := 35;
   OP_ET          : constant := 36;
   OP_OU          : constant := 37;
   OP_OUX         : constant := 38;
   OP_NON         : constant := 39;
   OP_SHL         : constant := 40;
   OP_SHR         : constant := 41;
   OP_SAR         : constant := 42;
   OP_CLAMP0      : constant := 43;
   OP_NEG         : constant := 44;
   OP_ABS         : constant := 45;
   OP_ADD         : constant := 46;
   OP_SUB         : constant := 47;
   OP_INC         : constant := 48;
   OP_DEC         : constant := 49;
   OP_MUL         : constant := 50;
   OP_DIV         : constant := 51;
   OP_REMI        : constant := 52;
   OP_MODI        : constant := 53;
   OP_UBFX        : constant := 54;
   OP_SBFX        : constant := 55;
   OP_BFI         : constant := 56;
   OP_CVTIX       : constant := 57;
   OP_CVTXI       : constant := 58;
   OP_FADD        : constant := 59;
   OP_FSUB        : constant := 60;
   OP_FMUL        : constant := 61;
   OP_FDIV        : constant := 62;
   OP_FNEG        : constant := 63;
   OP_FABS        : constant := 64;
   OP_FEXP        : constant := 65;
   OP_CVTIF       : constant := 66;
   OP_CVTFI       : constant := 67;
   OP_CVTFIR      : constant := 68;
   OP_CEQ         : constant := 69;
   OP_CNE         : constant := 70;
   OP_CGT         : constant := 71;
   OP_CGE         : constant := 72;
   OP_CLT         : constant := 73;
   OP_CLE         : constant := 74;
   OP_FCEQ        : constant := 75;
   OP_FCNE        : constant := 76;
   OP_FCGT        : constant := 77;
   OP_FCGE        : constant := 78;
   OP_FCLT        : constant := 79;
   OP_FCLE        : constant := 80;
   OP_BRA         : constant := 81;
   OP_BT          : constant := 82;
   OP_BF          : constant := 83;
   OP_CALL        : constant := 84;
   OP_CALLI       : constant := 85;
   OP_RTD         : constant := 86;
   OP_LINK        : constant := 87;
   OP_UNLINK      : constant := 88;
   OP_UNLINKR     : constant := 89;
   OP_CO_VAR      : constant := 90;
   OP_HEAP_ALLOC  : constant := 91;
   OP_EXC_MACH    : constant := 92;
   OP_EXC_RAISE   : constant := 93;
   OP_BLKMOV      : constant := 94;
   OP_BLKCMP      : constant := 95;
   OP_BLKAND      : constant := 96;
   OP_BLKOU       : constant := 97;
   OP_BLKOUX      : constant := 98;
   OP_BLKNOT      : constant := 99;
   OP_LEXCMP      : constant := 100;
   OP_TRAP        : constant := 101;
   OP_CHKB        : constant := 102;
   OP_CHKW        : constant := 103;
   OP_CHKD        : constant := 104;
   OP_CHKQ        : constant := 105;
   OP_CHKUB       : constant := 106;
   OP_CHKUW       : constant := 107;
   OP_CHKUD       : constant := 108;
   OP_CHKIB       : constant := 109;
   OP_CHKIW       : constant := 110;
   OP_CHKID       : constant := 111;
   OP_CHKIQ       : constant := 112;
   OP_CHKUIB      : constant := 113;
   OP_CHKUIW      : constant := 114;
   OP_CHKUID      : constant := 115;
   OP_UBFXI       : constant := 116;
   OP_SBFXI       : constant := 117;
   OP_BFII        : constant := 118;

   Dernier_Code : constant := 118;

   subtype Nom_Code is String (1 .. 10);
   type Table_Noms is array (0 .. Dernier_Code) of Nom_Code;
   Noms : constant Table_Noms :=
     ("ILLEGAL   ", "DROP      ", "DUP       ", "OVER      ", "LI        ", "LIF       ",
       "LCA       ", "LSPA      ", "LVA       ", "LIVA      ", "LB        ", "LW        ",
       "LD        ", "LQ        ", "LA        ", "ULB       ", "ULW       ", "ULD       ",
       "LIB       ", "LIW       ", "LID       ", "LIQ       ", "LIA       ", "ULIB      ",
       "ULIW      ", "ULID      ", "SB        ", "SW        ", "SD        ", "SQ        ",
       "SA        ", "SIB       ", "SIW       ", "SID       ", "SIQ       ", "SIA       ",
       "ET        ", "OU        ", "OUX       ", "NON       ", "SHL       ", "SHR       ",
       "SAR       ", "CLAMP0    ", "NEG       ", "ABS       ", "ADD       ", "SUB       ",
       "INC       ", "DEC       ", "MUL       ", "DIV       ", "REMI      ", "MODI      ",
       "UBFX      ", "SBFX      ", "BFI       ", "CVTIX     ", "CVTXI     ", "FADD      ",
       "FSUB      ", "FMUL      ", "FDIV      ", "FNEG      ", "FABS      ", "FEXP      ",
       "CVTIF     ", "CVTFI     ", "CVTFIR    ", "CEQ       ", "CNE       ", "CGT       ",
       "CGE       ", "CLT       ", "CLE       ", "FCEQ      ", "FCNE      ", "FCGT      ",
       "FCGE      ", "FCLT      ", "FCLE      ", "BRA       ", "BT        ", "BF        ",
       "CALL      ", "CALLI     ", "RTD       ", "LINK      ", "UNLINK    ", "UNLINKR   ",
       "CO_VAR    ", "HEAP_ALLOC", "EXC_MACH  ", "EXC_RAISE ", "BLKMOV    ", "BLKCMP    ",
       "BLKAND    ", "BLKOU     ", "BLKOUX    ", "BLKNOT    ", "LEXCMP    ", "TRAP      ",
       "CHKB      ", "CHKW      ", "CHKD      ", "CHKQ      ", "CHKUB     ", "CHKUW     ", "CHKUD     ",
       "CHKIB     ", "CHKIW     ", "CHKID     ", "CHKIQ     ", "CHKUIB    ", "CHKUIW    ", "CHKUID    ",
       "UBFXI     ", "SBFXI     ", "BFII      ");

   --  Services TRAP (numerotation de LLIR_hardware_support)
   SYS_EXIT           : constant := 0;
   SYS_CLOCK_GETTIME  : constant := 1;
   SYS_PUT_CHAR       : constant := 2;
   SYS_PUT_STR        : constant := 3;
   SYS_GET_CHAR       : constant := 4;
   SYS_GET_STR        : constant := 5;
   SYS_FILE_CREATE    : constant := 6;
   SYS_FILE_OPEN      : constant := 7;
   SYS_FILE_SET_POS   : constant := 8;
   SYS_FILE_GET_POS   : constant := 9;
   SYS_FILE_GET_SIZE  : constant := 10;
   SYS_FILE_WRITE     : constant := 11;
   SYS_FILE_READ      : constant := 12;
   SYS_FILE_CLOSE     : constant := 13;
   SYS_FILE_DELETE    : constant := 14;
   Dernier_Service : constant := 14;

end TX_Codes;

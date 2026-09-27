#!/usr/bin/env python3
"""Genere tx_run/hx_codes.ads (table de decodage des opcodes HX) a partir de la table des
opcodes de LLIR_hardware_support et des codes TX de tx_run/tx_codes.ads.

   gen_hx_codes.py SPEC tx_codes.ads > hx_codes.ads
"""
import re, sys

GENRE = {None: 'G_Aucun', 'B16': 'G_B16', 'B24': 'G_B24', 'C24': 'G_C24', 'C32': 'G_C32', 'D8': 'G_D8',
         'D16': 'G_D16', 'D24': 'G_D24', 'D32': 'G_D32', 'D64': 'G_D64', 'D8_8': 'G_D8_8',
         'BR8': 'G_BR8', 'BR16': 'G_BR16', 'BR24': 'G_BR24', 'BR32': 'G_BR32'}

def main():
    spec_ch, codes_ch = sys.argv[1:3]
    codes = {m.group(1): int(m.group(2)) for m in
             re.finditer(r'^\s*OP_(\w+)\s*:\s*constant\s*:=\s*(\d+)', open(codes_ch).read(), re.M)}
    table = {}
    for ligne in open(spec_ch, encoding='utf-8', errors='replace'):
        m = re.match(r'^(\d+)\t([ABCD])\t(b[01_i]+)\tx\t(.*)$', ligne.rstrip('\r\n'))
        if not m:
            continue
        fam, bits, reste = m.group(2), m.group(3)[1:].replace('_', ''), m.group(4).split(';')[0].split()
        nom, compl = reste[0], None
        for mot in reste[1:]:
            if mot.startswith('['):
                compl = mot.strip('[]')
        if 'i' in bits:                                         # LI imm4
            for i in range(16):
                table[0xD0 + i] = ('G_Imm4', codes['LI'], 'LI imm4')
            continue
        if re.match(r'U?LEXCMP[BWDQ]$', nom):
            code = codes['LEXCMP']
        elif nom == 'RTX':
            continue                                             # sans equivalent TX
        else:
            code = codes[nom]
        table[int(bits, 2)] = (GENRE[compl], code, nom + (' [%s]' % compl if compl else ''))
    print('--  Table de decodage des opcodes HX : GENERE par outils/gen_hx_codes.py a partir de')
    print('--  LLIR_hardware_support (table des opcodes) et de tx_codes.ads. Ne pas modifier a la main.')
    print('--  Pour chaque octet d\'opcode : format du complement et code TX equivalent.')
    print('package HX_Codes is\n')
    print('   type Genre is (G_Illegal, G_Aucun, G_Imm4, G_B16, G_B24, G_C24, G_C32,')
    print('                  G_D8, G_D16, G_D24, G_D32, G_D64, G_D8_8, G_BR8, G_BR16, G_BR24, G_BR32);\n')
    print('   --  octets de complement par genre')
    print('   Longueur_Complement : constant array (Genre) of Natural :=')
    print('     (G_Illegal => 0, G_Aucun => 0, G_Imm4 => 0, G_B16 => 2, G_B24 => 3, G_C24 => 3, G_C32 => 4,')
    print('      G_D8 => 1, G_D16 => 2, G_D24 => 3, G_D32 => 4, G_D64 => 8, G_D8_8 => 2,')
    print('      G_BR8 => 1, G_BR16 => 2, G_BR24 => 3, G_BR32 => 4);\n')
    print('   type Description is record')
    print('      G    : Genre;')
    print('      Code : Integer;                -- code TX (tx_codes.ads), 0 si illegal')
    print('   end record;\n')
    print('   Table : constant array (0 .. 255) of Description := (')
    for k in range(256):
        g, c, nom = table.get(k, ('G_Illegal', 0, 'reserve'))
        print('      %3d => (%-9s, %3d)%s   -- %02X %s' % (k, g, c, ',' if k < 255 else ' ', k, nom))
    print('   );\n')
    print('   Nombre_Opcodes : constant := %d;   -- codes definis, imm4 compte pour 16' % len(table))
    print('\nend HX_Codes;')

main()

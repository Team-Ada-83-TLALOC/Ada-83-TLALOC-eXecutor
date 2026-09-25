# TLALOC — exécution LLIR par interprète (codi_TX + tx_run)

## Principe

`codi_TX.finc` est un codi fasmg qui garde les noms et les paramètres des macros de `codi_x86_64L.finc`. Les `.FINC` produits par le front end s'assemblent donc sans modification. Chaque macro LLIR émet un enregistrement de 16 octets au lieu de code x86 ; `tx_run`, écrit en Ada, exécute l'image obtenue.

Ce format d'exécution est volontairement découplé de l'encodage binaire de `LLIR_hardware_support` : l'interprète dispose de tous les champs de chaque instruction et calcule lui-même la taille qu'elle occuperait dans les deux flux matériels (opcodes, arguments). On peut ainsi faire varier les formats de la spécification sans toucher au codi.

Enregistrement (petit-boutiste) : `op` (1 octet), `lvl` (int8, -1 = adresse sur la pile), 2 octets réservés, `ofs` (int32), `val` (64 bits : disp, imm, taille, adresse absolue de cible ou numéro de TRAP). L'image est chargée à 0x400000 ; un en-tête de 0x78 octets (`TLALOCTX`, version, base, entrée, ASM_SIZE, 16) précède le code, qui commence en 0x400078 comme en x86. La co-pile est placée au-dessus du code.

## Construction

    gnatmake -gnat83 -O2 tx_run.adb          (dans ada/, GNAT 13)

Tout est compilé en mode Ada 83, à deux exceptions près, isolées derrière une spécification Ada 83 :
- le corps d'`Args` (`pragma Ada_95`) : Ada 83 n'a pas d'accès normalisé à la ligne de commande ni au code de sortie ;
- le corps d'`Hote` (`pragma Ada_2012`) : il lie directement write, read, open, close, lseek, unlink, ioctl et clock_gettime. C'est la seule façon de reproduire exactement la sémantique des macros SYS_ de codi_x86 (drapeaux 0x242, mode 0700, valeurs -errno, mode terminal non canonique de GET_CHAR). Une première version en Text_IO/Direct_IO ajoutait un LF final à la sortie standard.

Unités : `Mots` (types 64 bits, conversions), `TX_Codes` (codes et services, numérotation identique à codi_TX), `Memoire` (régions image+co-pile / pile data / tas, accès contrôlés), `Machine` (+ sous-unité `Machine.Trap`), `Profil`, `Hote`, `Args`, `TX_Run`.

## Utilisation

Dans le `.FAS` principal, remplacer l'include de `codi_x86_64L.finc` par `codi_TX.finc`, puis :

    fasmg PROG.TXFAS PROG.tx
    tx_run [-p rapport|-] [-n limite] [-c copile_Mio] [-t tas_Mio] [-d pile_Mio] PROG.tx

La sortie standard est celle du programme LLIR. `-p` écrit le profil dynamique dans un fichier (`-` : sortie d'erreur). Le code de sortie est celui de SYS_EXIT, 70 en cas de faute. Une faute (division par zéro, accès hors région, débordement de pile, UNLINK 0, niveau hors display, code illégal, limite `-n`) est signalée avec le PC, l'instruction et le nombre d'instructions exécutées. Valeurs par défaut : pile data 4 Mio, co-pile 64 Mio, tas 64 Mio. Le display a 15 niveaux (0..14) ; au-delà, c'est une faute.

## Validation (essais/)

- `DIS_BONJOUR` : sortie identique octet pour octet à l'ELF x86 (" Bonjour \r\n"), 2 136 instructions exécutées. `DIS_BONJOUR.FINC` manquait dans l'envoi ; celui d'`essais/` est reconstruit (PUT_LINE_L60 appelé avec le doublet d'une STR).
- `CORPS.FINC` : banc d'essai LLIR assemblé avec les deux codis (`TEST.X86FAS`, `TEST.TXFAS`). Il couvre arithmétique, logique, décalages, champs de bits, virgule fixe (produit sur 128 bits), comparaisons, tailles et extensions B/C, flottants et NaN, blocs, LEXCMP, co-pile, tas, LSPA/CALLI et le déroulage EXC_MACH/EXC_RAISE. Les 81 lignes sont identiques ; la sortie attendue est dans `TEST.attendu`.
- `ECARTS.FINC` : les écarts attendus, qui sont des défauts de la référence x86 (voir plus bas).

## Écarts connus avec codi_x86_64 (à corriger dans la référence)

1. **CVTFIR** : `cvtsd2si` arrondit au pair ; Ada exige l'écart de zéro. 2.5 donne 2 en x86 et 3 en TX.
2. **Comparaisons** (CEQ … FCLE) : `setcc [rbp]` n'écrit que l'octet bas du sommet ; les 7 autres octets gardent ceux de l'opérande gauche. `0x1234500 > 5` donne 0x1234501 en x86. C'est sans effet tant que le booléen n'est consommé que par BT/BF (qui testent AL) ou SB, mais faux dès qu'il est rangé par SD/SQ ou utilisé en arithmétique. Correction suggérée : `setcc al` / `movzx eax, al` / `mov [rbp], rax`.
3. Choix de l'interprète sur les points ouverts de la spécification :
   - FEXP avec n < 0 rend 1/x**|n| (Ada RM 4.5.6) ; la boucle x86 ne se termine pas.
   - UBFX/BFI de largeur 64 donnent le champ complet ; x86 donne 0.
   - Les décalages restent modulo 64, comme en x86.
   - La division par zéro est une faute signalée, là où x86 reçoit SIGFPE.

## Profil (exemple : essais/DIS_BONJOUR.profil.txt)

Le profil contient : le mix dynamique par code ; les octets des deux flux (DIS_BONJOUR : 2,65 octets de code par instruction) ; la répartition des formats B/C/imm/branches (branches estimées : écart ARG pris égal au double de l'écart OP) ; les accès par niveau (81 % au niveau courant) ; les services TRAP ; les profondeurs maximales ; des diagnostics (booléens non normalisés, décalages ≥ 64, champs de largeur 0 ou 64).

Constat sur les formats : les accès C « hors format » de DIS_BONJOUR (27 %) viennent tous de `TEXT_IO._FILE_TYPE`. Son champ `NAME : String(1..256)` vient juste après ID et repousse tous les champs suivants aux décalages 260–291, hors du champ ofs 8 bits de C32. Deux remèdes :
- dans TLALOC, placer les grands tableaux en fin d'enregistrement (profitable aussi en x86) ;
- dans la spécification, élargir l'ofs de C32 à 12 bits.

## Limites actuelles

- Les tailles de branches sont estimées ; SX donne les écarts exacts en statique.
- GET_CHAR suit x86 : ICANON et ECHO sont coupés le temps de la lecture.
- Le rapport ne donne pas encore l'étude de limites d'ILP ; les points d'observation (`Profil.Instruction`, `Profil.Acces`) sont en place pour l'ajouter.

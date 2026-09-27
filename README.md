# Ada_83_TLALOC_eXecutor — exécution de la LLIR de TLALOC (tx_run)

`tx_run` exécute les programmes produits par le compilateur Ada 83 TLALOC sans passer par le code x86. Il accepte deux formats d'image, reconnus à la signature de leur en-tête :

- **TX** (`TLALOCTX`), produit par `codi_TX.finc` : un enregistrement de 16 octets par instruction LLIR. C'est le format d'étude, qui donne à l'interprète tous les champs de chaque instruction.
- **HX** (`TLALOCHX`), produit par `codi_HX.finc` : le **binaire exact de la machine TAHX**, selon `LLIR_hardware_support_V3.txt`. Opcode d'un octet, complément de 0 à 8 octets, 2,41 octets par instruction exécutée sur TLALOC.

Les deux codis gardent les noms et les paramètres des macros de `codi_x86_64L.finc`. Les `.FINC` du front end s'assemblent donc sans modification avec l'un ou l'autre : seul change l'include du codi dans le `.FAS` principal.

Sur TLALOC compilant `expander-expressions.adb`, les exécutions TX et HX produisent un `EXPANDER-EXPRESSIONS.FINC` identique à celui du compilateur natif.

## Construction

    gnatmake -gnat83 -O2 -gnatn tx_run.adb           (mise au point)
    gnatmake -gnat83 -O2 -gnatn -gnatp tx_run.adb    (production)

Tout est compilé en mode Ada 83, à deux exceptions près, isolées derrière une spécification Ada 83 :
- le corps d'`Args` (`pragma Ada_95`) : Ada 83 n'a pas d'accès normalisé à la ligne de commande ni au code de sortie ;
- le corps d'`Hote` (`pragma Ada_2012`) : il lie directement write, read, open, close, lseek, unlink, ioctl et clock_gettime. C'est la seule façon de reproduire exactement la sémantique des macros SYS_ de codi_x86 (drapeaux 0x242, mode 0700, valeurs -errno, mode terminal non canonique de GET_CHAR).

**Unités**

| unité | rôle |
|---|---|
| `Mots` | types 64 bits et conversions |
| `TX_Codes` | codes TX et services TRAP (numérotation identique à codi_TX) |
| `HX_Codes` | table de décodage des 256 octets d'opcode HX : **générée** depuis la spécification par `outils/gen_hx_codes.py`, à ne pas modifier à la main |
| `Memoire` | régions image + co-pile, pile data, tas ; accès contrôlés ; chargement des images TX et HX |
| `Decodeur_HX` | décodage des instructions HX vers la forme canonique de 16 octets |
| `Machine`, `Machine.Trap` | état architectural, boucle d'exécution, sémantique commune, services système |
| `Profil` | profil dynamique (`-p`) |
| `Limites` | étude de limites du parallélisme (`-l`) |
| `Frontal` | disposition du code HX et modèle de chargement, calculés depuis une image TX (`-f`) |
| `Hote`, `Args`, `TX_Run` | liaison système, ligne de commande, programme principal |

## Assemblage des images

fasmg **g.l8vn** (ou plus récent) est nécessaire. Avec g.k3dc, `codi_HX` était environ dix fois plus lent : ses `calminstruction` sont la partie de fasmg qui a le plus progressé.

    fasmg PROG.TXFAS PROG.tx          (include de codi_TX.finc)
    fasmg PROG.HXFAS PROG.hx          (include de codi_HX.finc)

Sur TLALOC (611 512 instructions LLIR), avec fasmg g.l8vn :

| codi | passes | temps | image |
|---|---|---|---|
| codi_HX | 17 | 37 s | 4,29 Mo, dont 1,57 Mo de code et 2,45 Mo de table des instructions |
| codi_TX | 16 | 42 s | 12,5 Mo |
| codi_x86_64L | 18 | 62 s | 11,3 Mo |

La plupart des passes viennent de l'assemblage paresseux des procédures : une procédure appelée vers l'avant n'est découverte qu'à la passe suivante.

`HX_SANS_TABLE = 1`, placé avant l'include de `codi_HX.finc`, supprime la table des instructions : l'image ne contient plus que l'en-tête, le code et les données (environ 1,84 Mo pour TLALOC). C'est l'image de la vraie machine, et le code est identique octet par octet. `tx_run` l'exécute aussi, mais sans vérifier les débuts d'instruction, et avec un compte LLIR égal au compte HX.

## Utilisation

    tx_run [-p rapport|-] [-l] [-f] [-n limite] [-c copile_Mio] [-t tas_Mio] [-d pile_Mio] image

| option | effet |
|---|---|
| `-p rapport` | profil dynamique dans le fichier (`-` : sortie d'erreur) |
| `-l` | étude de limites du parallélisme (IPC de modèles idéalisés, prédiction de branchement) |
| `-f` | disposition du code HX (flux unique ou double) et modèle de chargement ; **image TX de format 3 seulement** |
| `-n limite` | arrête l'exécution après ce nombre d'instructions |
| `-c`, `-t`, `-d` | tailles de la co-pile (64 Mio), du tas (64 Mio) et de la pile data (4 Mio) |

La sortie standard est celle du programme LLIR. Le code de sortie est celui de SYS_EXIT, ou 70 en cas de faute. Une faute est signalée avec le PC, l'instruction et le nombre d'instructions exécutées. Les fautes détectées sont : division par zéro, accès hors région, débordement de pile, UNLINK 0, niveau hors display, code illégal, limite `-n`, et en HX, opcode réservé ou PC qui n'est pas un début d'instruction. Le display a 15 niveaux (0..14).

## Format TX

Enregistrement petit-boutiste de 16 octets : `op` (1 octet), `lvl` (int8, −1 = adresse sur la pile), 2 octets réservés, `ofs` (int32), `val` (64 bits : disp, imm, taille, adresse absolue de cible ou numéro de TRAP).

L'image est chargée à 0x400000. Un en-tête de 0x78 octets précède le code, qui commence en 0x400078 comme en x86. La co-pile est placée au-dessus de l'image.

| en-tête | contenu |
|---|---|
| +0 | `TLALOCTX` |
| +8 | version (1, 2 ou 3) |
| +16 | base 0x400000 |
| +24 | entrée 0x400078 |
| +32 | taille du code et des données |
| +40 | 16 (taille d'enregistrement) |
| +48 | CEV : cible des CHK en échec (version ≥ 2) |
| +56, +64 | table des instructions et nombre d'entrées (version 3) |

## Format HX

L'en-tête a la même disposition, avec la signature `TLALOCHX`, la version 1 et un 0 en +40. Le code suit `LLIR_hardware_support_V3.txt` :

- **Opcode sur un octet**, complément de 0 à 8 octets. La longueur ne dépend que de l'opcode.
- **Complément rangé poids fort en tête**, dans l'ordre de la notation des formats. Le champ lvl est ainsi toujours dans les bits 7..4 de l'octet qui suit l'opcode.
- **Formats minimaux** : FMT 00, puis B16/B24 et C24/C32 ; LI imm4 (0..15, non signé), puis D8 à D64.
- **Branches BR8 à BR32**, relaxées par fasmg. Pour une cible en avant, la distance tient compte de la taille qu'avait la branche à la passe précédente, taille mémorisée sous le nom de la cible.
- **Replis** pour ofs hors de 0..255 (ofs > 255 ou négatif), et séquences de remplacement pour les CHK hors format.
- **Écarts avec TX** : `SYS_EXIT code` s'assemble en `LI code ; TRAP 0`. `LVA -1, 0` n'est émis par aucun codi, y compris quand son déplacement est un symbole qui vaut 0 à l'assemblage.

**Table des instructions**, en fin d'image : un mot de 32 bits par instruction HX. Les bits 29..0 portent l'adresse relative à 0x400000. Le bit 31 (SUITE) marque une instruction qui prolonge l'instruction LLIR précédente : repli, `SYS_EXIT`, séquence CHK. Le bit 30 (VIDE) est réservé ; il n'est plus produit, mais reste lu pour les anciennes images. La machine ignore cette table. Elle permet à l'exécuteur :
- de vérifier que tout PC atteint est un début d'instruction ; en HX, l'octet 0x00 est un opcode valide (ET) ;
- de compter les instructions **LLIR** exécutées : une instruction HX en représente 0 (SUITE) ou 1.

## Exécution des images HX

`Decodeur_HX` décode chaque instruction une seule fois, à sa première exécution, vers un enregistrement de 16 octets de la forme TX (code TX, lvl, ofs, val). Il le range dans un cache indexé par l'adresse de l'instruction. `Machine` exécute ensuite cet enregistrement avec la sémantique commune. Au décodage :
- lvl = 1111 devient −1, et FMT 00 donne lvl = −1, disp = 0, ofs = 0 ;
- les déplacements des branches et de CALL deviennent des adresses absolues ;
- pour UBFXI, SBFXI et BFII, val = lsb et ofs = w ; pour LEXCMP, ofs = taille et lvl = 1 si les composants sont signés.

Pour TLALOC, 611 711 instructions distinctes sont décodées pour 5,27 milliards d'exécutions. Le coût de l'exécution HX est à 4 % près celui de TX (100,6 s contre 96,7 s).

Quelques instructions TX ont le même encodage HX, et le rapport HX les montre sous un seul nom : LA, SA et LIA apparaissent comme LQ, SQ et LIQ ; LCA, LSPA et LIF comme LI ; LIVA −1,0,0 comme LQ.

## Profil (`-p`)

Le rapport donne :
- le mix dynamique par code et les paires adjacentes ;
- les fusions candidates et les réductions par peephole ;
- les formats B, C, immédiats, branches et CHK ;
- les accès par niveau, les services TRAP et les profondeurs maximales ;
- les branchements conditionnels pris et non pris ;
- des diagnostics (booléens non normalisés, décalages ≥ 64, champs de largeur 0 ou 64).

Pour une image TX, les octets et les formats sont ceux du modèle d'encodage, et la portée des branches est estimée. Pour une image HX, le rapport ajoute des **mesures exactes** : instructions LLIR représentées, octets de code réellement lus, octets d'arguments, et format réel des branches (BR8 à BR32).

## Outils (outils/)

| outil | rôle |
|---|---|
| `hx_verif.py SPEC PROG.tx PROG.hx codi_TX.finc [-l]` | Vérificateur indépendant de codi_HX : il construit sa table de décodage depuis la spécification. Il contrôle la longueur et le format minimal de chaque instruction, les cibles, les drapeaux de la table, et la correspondance instruction par instruction avec l'image TX. `-l` donne un listing désassemblé. |
| `gen_hx_codes.py SPEC tx_codes.ads > hx_codes.ads` | Régénère la table de décodage Ada après une modification de la table des opcodes. |
| `banc_hx.sh tx_run essai…` | Exécute chaque essai en TX et en HX, et compare sorties, codes de sortie et comptes (compte LLIR du HX = compte TX). |
| `llir_reecrire.py fichier.FINC…` | Réécritures que le front end devra faire lui-même : contrôles d'intervalle vers CHK, charges étroites, formes immédiates des champs de bits, peephole d'adresses, suppression du LVA nul textuel. |

## Validation

- **Banc TX/HX** : 16 essais (`CORPS`, `CHK`, `BRANCH`, `EXPO`, `REPLIS`, `BANC`, `PROF`, `ECARTS`, `NOMS`, `SSET`, `ENCODAGE`, `INSERTION`, `LCA`, `RELAX`, `VIDE`, `ZERO`). Tous sont conformes à `hx_verif.py`. Les sorties, les codes de sortie et les comptes TX et HX sont identiques.
- **Essais à rôle particulier** : `ENCODAGE` couvre les frontières de chaque format ; `REPLIS` les replis, exécutés et comparés à x86 (`REPLIS.attendu`) ; `INSERTION` et `RELAX` la relaxation des branches avec assemblage paresseux ; `ZERO` le LVA de symbole nul.
- **Référence x86** : `CORPS` (81 lignes, `TEST.attendu`), `CHK` et `REPLIS` donnent les mêmes sorties en x86, TX et HX. `DIS_BONJOUR` est identique octet pour octet à l'ELF x86.
- **Tirages aléatoires** : 750 programmes aléatoires (procédures paresseuses, branches imbriquées) assemblés en TX et en HX ; tous sont conformes, avec des branches minimales.
- **TLALOC** : `hx_verif` rend CONFORME (611 512 instructions TX, 611 711 HX). Les exécutions TX et HX produisent le même `.FINC`. Il faut 5 264 323 193 instructions en TX, et 5 270 937 767 instructions HX représentant autant d'instructions LLIR, à l'exception décrite ci-dessous.

TLALOC affiche sa durée de compilation (« Ok NNNNN msec ») : une exécution de plus de 100 s imprime un chiffre de plus et exécute 57 instructions de plus. C'est pourquoi deux exécutions ne se comparent exactement que si elles tombent du même côté de ce seuil.

## Écarts connus avec codi_x86_64 (à corriger dans la référence)

1. **CVTFIR** : `cvtsd2si` arrondit au pair, alors qu'Ada exige l'écart de zéro. 2.5 donne 2 en x86 et 3 en TX et HX.
2. **Comparaisons** (CEQ … FCLE) : `setcc [rbp]` n'écrit que l'octet bas du sommet. C'est sans effet tant que le booléen n'est consommé que par BT/BF ou SB. Correction suggérée : `setcc al` / `movzx eax, al` / `mov [rbp], rax`.
3. **Points ouverts de la spécification**, tranchés ainsi par l'interprète :
   - FEXP avec n < 0 rend 1/x**|n| (Ada RM 4.5.6) ;
   - UBFX et BFI de largeur 64 donnent le champ complet ;
   - les décalages restent modulo 64 ;
   - la division par zéro est une faute signalée.

## Limites

- `-f` refuse les images HX : il modélise la disposition HX à partir d'une image TX.
- Les formats du profil restent ceux du modèle TX (estimations), sauf les mesures exactes propres à HX.
- GET_CHAR suit x86 : ICANON et ECHO sont coupés le temps de la lecture.

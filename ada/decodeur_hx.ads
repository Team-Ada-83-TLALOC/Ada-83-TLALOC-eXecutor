--  Decodeur des images HX (codi_HX.finc, LLIR_hardware_support V3).
--
--  Chaque instruction HX est decodee une seule fois, a sa premiere execution, en un
--  enregistrement de 16 octets de la forme des enregistrements TX (code TX, lvl, ofs, val),
--  range dans un cache indexe par l'adresse de l'instruction. La machine execute ensuite
--  cet enregistrement avec la semantique commune.
--
--  Traductions faites au decodage :
--    lvl = 1111 devient -1 ; FMT 00 donne lvl = -1, disp = 0, ofs = 0 ;
--    les deplacements des branches et de CALL deviennent des adresses absolues ;
--    UBFXI, SBFXI, BFII : val = lsb, ofs = w ; LEXCMP : ofs = taille, lvl = 1 si signe ;
--    LINK : val = taille des locales (non signee) ; UNLINK, UNLINKR : lvl = complement ;
--    TRAP : val = service ; le code de SYS_EXIT est sur la pile (LI code ; TRAP 0).
--
--  Avec la table des instructions de l'image (en-tete +56), tout PC atteint doit etre un
--  debut d'instruction, et chaque instruction porte son poids LLIR : 0 si elle prolonge
--  l'instruction LLIR precedente (drapeau SUITE), 1 + le nombre d'entrees VIDE qui la
--  precedent. Sans table, aucune verification et un poids de 1.
with Interfaces; use Interfaces;
package Decodeur_HX is

   procedure Preparer;                         -- apres Memoire.Charger_Image d'une image HX

   procedure Lire (PC       : Unsigned_64;
                   Op       : out Integer;       -- code TX equivalent
                   Lvl      : out Integer;
                   Ofs      : out Unsigned_64;   -- etendu en signe
                   Val      : out Unsigned_64;
                   Longueur : out Unsigned_64;   -- octets de l'instruction HX
                   Poids    : out Integer);      -- instructions LLIR representees

   function Avec_Table return Boolean;
   function Instructions_Decodees return Natural;

end Decodeur_HX;

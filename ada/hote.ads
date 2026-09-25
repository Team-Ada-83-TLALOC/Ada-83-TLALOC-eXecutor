--  Services du systeme hote rendus a la machine LLIR par TRAP.
--  Specification en Ada 83 ; le corps, seul avec celui d'Args, est ecrit en Ada 2012
--  car il lie directement les appels POSIX (write, read, open, lseek, ioctl...) :
--  c'est la seule maniere de reproduire exactement la semantique de codi_x86_64.
--  Conventions de retour de Linux : valeur >= 0, ou -errno en cas d'echec.
--  Descripteurs : 0 entree standard, 1 sortie standard, 2 sortie d'erreur,
--  3 et au-dela fichiers ouverts par FILE_CREATE / FILE_OPEN.
with Interfaces; use Interfaces;
with Mots; use Mots;
package Hote is

   type Tampon is array (Natural range <>) of Unsigned_8;

   ENOENT : constant := -2;
   EIO    : constant := -5;
   EBADF  : constant := -9;
   EACCES : constant := -13;
   EMFILE : constant := -24;
   EINVAL : constant := -22;

   function Ecrire (Fd : Signe; Donnees : Tampon) return Signe;
   procedure Lire (Fd : Signe; Donnees : in out Tampon; Lus : out Signe);
   procedure Lire_Immediat (Donnees : in out Tampon; Lus : out Signe);   -- entree non canonique

   function Creer     (Nom : String) return Signe;
   function Ouvrir    (Nom : String) return Signe;
   function Fermer    (Fd : Signe) return Signe;
   function Detruire  (Nom : String) return Signe;
   function Positionner (Fd : Signe; Position : Signe) return Signe;
   function Position  (Fd : Signe) return Signe;
   function Taille    (Fd : Signe) return Signe;

   procedure Horloge (Secondes : out Signe; Nanosecondes : out Signe);

   procedure Terminer;           -- ferme les fichiers encore ouverts

end Hote;

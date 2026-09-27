#!/bin/bash
#  Banc TX / HX : memes sorties, meme code de sortie, compte LLIR du HX = compte TX.
#    banc_hx.sh tx_run essai1 essai2 ...   (images essaiN.tx et essaiN.hx a cote)
R=$1; shift; ok=0; ko=0
for f in "$@"; do
  $R -p t.rap $f.tx > t.out 2>t.err; ct=$?
  $R -p h.rap $f.hx > h.out 2>h.err; ch=$?
  nt=$(grep "^instructions executees" t.rap | awk '{print $NF}')
  nh=$(grep "^instructions executees" h.rap | awk '{print $NF}')
  nl=$(grep "instructions LLIR representees" h.rap | awk '{print $NF}')
  oh=$(grep "octets de code HX lus" h.rap | awk '{print $NF}')
  if cmp -s t.out h.out && [ $ct = $ch ] && [ "$nt" = "$nl" ]; then r=OK; ok=$((ok+1)); else r=ECART; ko=$((ko+1)); fi
  printf "%-10s %-5s sortie %3s  TX %10s   HX %10s  LLIR %10s  %s octets HX\n" $f $r $ch "$nt" "$nh" "$nl" "$oh"
  [ $r = ECART ] && { diff t.out h.out | head -5; cat h.err | head -3; }
done
echo "$ok conformes, $ko en ecart"

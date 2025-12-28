
echo '--> Test Menu

0. Exit (x)
1. Menu
2. About
'
select menu in
do
case $REPLY in
x) clear; exit; break;;
0) clear; exit; break;;
1) echo 'menu'; break;;
2) echo 'linex Project'; break;;
*) echo 'What??
Try Again ^_^'; esac; done; 

if [ "$1" = tes ]; then
echo 'tes'
else
echo 'hmm'
fi

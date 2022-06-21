#! /bin/bash
# 
#sudo -i
#cd /root
prev=""
declare -i j=0 
for uu in $(lsblk -o uuid); do
    j=j+1
    if [[ "$prev" == *"$uu" ]]; then
        echo "uuid $uu is in the list of prev uuids so duplicate"
    else
        echo "uuid $uu is unique _so_far_"
    fi
    echo "$i: $uu not in $prev"
    prev="$prev $uu"
done

for kn in $(lsblk -o kname); do
    uu=`lsblk -n -o uuid /dev/$kn
    if [[ "$prev" == *"$uu" ]]; then

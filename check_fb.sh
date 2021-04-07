#/bin/bash
if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "Supply the file containing the names (or numbers) to check and at least one leaked txt"
    exit 1
fi

namesfile=$1
shift

mapfile -t names < $namesfile

echo "Checking..."

for name in "${names[@]}"
do
   echo "$name"
   cat $@ | grep --color=always $name
done

exit 0
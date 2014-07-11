#init
declare -A sshkeys

#vars
admins=("ruben" "sascha")

sshkeys["ruben"]=""
sshkeys["sascha"]=""

#run
echo "Init complete."

REPLY=""
while [ -z "$REPLY" ]; do
	echo ""
	read -p "Enter a hostname: " -r
done
hostname="$REPLY"


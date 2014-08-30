#init
declare -A sshkeys

#vars
admins=("ruben" "sascha" "tobias")

sshkeys["ruben"]="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDA4VjJnNTVDxtLgQqCzOiPWsy0yBNiv32GzzYPPatKYozL8PW5hDhEWg7h8vMs5Ty77U/qijjNr4VRyKKmvDFv907f6Wg/Fnm0a7+DmzZ6M4jdEJgqM3LJc3V81aXB6vXDCpCHB3orIKVB9xz2zaBdcA1A8eNYmy7paiZZPnjnSTGDt+UNMWfKumD9TAj4zyvH3yc1MdeB2WOvWCdxQXnyVEfS/AvAIZtzZA5D2osCPKouTGpjKZXoRYqJoT7X+GltbkopFZ7As9jEMfxG3Rum8oIOrqhNwy4ipahd50RYLhBXEUFvFQpDNadlbeslgTq/P5feX1z41PUR5OgNP8cd maintrw1
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIVP7CBN1orjIvx7OOvAaQ6h461ziDZjjgJSseR1GfPvpFizP80+N+6bhrOs8+sz/BxaO1kr9fpArs+g/NmMQobiiXKKmOcR+Wm1y2/LBOrtotmZZJGVQnSoQwwY9K7xhJMGKL4TlktSusvmja5kg2WAf7vW389oYqTfwVq4TgerpPSihn9vVRfVi0827MNfh5agwRIZ/OgWXd6ka/LDByQ0FtV4npFWAwx4/uWphg2t/g6vR7ZoIt5rBSR/E0VqRGMwSbwlbDbYgJTPJ3/lVCrDtVka2r1fuL5f+VyuyYhobtBwkjD5GusIB82XlvIs4KzFTOGVhPpvrmoFKaN1aJ maintrw2"
sshkeys["sascha"]="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDaN3JkkX8JnNjU8KfzW5VmnHJ53NWsMfTv1RD17HKVTzpGt3kc4tEAbt3yca+zBLQ2QuymAauPnSNxbE+eB+E5xKJgXzYSbujBewNBBKaYamYr0WMhOS4iOSIgNv5RZRa59xKpBenkGrmQUfNN1b9kITlZHSu5pYRS5CCXLoCflrroKPttcW3Bt3mHYkOnw85lndRMY/NJ/1jmTJMsX0mmjYbvDF9YLkvYaQhzQI6eU9nb4z4YB7Vs3ksg3cdE3uHThE5NTXqYe73uL0wUUyYQl3+Ta3brPCqhOCF8WTtHEgk5RMaiQtul8xUhOoy+KPCpZJoUbD8FBIOWiM6LLuN maintsb"
sshkeys["tobias"]="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDW5fdNl1nCgAlr2ybbYkliqH+B/UvaJPXddlYlxNVcEEIMYO4myy26hg1k9pnOKXVxBUyOQo627RbHKB129HK5nksFoFrqzXmh8LKgOR4/yOff8jLYOba4GYynwplsgosR5Jrf7AIJSKfU47dYOQBoTtYTjcVLuaqQzVUkgR6lJBPY9si4o4kmwrjcluwiEsjoVer8qnUhSDtRPQmPMTHGenR56/j4tUEoLHUwkkgcjc/EMh05KDvCD1aOvPm89zptwKg8Hwn4xHKrTzTQSpmQ+KB7tMLi2WZ9ubZgJDajbdqo7a/crGBM2+CiZVbiQAwuEBSvZbr/kiUQ69jjsbar tobias@freifunk-nrw.de"

archfr_repo='
[archlinuxfr]
SigLevel = Optional TrustAll
Server = http://repo.archlinux.fr/$arch'
locale_conf='LANG=de_DE.UTF-8
LC_CTYPE="de_DE.UTF-8"
LC_NUMERIC="de_DE.UTF-8"
LC_TIME="de_DE.UTF-8"
LC_COLLATE="de_DE.UTF-8"
LC_MONETARY="de_DE.UTF-8"
LC_MESSAGES="de_DE.UTF-8"
LC_PAPER="de_DE.UTF-8"
LC_NAME="de_DE.UTF-8"
LC_ADDRESS="de_DE.UTF-8"
LC_TELEPHONE="de_DE.UTF-8"
LC_MEASUREMENT="de_DE.UTF-8"'

echo "Init complete."

#check preconditions
echo "Checking internet-connection..."

ping -q 8.8.8.8 -c 4 -i 1 -W 5 >/dev/null 2>&1
if test $? -ne 0; then
    echo "ping failed.";exit 1
fi

ping -q google.com -c 4 -i 1 -W 5 >/dev/null 2>&1
if test $? -ne 0; then
    echo "DNS-resolution failed.";exit 1
fi

maindevice=""
no_dev=0
[ -b /dev/sda ] && maindevice="/dev/sda"&&no_dev+=1
[ -b /dev/vda ] && maindevice="/dev/vda"&&no_dev+=1
[ -b /dev/hda ] && maindevice="/dev/hda"&&no_dev+=1

if [ $no_dev -gt 1 ]; then
	echo "more than one maindevice is not supported.";exit 1
fi
unset no_dev

#run

REPLY=""
while [ -z "$REPLY" ]; do
	echo ""
	read -p "Enter a hostname: " -r
done
hostname="$REPLY"
unset REPLY

echo "creating partion..."
parted -s -- $maindevice mklabel msdos
parted -a optimal -s -- $maindevice mkpart primary ext4 1% 99%FREE #btrfs not supported here

mainpartition=$(echo "$maindevice")1

echo "creating and mounting new filesystem..."
mkfs.btrfs -f -L root $mainpartition
mount $mainpartition /mnt -O rw,noatime,recovery,compress=zlib,autodefrag,discard,space_cache,inode_cache,nossd
echo "install basic system..."
pacstrap /mnt base base-devel grub
echo "generating fstab entrys..."
genfstab -Up /mnt >> /mnt/etc/fstab

echo "doing chroot, to configure new system..."

arch-chroot /mnt /bin/sh <<EOC
echo $HOSTNAME > /etc/hostname
ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime
sed -i -e 's/#\(de_DE\).UTF-8 UTF-8/\1.UTF-8 UTF-8/' /etc/locale.gen
sed -i -e 's/#\(de_DE\) ISO-8859-1/\1 ISO-8859-1/' /etc/locale.gen
sed -i -e 's/#\(de_DE\)@euro ISO-8859-15/\1@euro ISO-8859-15/' /etc/locale.gen
locale-gen
cat <<EOLC > /etc/locale.conf
$locale_conf
EOLC
echo 'KEYMAP=\"de-latin1\"' > /etc/vconsole.conf
cat <<EOLC >> /etc/pacman.conf
$archfr_repo
EOLC
pacman -Syy
pacman -S yaourt --noconfirm
sed -i -e 's/ -mtune=generic / -mtune=native /g' /etc/makepkg.conf
sed -i -e 's/^#MAKEFLAGS="-j2"/MAKEFLAGS="-j6"/' /etc/makepkg.conf
pkgfile --update
yaourt -S mkinitcpio-btrfs rk-server-basic linux-lts linux-lts-headers --noconfirm
yaourt -Rs linux linux-headers --noconfirm
echo 'KEYMAP="de"' > /etc/vconsole.conf
LISTOFADMINS=""
for admin in \"${admins[@]}\"; do

	useradd -m -g users -G wheel -s /bin/bash $admin
	
	mkdir -p ~$admin/.ssh/
	touch ~$admin/.ssh/authorized_keys
	chown $admin: -R ~$admin/.ssh/
	chmod 700 ~$admin/.ssh/
	chmod 600 ~$admin/.ssh/authorized_keys
	echo \"${sshkeys[\"$admin\"]}\" > ~$admin/.ssh/authorized_keys
	LISTOFADMINS+=\" $admin\"
done

echo -e \"\nAllowUsers$LISTOFADMINS\" >> /etc/ssh/sshd_config;unset LISTOFADMINS
sed -i -e 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sed -i -e 's/#Port 22/Port 1337/' /etc/ssh/sshd_config
sed -i -e 's/#ClientAliveInterval 0/ClientAliveInterval 2/' /etc/ssh/sshd_config
sed -i -e 's/#ClientAliveCountMax 3/ClientAliveCountMax 5/' /etc/ssh/sshd_config
sed -i -e 's/#Banner none/Banner \/etc\/issue/' /etc/ssh/sshd_config
sed -i -e 's/#MaxStartups 10:30:100/MaxStartups 10:30:100/' /etc/ssh/sshd_config
sed -i -e 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords no' /etc/ssh/sshd_config

sed -i -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
passwd -l root

systemctl enable dhcpcd
echo noarp >> /etc/dhcpcd.conf

mkinitcpio -p linux
grub-install $maindevice

sed -i -e 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
EOC
umount /mnt

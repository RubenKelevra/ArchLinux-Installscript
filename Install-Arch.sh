#init
declare -A sshkeys

#vars
admins=("ruben" "sascha")

sshkeys["ruben"]="123"
sshkeys["sascha"]="456"

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
echo "$archfr_repo" >> /etc/pacman.conf
pacman -Syy
pacman -S yaourt --noconfirm
sed -i -e 's/ -mtune=generic / -mtune=native /' /etc/makepkg.conf
yaourt -S mkinitcpio-btrfs rk-server-basic --noconfirm
sed -i -e 's/#\(de_DE\).UTF-8 UTF-8/\1.UTF-8 UTF-8/' /etc/locale.gen
sed -i -e 's/#\(de_DE\) ISO-8859-1/\1 ISO-8859-1/' /etc/locale.gen
sed -i -e 's/#\(de_DE\)@euro ISO-8859-15/\1@euro ISO-8859-15/' /etc/locale.gen
locale-gen
cat $locale_conf > /etc/locale.conf
echo 'KEYMAP="de-latin1"' > /etc/vconsole.conf
passwd -l root

LISTOFADMINS=""
for admin in "${admins[@]}"; do

	useradd -m -g users -G wheel -s /bin/bash $admin
	
	mkdir -p ~$admin/.ssh/
	touch ~$admin/.ssh/authorized_keys
	chown $admin: -R ~$admin/.ssh/
	chmod 700 ~$admin/.ssh/
	chmod 600 ~$admin/.ssh/authorized_keys
	echo "${sshkeys["$admin"]}" > ~$admin/.ssh/authorized_keys
	LISTOFADMINS+=" $admin"
done

echo -e "\nAllowUsers$LISTOFADMINS" >> /etc/ssh/sshd_config;unset LISTOFADMINS
sed -i -e 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sed -i -e 's/#Port 22/Port 1337/' /etc/ssh/sshd_config
sed -i -e 's/#ClientAliveInterval 0/ClientAliveInterval 60/' /etc/ssh/sshd_config
sed -i -e 's/#ClientAliveCountMax 3/ClientAliveCountMax 500/' /etc/ssh/sshd_config
sed -i -e 's/#Banner none/Banner \/etc\/issue/' /etc/ssh/sshd_config
sed -i -e 's/#MaxStartups 10:30:100/MaxStartups 10:30:100/' /etc/ssh/sshd_config
sed -i -e 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords no' /etc/ssh/sshd_config

sed -i -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers

sed -i -e 's/HOOKS="base udev autodetect modconf block filesystems keyboard fsck"/HOOKS="base udev autodetect modconf block filesystems keyboard fsck btrfs_advanced"/' /etc/mkinitcpio.conf

mkinitcpio -p linux
grub-install $maindevice
sed -i -e 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable dhcpcd
echo noarp >> /etc/dhcpcd.conf
EOC
umount /mnt

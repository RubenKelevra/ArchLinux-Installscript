[ -z "$1" ] && (echo "supply a hostname!") && exit 1
hostname="$1"

swap=0
[ ! -z "$2" ] && [ "$2" == "swap" ] && swap=1

extfour=0
[ ! -z "$3" ] && [ "$3" == "ext4" ] && extfour=1

extrarepos='
[archlinuxfr]
SigLevel = Optional TrustAll
Server = http://repo.archlinux.fr/$arch

[demz-repo-core]
Server = http://demizerone.com/$repo/$arch'

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

echo "Updating time..."
ntpdate pool.ntp.org >/dev/null 2>&1
if test $? -ne 0; then
    echo "NTP failed.";exit 1
fi

echo "$extrarepos" >> /etc/pacman.conf
pacman-key -r 5E1ABF240EE7A126 && pacman-key --lsign-key 5E1ABF240EE7A126
pacman -Sy

if [ "$extfour" -eq "0" ]; then
	sed -i -e 's/CheckSpace/#CheckSpace/' /etc/pacman.conf #disable space check (see bug #45070)
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

echo "unmount / unswap any existing partions..."
swapoff -a > /dev/null
umount -l $maindevice* > /dev/null

#run
echo "overwriting any existing MBR/GPT"
dd if=/dev/zero of=$maindevice bs=5M count=10 || exit 1

partprobe || true

echo "creating partion..."
parted -s -- $maindevice mklabel msdos

if [ "$swap" -eq "1" ]; then
  parted -a optimal -s -- $maindevice mkpart primary ext4 4096S 70MB
  parted -a optimal -s -- $maindevice mkpart primary linux-swap 70MB 2070MB
  parted -a optimal -s -- $maindevice mkpart primary ext4 2070MB 99%FREE
  parted $maindevice set 1 boot on
  bootpartition=$(echo "$maindevice")1
  swappartition=$(echo "$maindevice")2
  mainpartition=$(echo "$maindevice")3
else
  parted -a optimal -s -- $maindevice mkpart primary ext4 4096S 70MB
  parted -a optimal -s -- $maindevice mkpart primary ext4 70MB 99%FREE
  parted $maindevice set 1 boot on
  bootpartition=$(echo "$maindevice")1
  mainpartition=$(echo "$maindevice")2
fi
  
echo 'overwriting first 100 MByte of the new partition(s), to remove all existing filesystem-remains...'
if [ "$swap" -eq '1' ]; then
  dd if=/dev/zero of=$swappartition bs=1M count=100 || exit 1
  wipefs --all $swappartition
  echo "swap-partion done."
fi
dd if=/dev/zero of=$bootpartition bs=1M count=50 || exit 1
wipefs --all $bootpartition
echo "boot-partion done."
dd if=/dev/zero of=$mainpartition bs=1M count=100 || exit 1
wipefs --all $mainpartition
echo "root-partion done."

echo "creating and mounting new filesystem(s)..."

if [ "$swap" -eq "1" ]; then
  mkswap $swappartition || exit 1
  swapon $swappartition || exit 1
fi

mkfs.ext4 -L boot $bootpartition || exit 1
if [ "$extfour" -eq "0" ]; then
	zpool export zroot || echo ""
	zpool labelclear -f $mainpartition || echo "labelclear failed, ignoring"
	zpool create zroot $mainpartition || exit 1

	zfs set atime=off zroot
	zfs set compression=gzip-9 zroot
	zfs set dedup=on zroot
	zfs set redundant_metadata=most zroot
	zfs set mountpoint=/ zroot
	zfs set xattr=sa zroot
	zfs set acltype=posixacl zroot
	#zpool set bootfs=zroot zroot

	zpool export zroot

	zpool import -R /mnt zroot
	zpool set cachefile=/etc/zfs/zpool.cache zroot
else
	mkfs.ext4 -L root $mainpartition || exit 1
	mount $mainpartition /mnt -O rw,noatime || exit 1
fi

mkdir -p /mnt/boot
mount $bootpartition /mnt/boot || exit 1
echo "install basic system..."
if [ "$extfour" -eq "0" ]; then
	pacstrap -c /mnt base base-devel grub archzfs-git || exit 1
	cp /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache
else
	pacstrap -c /mnt base base-devel grub || exit 1
fi
echo "generating fstab entrys..."
genfstab -Up /mnt >> /mnt/etc/fstab || exit 1

sed -i -e 's/rw,relatime,data=ordered/rw,data=ordered,noatime,discard/' /mnt/etc/fstab || exit 1
if [ "$swap" -eq "1" ]; then
  sed -i -e 's/defaults/defaults,discard/' /mnt/etc/fstab || exit 1
fi

echo 'KERNELVER=`uname -r` 
LOAD=`uptime | awk -F'\''load average:'\'' '\''{ print $2 }'\''`

# get uptime from /proc/uptime

uptime=$(</proc/uptime)
uptime=${uptime%%.*}

seconds=$(( uptime%60 ))
minutes=$(( uptime/60%60 ))
hours=$(( uptime/60/60%24 ))
days=$(( uptime/60/60/24 ))

UPTIME="$days days $hours:$minutes"

short_hostname=$(echo $HOSTNAME | cut -d"." -f1)

echo "
       /\\                        _     _ _
      /  \\         __ _ _ __ ___| |__ | (_)_ __  _   ___  __
     /'\''   \\       / _\\\`| '\''__/ __| '\''_ \\| | | '\''_ \\| | | \\ \\/ /
    /_- ~ -\\     | (_| | | | (__| | | | | | | | | |_| |>  <
   /        \\     \\__,_|_|  \\___|_| |_|_|_|_| |_|\\__,_/_/\_\\
  /  _- - _ '\''\\
 /_-'\''      '\''-_\\   connected to $short_hostname running Linux $KERNELVER

Machine Load:  $LOAD
Machine Uptime: $UPTIME
                                                                         " > /etc/issue' > /mnt/usr/local/bin/issue_update.sh

echo "writing install-script ..."

echo "admins=(\"maintain\")" > /mnt/install.sh
echo "declare -A sshkeys" >> /mnt/install.sh
echo "sshkeys[\"maintain\"]='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDA4VjJnNTVDxtLgQqCzOiPWsy0yBNiv32GzzYPPatKYozL8PW5hDhEWg7h8vMs5Ty77U/qijjNr4VRyKKmvDFv907f6Wg/Fnm0a7+DmzZ6M4jdEJgqM3LJc3V81aXB6vXDCpCHB3orIKVB9xz2zaBdcA1A8eNYmy7paiZZPnjnSTGDt+UNMWfKumD9TAj4zyvH3yc1MdeB2WOvWCdxQXnyVEfS/AvAIZtzZA5D2osCPKouTGpjKZXoRYqJoT7X+GltbkopFZ7As9jEMfxG3Rum8oIOrqhNwy4ipahd50RYLhBXEUFvFQpDNadlbeslgTq/P5feX1z41PUR5OgNP8cd r1
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIVP7CBN1orjIvx7OOvAaQ6h461ziDZjjgJSseR1GfPvpFizP80+N+6bhrOs8+sz/BxaO1kr9fpArs+g/NmMQobiiXKKmOcR+Wm1y2/LBOrtotmZZJGVQnSoQwwY9K7xhJMGKL4TlktSusvmja5kg2WAf7vW389oYqTfwVq4TgerpPSihn9vVRfVi0827MNfh5agwRIZ/OgWXd6ka/LDByQ0FtV4npFWAwx4/uWphg2t/g6vR7ZoIt5rBSR/E0VqRGMwSbwlbDbYgJTPJ3/lVCrDtVka2r1fuL5f+VyuyYhobtBwkjD5GusIB82XlvIs4KzFTOGVhPpvrmoFKaN1aJ r2
ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAFGe5/7cfDkbssq+byjSC1NEfFRIT9h7q26hKESXl2OSQuNj/vRLXlyF1iz8zwFamg0YSVjWb6KwvydimpfXNp8KQE3DKefEzn85eZMO3igMUl9tlnUQFU8skNFyG0o7aSSvw5P4AF5lFEJWqXT8VIkivU5ejI1Ua62CihwMccZ5LbFsg== r@i3-2014-09-22'" >> /mnt/install.sh
echo "echo '$hostname' > /etc/hostname" >> /mnt/install.sh
echo "sed -i -e 's/CheckSpace/#CheckSpace/' /etc/pacman.conf #disable space check (see bug #45070)" >> /mnt/install.sh
echo "ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime" >> /mnt/install.sh
echo "sed -i -e 's/#\(de_DE\).UTF-8 UTF-8/\1.UTF-8 UTF-8/' /etc/locale.gen" >> /mnt/install.sh
echo "sed -i -e 's/#\(de_DE\) ISO-8859-1/\1 ISO-8859-1/' /etc/locale.gen" >> /mnt/install.sh
echo "sed -i -e 's/#\(de_DE\)@euro ISO-8859-15/\1@euro ISO-8859-15/' /etc/locale.gen" >> /mnt/install.sh
echo "locale-gen" >> /mnt/install.sh
echo "echo '$locale_conf' > /etc/locale.conf" >> /mnt/install.sh
echo "echo 'KEYMAP=\"de-latin1\"' > /etc/vconsole.conf" >> /mnt/install.sh
echo "echo '$extrarepos' >> /etc/pacman.conf" >> /mnt/install.sh
echo "dirmngr < /dev/null" >> /mnt/install.sh
echo "pacman-key -r 5E1ABF240EE7A126 && pacman-key --lsign-key 5E1ABF240EE7A126" >> /mnt/install.sh
echo "pacman -Syy" >> /mnt/install.sh
echo "pacman -S yaourt --noconfirm" >> /mnt/install.sh
echo "sed -i -e 's/ -mtune=generic / -mtune=native /g' /etc/makepkg.conf" >> /mnt/install.sh
echo "LISTOFADMINS=''"  >> /mnt/install.sh
echo 'for admin in "${admins[@]}"; do' >> /mnt/install.sh
echo ""  >> /mnt/install.sh
echo '    useradd -m -g users -G wheel -s /bin/bash $admin'  >> /mnt/install.sh
echo '    mkdir /home/$admin/.ssh/'  >> /mnt/install.sh
echo '    touch /home/$admin/.ssh/authorized_keys'  >> /mnt/install.sh
echo '    chown $admin: -R /home/$admin/.ssh/'  >> /mnt/install.sh
echo '    chmod 700 /home/$admin/.ssh/'  >> /mnt/install.sh
echo '    chmod 600 /home/$admin/.ssh/authorized_keys'  >> /mnt/install.sh
echo '    echo "${sshkeys["$admin"]}" > /home/$admin/.ssh/authorized_keys'  >> /mnt/install.sh
echo '    LISTOFADMINS+=" $admin"'  >> /mnt/install.sh
echo 'done' >> /mnt/install.sh
echo 'useradd -m -g users -s /bin/bash user' >> /mnt/install.sh
echo "sed -i -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers" >> /mnt/install.sh
echo 'echo "running yaourt with $admin-user"' >> /mnt/install.sh
echo 'su $admin -c "yaourt -S rk-server-basic --noconfirm"' >> /mnt/install.sh
echo 'rm -fdR /var/cache/pacman/pkg/*' >> /mnt/install.sh
echo 'su $admin -c "yaourt -S rdesktop lxde lxkb_config-git xterm xf86-input-mouse xf86-input-keyboard xf86-video-intel xf86-video-sis xf86-video-vesa --noconfirm"' >> /mnt/install.sh
echo "pkgfile --update" >> /mnt/install.sh
echo "systemctl enable lxdm" >> /mnt/install.sh
echo 'echo -e "\nAllowUsers$LISTOFADMINS" >> /etc/ssh/sshd_config;unset LISTOFADMINS' >> /mnt/install.sh
echo "sed -i -e 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#Port 22/Port 1337/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#ClientAliveInterval 0/ClientAliveInterval 2/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#ClientAliveCountMax 3/ClientAliveCountMax 5/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#Banner none/Banner \/etc\/issue/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#MaxStartups 10:30:100/MaxStartups 10:30:100/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "sed -i -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config" >> /mnt/install.sh
echo "passwd -l root" >> /mnt/install.sh
echo "systemctl enable dhcpcd" >> /mnt/install.sh
echo "systemctl enable sshd" >> /mnt/install.sh
echo "systemctl mask tmp.mount" >> /mnt/install.sh
echo "crontab /crontab"  >> /mnt/install.sh
echo "chmod +x /usr/local/bin/issue_update.sh" >> /mnt/install.sh
echo "echo noarp >> /etc/dhcpcd.conf" >> /mnt/install.sh
echo "mkinitcpio -p linux" >> /mnt/install.sh
echo "grub-install $maindevice --target=i386-pc" >> /mnt/install.sh
echo "sed -i -e 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub" >> /mnt/install.sh
echo "grub-mkconfig -o /boot/grub/grub.cfg" >> /mnt/install.sh
echo "rm -fdR /var/cache/pacman/pkg/*" >> /mnt/install.sh
echo "mv /remotedesktop.desktop /usr/share/applications/" >> /mnt/install.sh

echo "0    *   * * * systemd-tmpfiles --clean
0    */2 * * * pacman-optimize
*/1  *   * * * /usr/local/bin/issue_update.sh" > /mnt/crontab


echo "[Desktop Entry]
Name=Remote Desktop
Type=Application
Comment=Connect to a remote desktop
Terminal=false
Exec=/usr/sbin/rdesktop -u user -d domain -P 192.168.0.1:3389
Categories=Systemtools;
GenericName=Remote Desktop" > /mnt/remotedesktop.desktop
 
echo "doing chroot, to configure new system..."

arch-chroot /mnt /bin/sh <<EOC
bash /install.sh
rm /install.sh
rm /crontab
EOC
umount /mnt/boot | exit 0

if [ "$extfour" -eq "0" ]; then 
	zfs umount -a
	zpool export zroot
else
	umount /mnt | exit 0
fi
swapoff -a

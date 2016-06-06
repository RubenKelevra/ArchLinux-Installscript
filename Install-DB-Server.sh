[ -z "$1" ] && (echo "supply a hostname!") && exit 1
hostname="$1"

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

echo "unmount / unswap any existing partions..."
swapoff -a > /dev/null
umount -l $maindevice* > /dev/null

#run
echo "overwriting any existing MBR"
dd if=/dev/zero of=$maindevice bs=512 count=1 || exit 1

partprobe || true

echo "creating partion..."
parted -s -- $maindevice mklabel msdos
parted -a optimal -s -- $maindevice mkpart primary ext4 4096S 500MB
parted -a optimal -s -- $maindevice mkpart primary linux-swap 500M 2500MB
parted -a optimal -s -- $maindevice mkpart primary ext4 2500MB 99%FREE

bootpartition=$(echo "$maindevice")1
swappartition=$(echo "$maindevice")2
mainpartition=$(echo "$maindevice")3

echo "overwriting first 100 MByte of the new partitions, to remove all existing filesystem-remains..." 
dd if=/dev/zero of=$bootpartition bs=1M count=100 || exit 1
echo "boot-partion done."
dd if=/dev/zero of=$swappartition bs=1M count=100 || exit 1
echo "swap-partion done."
dd if=/dev/zero of=$mainpartition bs=1M count=100 || exit 1
echo "root-partion done."

echo "creating and mounting new filesystem..."
mkfs.ext4 -L boot $bootpartition || exit 1
mkswap $swappartition || exit 1
swapon $swappartition || exit 1
mkfs.ext4 -L root $mainpartition || exit 1
mount $mainpartition /mnt -O rw,noatime || exit 1
mkdir /mnt/boot || exit 1
mount $bootpartition /mnt/boot -O rw,noatime || exit 1
echo "install basic system..."
pacstrap /mnt base base-devel grub || exit 1
echo "generating fstab entrys..."
genfstab -Up /mnt >> /mnt/etc/fstab || exit 1

sed -i -e 's/rw,relatime,data=ordered/rw,data=ordered,noatime/' /mnt/etc/fstab || exit 1
sed -i -e 's/defaults/defaults/' /mnt/etc/fstab || exit 1

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

echo "admins=(\"kevin\")" > /mnt/install.sh
echo "declare -A sshkeys" >> /mnt/install.sh
echo "sshkeys[\"kevin\"]='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQClO6Jdbj7HffLDmAoXr/KU7IYnkL/DvJBodE2UdhzROkc6YNSq7Y4xcfS3wHLH8OtPupbIDURwH/XZw2dflwcjxkHgyDPIQzzA988VJpZeT7DJ8AXx0VzZ0MfbIvksVja6eFgSbkvfU54zKloFFU0ml7UMh7WPwzY0kzhzjkiWnRLiTbERggIeeuQCF5HZvqpIr15ss1R0DLWMsLDL32FmM7tqYQRR5DkbD1T8ALIH3VaTcJhkaiqgW6V27Ps6gK/lEQU9JKFNxfhqF+OsK+pngnC0uppw/r265rymfsHa1SfWQxhYRuxZxafldCnZYgMs9KzGK76pziDHv3rGErCL kevinolbrich@Kevins-MacBook-Pro.local'" >> /mnt/install.sh
echo "echo '$hostname' > /etc/hostname" >> /mnt/install.sh
echo "ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime" >> /mnt/install.sh
echo "sed -i -e 's/#\(de_DE\).UTF-8 UTF-8/\1.UTF-8 UTF-8/' /etc/locale.gen" >> /mnt/install.sh
echo "sed -i -e 's/#\(de_DE\) ISO-8859-1/\1 ISO-8859-1/' /etc/locale.gen" >> /mnt/install.sh
echo "sed -i -e 's/#\(de_DE\)@euro ISO-8859-15/\1@euro ISO-8859-15/' /etc/locale.gen" >> /mnt/install.sh
echo "locale-gen" >> /mnt/install.sh
echo "echo '$locale_conf' > /etc/locale.conf" >> /mnt/install.sh
echo "echo 'KEYMAP=\"de-latin1\"' > /etc/vconsole.conf" >> /mnt/install.sh
echo "echo '$archfr_repo' >> /etc/pacman.conf" >> /mnt/install.sh
echo "pacman -Syy" >> /mnt/install.sh
echo "pacman -S yaourt --noconfirm" >> /mnt/install.sh
echo "sed -i -e 's/ -mtune=generic / -mtune=native /g' /etc/makepkg.conf" >> /mnt/install.sh
echo "sed -i -e 's/^#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j4\"/' /etc/makepkg.conf" >> /mnt/install.sh
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
echo "sed -i -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers" >> /mnt/install.sh
echo 'echo "running yaourt with $admin-user"' >> /mnt/install.sh
echo 'su $admin -c "yaourt -S rk-server-basic --noconfirm"' >> /mnt/install.sh
echo "pkgfile --update" >> /mnt/install.sh
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
echo "grub-install $maindevice" >> /mnt/install.sh
echo "sed -i -e 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub" >> /mnt/install.sh
echo "grub-mkconfig -o /boot/grub/grub.cfg" >> /mnt/install.sh

echo "0    *   * * * systemd-tmpfiles --clean
*/15 *   * * * pacman -Syuw --noconfirm
0    */2 * * * pacman-optimize
*/1  *   * * * /usr/local/bin/issue_update.sh" > /mnt/crontab
 


echo "doing chroot, to configure new system..."

arch-chroot /mnt /bin/sh <<EOC
bash /install.sh
read -p "Install passwords manually, then press [Enter] to finish installation..."
rm /install.sh
rm /crontab
EOC
umount /mnt/boot
umount /mnt
swapoff -a
sync
systemctl reboot

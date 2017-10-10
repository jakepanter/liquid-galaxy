#!/bin/bash

cat << "EOM"
 _ _             _     _               _                  
| (_) __ _ _   _(_) __| |   __ _  __ _| | __ ___  ___   _ 
| | |/ _` | | | | |/ _` |  / _` |/ _` | |/ _` \ \/ / | | |
| | | (_| | |_| | | (_| | | (_| | (_| | | (_| |>  <| |_| |
|_|_|\__, |\__,_|_|\__,_|  \__, |\__,_|_|\__,_/_/\_\\__, |
        |_|                |___/                    |___/ 
https://github.com/LiquidGalaxy/liquid-galaxy
https://github.com/LiquidGalaxyLAB/liquid-galaxy
-------------------------------------------------------------

EOM

# Parameters
MASTER=false
MASTER_IP="10.200.144.22"
MASTER_USER=$USER
MASTER_HOME=$HOME
MASTER_PASSWORD="liquid"
LOCAL_USER=$USER
MACHINE_ID="8"
MACHINE_NAME="lg8"
OCTET="42"
GIT_FOLDER_NAME="liquid-galaxy"
GIT_URL="https://github.com/LiquidGalaxyLAB/liquid-galaxy"
NETWORK_INTERFACE=$(/sbin/route -n | grep "^0.0.0.0" | rev | cut -d' ' -f1 | rev)
NETWORK_INTERFACE_MAC=$(ifconfig | grep $NETWORK_INTERFACE | awk '{print $5}')
SSH_PASSPHRASE=""

read -p "Unique number that identifies your Galaxy (octet) (i.e. 42): " OCTET

#
# Pre-start
#

PRINT_IF_NOT_MASTER=""
if [ $MASTER == false ]; then
	PRINT_IF_NOT_MASTER=$(cat <<- EOM

	MASTER_IP: $MASTER_IP
	MASTER_USER: $MASTER_USER
	MASTER_HOME: $MASTER_HOME
	MASTER_PASSWORD: $MASTER_PASSWORD
	EOM
	)
fi

cat << EOM

Liquid Galaxy will be installed with the following configuration:
MASTER: $MASTER
LOCAL_USER: $LOCAL_USER
MACHINE_ID: $MACHINE_ID
MACHINE_NAME: $MACHINE_NAME $PRINT_IF_NOT_MASTER
OCTET (UNIQUE NUMBER): $OCTET
GIT_URL: $GIT_URL 
GIT_FOLDER: $GIT_FOLDER_NAME
NETWORK_INTERFACE: $NETWORK_INTERFACE
NETWORK_MAC_ADDRESS: $NETWORK_INTERFACE_MAC

Is it correct? Press any key to continue or CTRL-C to exit
EOM
read

if [[ $EUID -eq 0 ]]; then
   echo "Do not run it as root!" 1>&2
   exit 1
fi

# Initialize sudo access
sudo -v

#
# General
#

# Update OS
echo "Checking for system updates..."
sudo apt-get -qq update > /dev/null

echo "Upgrading system packages ..."
sudo apt-get -qq upgrade > /dev/null
sudo apt-get -qq dist-upgrade > /dev/null

echo "Installing new packages..."
sudo apt-get install -qq git chromium-browser nautilus openssh-server sshpass squid3 squid-cgi apache2 xdotool unclutter > /dev/null

# OS config tweaks (like disabling idling, hiding launcher bar, ...)
echo "Setting system configuration..."
sudo tee /etc/lightdm/lightdm.conf > /dev/null << EOM
[Seat:*]
autologin-guest=false
autologin-user=$LOCAL_USER
autologin-user-timeout=0
autologin-session=ubuntu
EOM
echo autologin-user=lg >> sudo /etc/lightdm/lightdm.conf
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
echo -e 'Section "ServerFlags"\nOption "blanktime" "0"\nOption "standbytime" "0"\nOption "suspendtime" "0"\nOption "offtime" "0"\nEndSection' | sudo tee -a /etc/X11/xorg.conf > /dev/null
gsettings set org.compiz.unityshell:/org/compiz/profiles/unity/plugins/unityshell/ launcher-hide-mode 1
sudo update-alternatives --set x-www-browser /usr/bin/chromium-browser --quiet
sudo update-alternatives --set gnome-www-browser /usr/bin/chromium-browser --quiet
sudo apt-get remove --purge -qq update-notifier* > /dev/null

#
# Liquid Galaxy
#

# Setup Liquid Galaxy files
echo "Setting up Liquid Galaxy..."
git clone -q $GIT_URL

sudo cp -r $GIT_FOLDER_NAME/earth/ $HOME

sudo cp -r $GIT_FOLDER_NAME/gnu_linux/home/lg/. $HOME

cd $HOME"/dotfiles/"
for file in *; do
    sudo mv "$file" ".$file"
done
sudo cp -r . $HOME
cd - > /dev/null

sudo cp -r $GIT_FOLDER_NAME/gnu_linux/etc/ $GIT_FOLDER_NAME/gnu_linux/patches/ $GIT_FOLDER_NAME/gnu_linux/sbin/ /

sudo chmod 0440 /etc/sudoers.d/42-lg
sudo ln -s /etc/apparmor.d/sbin.dhclient /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/sbin.dhclient
sudo /etc/init.d/apparmor restart > /dev/null
sudo chown -R $LOCAL_USER:$LOCAL_USER $HOME

echo "Starting SSH files sync with master..."
sshpass -p "$MASTER_PASSWORD" scp -o StrictHostKeyChecking=no $MASTER_IP:$MASTER_HOME/ssh-files.zip $HOME/
unzip $HOME/ssh-files.zip -d $HOME/ > /dev/null
sudo cp -r $HOME/ssh-files/etc/ssh /etc/
sudo cp -r $HOME/ssh-files/root/.ssh /root/ 2> /dev/null
sudo cp -r $HOME/ssh-files/user/.ssh $HOME/
sudo rm -r $HOME/ssh-files/
sudo rm $HOME/ssh-files.zip

sudo chmod 0600 $HOME/.ssh/lg-id_rsa
sudo chmod 0600 /root/.ssh/authorized_keys
sudo chmod 0600 /etc/ssh/ssh_host_dsa_key
sudo chmod 0600 /etc/ssh/ssh_host_ecdsa_key
sudo chmod 0600 /etc/ssh/ssh_host_rsa_key
sudo chown -R $LOCAL_USER:$LOCAL_USER $HOME/.ssh


# Network configuration
sudo tee -a "/etc/network/interfaces" > /dev/null << EOM
auto eth0
iface eth0 inet dhcp
EOM
sudo sed -i "s/\(managed *= *\).*/\1true/" /etc/NetworkManager/NetworkManager.conf
echo "SUBSYSTEM==\"net\",ACTION==\"add\",ATTR{address}==\"$NETWORK_INTERFACE_MAC\",KERNEL==\"$NETWORK_INTERFACE\",NAME=\"eth0\"" | sudo tee /etc/udev/rules.d/10-network.rules > /dev/null
sudo sed -i '/lgX.liquid.local/d' /etc/hosts
sudo sed -i '/kh.google.com/d' /etc/hosts
sudo sed -i '/10.42./d' /etc/hosts
sudo tee -a "/etc/hosts" > /dev/null 2>&1 << EOM
10.42.$OCTET.1  lg1
10.42.$OCTET.2  lg2
10.42.$OCTET.3  lg3
10.42.$OCTET.4  lg4
10.42.$OCTET.5  lg5
10.42.$OCTET.6  lg6
10.42.$OCTET.7  lg7
10.42.$OCTET.8  lg8
EOM
sudo sed -i '/10.42./d' /etc/hosts.squid
sudo tee -a "/etc/hosts.squid" > /dev/null 2>&1 << EOM
10.42.$OCTET.1  lg1
10.42.$OCTET.2  lg2
10.42.$OCTET.3  lg3
10.42.$OCTET.4  lg4
10.42.$OCTET.5  lg5
10.42.$OCTET.6  lg6
10.42.$OCTET.7  lg7
10.42.$OCTET.8  lg8
EOM
sudo tee "/etc/iptables.conf" > /dev/null << EOM
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [43616:6594412]
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -p tcp -m multiport --dports 22 -j ACCEPT
-A INPUT -s 10.42.0.0/16 -p udp -m udp --dport 161 -j ACCEPT
-A INPUT -s 10.42.0.0/16 -p udp -m udp --dport 3401 -j ACCEPT
-A INPUT -p tcp -m multiport --dports 81,8111 -j ACCEPT
-A INPUT -s 10.42.$OCTET.0/24 -p tcp -m multiport --dports 80,89,3128,3130,8086 -j ACCEPT
-A INPUT -s 10.42.$OCTET.0/24 -p udp -m multiport --dports 80,89,3128,3130,8086 -j ACCEPT
-A INPUT -s 10.42.$OCTET.0/24 -p tcp -m multiport --dports 9335 -j ACCEPT
-A INPUT -s 10.42.$OCTET.0/24 -d 10.42.$OCTET.255/32 -p udp -j ACCEPT
-A INPUT -j DROP
-A FORWARD -j DROP
COMMIT
*nat
:PREROUTING ACCEPT [52902:8605309]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [358:22379]
:POSTROUTING ACCEPT [358:22379]
COMMIT
EOM

# Launch on boot
mkdir -p $HOME/.config/autostart/
echo -e "[Desktop Entry]\nName=LG\nExec=bash "$HOME"/bin/startup-script.sh\nType=Application" > $HOME"/.config/autostart/lg.desktop"
echo -e "[Desktop Entry]\nName=Touchkiosk\nExec=chromium-browser --noerrdialogs --kiosk --incognito --disable-web-security --user-data-dir http://localhost:4200/search" > $HOME"/.config/autostart/touchkiosk.desktop"


# Cleanup
sudo rm -r $GIT_FOLDER_NAME

#
# Global cleanup
#

echo "Cleaning up..."
sudo apt-get -qq autoremove > /dev/null

echo "Liquid Galaxy installation completed! :-)"
echo "Press any key to reboot now"
read
reboot

exit 0

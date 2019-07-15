######################################################################################
# install_freepbx.sh
# Description: The following script will install FreePBX on CentOS 7.
#              Asterick Version: 15
#              FreePBX Version: 13
#
# Author: Joshua Weigand
# Last Modified: July 15, 2019
######################################################################################
# Before installation disable SELINUX
# 
# sed -i 's/\(^SELINUX=\).*/\SELINUX=disabled/' /etc/sysconfig/selinux
# sed -i 's/\(^SELINUX=\).*/\SELINUX=disabled/' /etc/selinux/config
#
# Reboot System
######################################################################################

# Check for root user
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Update System
yum -y update
yum -y groupinstall core base "Development Tools"

# Add Asterisk User
adduser asterisk -M -c "Asterisk User"

if [ ! -d "/home/asterisk" ]; then
  mkhomedir_helper asterisk
fi

# Firewalld Basic Configuration
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --reload

# Install Additional Required Dependencies
yum -y install lynx tftp-server unixODBC mysql-connector-odbc mariadb-server mariadb \
  httpd ncurses-devel sendmail sendmail-cf sox newt-devel libxml2-devel libtiff-devel \
  audiofile-devel gtk2-devel subversion kernel-devel git crontabs cronie \
  cronie-anacron wget vim uuid-devel sqlite-devel net-tools gnutls-devel python-devel texinfo \
  libuuid-devel

# Install php 5.6 repositories
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm

# Install php 5.6
yum remove php*
yum install php56w php56w-pdo php56w-mysql php56w-mbstring php56w-pear php56w-process php56w-xml php56w-opcache php56w-ldap php56w-intl php56w-soap

# Install nodejs
curl -sL https://rpm.nodesource.com/setup_8.x | bash -
yum install -y nodejs

# Enable and Start MariaDB
systemctl enable mariadb.service
systemctl start mariadb

# Complete DB Setup
mysql_secure_installation

# Enable and Start Apache
systemctl enable httpd.service
systemctl start httpd.service

# Install Legacy Pear requirements
pear install Console_Getopt

# Download Asterisk
cd /usr/src
wget http://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/dahdi-linux-complete-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/libpri/libpri-current.tar.gz
wget -O jansson.tar.gz https://github.com/akheron/jansson/archive/v2.10.tar.gz
wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-15-current.tar.gz

# Compile and Install jansson
cd /usr/src
tar vxfz jansson.tar.gz
rm -f jansson.tar.gz
cd jansson-*
autoreconf -i
./configure --libdir=/usr/lib64
make
make install

# Compile and install Asterisk
cd /usr/src
tar xvfz asterisk-14-current.tar.gz
rm -f asterisk-*-current.tar.gz
cd asterisk-*
contrib/scripts/install_prereq install
./configure --libdir=/usr/lib64 --with-pjproject-bundled
contrib/scripts/get_mp3_source.sh
make menuselect

############################
### After menu selection ###
############################

make
make install
make config
ldconfig
chkconfig asterisk off

# Set Asterisk ownership permissions.
chown asterisk. /var/run/asterisk
chown -R asterisk. /etc/asterisk
chown -R asterisk. /var/{lib,log,spool}/asterisk
chown -R asterisk. /usr/lib64/asterisk
chown -R asterisk. /var/www/

# A few small modifications to Apache.
sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php.ini
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/httpd/conf/httpd.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
systemctl restart httpd.service

# Download and install FreePBX.
cd /usr/src
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-14.0-latest.tgz
tar xfz freepbx-14.0-latest.tgz
rm -f freepbx-14.0-latest.tgz
cd freepbx
./start_asterisk start
./install -n

# Configure FreePBX to run on startup
cd /etc/systemd/system/

echo "
[Unit]
Description=FreePBX VoIP Server
After=mariadb.service
 
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/fwconsole start -q
ExecStop=/usr/sbin/fwconsole stop -q
 
[Install]
WantedBy=multi-user.target" > freepbx.service

systemctl enable freepbx.service
ln -s '/etc/systemd/system/freepbx.service' '/etc/systemd/system/multi-user.target.wants/freepbx.service'
systemctl start freepbx

systemctl status -l freepbx.service
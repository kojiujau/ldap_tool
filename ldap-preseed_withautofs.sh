#!/bin/bash
## Setting pc/server be ldap client
## Wrote by Ke Chun-Chao in 20140804
## Added AutoMount NFS setting and colorful echo text by Ke Chun-Chao in 20141014

# Setting text color
export red='\e[0;31m'
export orange='\e[0;33m'
export blue='\e[0;34m'
export lightred='\e[1;31m'
export NC='\e[0m' # No Color

# Setting install variables
export LDAP_SERVER_IP=ldap://192.168.11.1
export BASE_DN=dc=test,dc=com,dc=tw
export UTILITYS="ldap-utils libpam-ldap libnss-ldap nslcd"
export AUTOFS_PKGS="autofs autofs-ldap autofs5-ldap"

cat> /tmp/debconf-ldap-preseed.txt <<EOF
ldap-auth-config    ldap-auth-config/ldapns/ldap-server    string    ${LDAP_SERVER_IP}
ldap-auth-config    ldap-auth-config/ldapns/base-dn    string     ${BASE_DN}
ldap-auth-config    ldap-auth-config/ldapns/ldap_version    select    3 
ldap-auth-config    ldap-auth-config/dbrootlogin    boolean    false 
ldap-auth-config    ldap-auth-config/dblogin    boolean    false 
nslcd   nslcd/ldap-uris string  "${LDAP_SERVER_IP}"
nslcd   nslcd/ldap-base string  "${BASE_DN}"
EOF
setting_autofs()
{
	mv /etc/default/autofs /etc/default/autofs.$(date +'%Y-%m-%d')
        cat> /etc/default/autofs <<EOF
MASTER_MAP_NAME="nisMapName=auto.master,${BASE_DN}"
TIMEOUT=300
BROWSE_MODE="no"
LDAP_URI="${LDAP_SERVER_IP}"
SEARCH_BASE="${BASE_DN}"
MAP_OBJECT_CLASS="nisMap"
ENTRY_OBJECT_CLASS="nisObject"
MAP_ATTRIBUTE="nisMapName"
ENTRY_ATTRIBUTE="cn"
VALUE_ATTRIBUTE="nisMapEntry"
USE_MISC_DEVICE="yes"
EOF
        /etc/init.d/autofs restart
}
if [ ! -f /var/run/nslcd/nslcd.pid ] ;then
	if [ -f /tmp/debconf-ldap-preseed.txt ] ;then

		cat /tmp/debconf-ldap-preseed.txt |debconf-set-selections
		apt-get install -y ${UTILITYS}
		auth-client-config -t nss -p lac_ldap
		sed -i '$ i\session required pam_mkhomedir.so skel=/etc/skel umask=0022\' /etc/pam.d/common-session
		update-rc.d nslcd enable
#	/etc/init.d/nslcd restart
		rm /tmp/debconf-ldap-preseed.txt
		echo -e "\n${blue}Please restart OS to enable and startup ldap authentication!!!${NC}\n"
	else  
		echo -e "${lightred}Where the debconf-ldap-preseed.txt ??${NC}\n"
	fi
else
	        echo -e "\n${orange}Local machine already use LDAP authentication!!!${NC}\n"
fi
if [ ! -f /var/run/autofs-running ] ; then
	if [ ! -f /etc/default/autofs ] ;then
		apt-get install -y ${AUTOFS_PKGS}
		setting_autofs
		echo -e "automount: ldap" >> /etc/nsswitch.conf
		/etc/init.d/autofs restart
		echo -e "${blue}\nAutofs already installed in local machine!!!${NC}\n"
	else
	#	setting_autofs
	#	cp -p /etc/nsswitch.conf /etc/nsswitch.conf.$(date +'%Y-%m-%d')
	#	echo -e "automount: ldap" >> /etc/nsswitch.conf
	#	/etc/init.d/autofs restarta
		echo -e "${lightred}\nAutofs already installed in local machine!!!\nIf you want to use autofs,to modify /etc/default/autofs /etc/nsswitch.conf!!!${NC}\n" 
	fi
else
	echo -e "\n${orange}Autofs already installed in local machine!!!${NC}\n"
fi


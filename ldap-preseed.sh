#!/bin/bash
## Setting pc/server be ldap client
## Wrote by Ke Chun-Chao in 20140804

export LDAP_SERVER_IP="ldap://192.168.11.1"
export BASE_DN="dc=test,dc=com,dc=tw"
export UTILITYS="ldap-utils libpam-ldap libnss-ldap nslcd"

cat> debconf-ldap-preseed.txt <<EOF
ldap-auth-config    ldap-auth-config/ldapns/ldap-server    string    ${LDAP_SERVER_IP}
ldap-auth-config    ldap-auth-config/ldapns/base-dn    string     ${BASE_DN}
ldap-auth-config    ldap-auth-config/ldapns/ldap_version    select    3 
ldap-auth-config    ldap-auth-config/dbrootlogin    boolean    false 
ldap-auth-config    ldap-auth-config/dblogin    boolean    false 
nslcd   nslcd/ldap-uris string  ${LDAP_SERVER_IP} 
nslcd   nslcd/ldap-base string  ${BASE_DN}
EOF

if [ -f debconf-ldap-preseed.txt ] ;then

	cat debconf-ldap-preseed.txt |debconf-set-selections
	apt-get install -y ${UTILITYS}
	auth-client-config -t nss -p lac_ldap
	sed -i '$ i\session required pam_mkhomedir.so skel=/etc/skel umask=0022\' /etc/pam.d/common-session
	update-rc.d nslcd enable
	/etc/init.d/nslcd restart

else  
	echo -e "Where the debconf-ldap-preseed.txt ??\n"
fi
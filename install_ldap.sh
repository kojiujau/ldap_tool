#!/bin/bash -x
## Below script is for install LDAP service with Master/Slave replication
## Make sure your setting is same with below.
## If not,you need to modify or mask it.
## 1.The install log in /var/log/install_${PKG}.log.
## 2.Default LDAP_MASTER is 192.168.11.117.If not,you need to change it.
## 3.Default domain base is "dc=example,dc=com,dc=tw".If not,you need change it.
##
## If you have any question or propose,please let me know.
## Wrote by Ke Chun-Chao in 20140715
## Modify by Eric Grosse in 20141030


usage_and_exit() 
{
	echo -e "This script will builds LDAP server.\nWhen LDAP Server be slave,the password must same with master LDAP Server \n"
	echo -e "usage_and_exit: bash $0 [password] [master] |[password] [slave] [master_ip]\n"
	exit 1

}

 if [ $# -eq 0 -o $# -eq 1 ]
 then
	usage_and_exit
 fi

if [ "$2" == "master" -o "$2" == "slave" ]
then
        ROLE=$2
else
	usage_and_exit
fi
if [ "$2" == "slave" -a $# -ne 3 ]
then
	usage_and_exit
fi   

export PKG="slapd"
export LDAP_ADMIN_PASSWD=${1:-"1"}
export LDAP_OLC_ADMIN_PASSWD=$LDAP_ADMIN_PASSWD
export KEY1="${PKG}/password1"
export KEY2="${PKG}/password2"
export SAMBA_DOC="/usr/share/doc/samba-doc/examples/LDAP/"
export BASEDIR=$(dirname $0)
export WORK_DIR="/tmp/"
export UTILITYS="debconf-utils ldap-utils ldapvi tree samba-doc"
export INSTALL_LOG="/var/log/install_${PKG}.log"
export LDAP_MASTER=${3:-"192.168.11.96"}
export BIND_DN="cn=admin,dc=example,dc=com,dc=tw"
export DOMAIN_BASE="dc=example,dc=com,dc=tw"
export BIND_DN="cn=admin,dc=abc,dc=com"
export DOMAIN_BASE="dc=abc,dc=com"

#apt-get update
#apt-get remove -y ${UTILITYS}
#apt-get install -y ${UTILITYS}
#apt-get purge -y ${PKG}
apt-get purge -y apparmor
#apt-get purge slpad
#apt-get install slapd

unset HISTFILE
PASSWD_BASE64=$(slappasswd -s $LDAP_OLC_ADMIN_PASSWD  -h {SSHA} | base64)

reinstall_ldap() 
{
 local password=$1
 apt-get -y purge slapd

debconf-set-selections<<EOF
slapd slapd/password1 password $password
slapd slapd/password2 password $password
EOF

  apt-get -y install slapd
}

###############
# Build the base config


olc_config() 
{
####
# olcRootPW should be SSHA encrypted version of LDAP_OLC_ADMIN_PASSWD
cat > /tmp/config.ldif <<EOF
dn: olcDatabase={-1}frontend,cn=config
changetype: modify
delete: olcAccess

dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,cn=config

dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootPW
olcRootPW:: ${PASSWD_BASE64}

dn: olcDatabase={0}config,cn=config
changetype: modify
delete: olcAccess
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/config.ldif
}

unpack_samba_schema() 
{
 rm -rf ${SAMBA_DOC}samba.schema ${SAMBA_DOC}samba.ldif
 gunzip "${SAMBA_DOC}samba.schema.gz"
 gunzip "${SAMBA_DOC}samba.ldif.gz"
 cp ${SAMBA_DOC}samba.schema ${SAMBA_DOC}samba.ldif /etc/ldap/schema/
 ls /etc/ldap/schema/
}

add_samba_indices()
{
cat> ${WORK_DIR}samba_indices.ldif <<EOF
dn: olcDatabase={1}hdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: uidNumber eq
olcDbIndex: gidNumber eq
olcDbIndex: loginShell eq
olcDbIndex: uid eq,pres,sub
olcDbIndex: memberUid eq,pres,sub
olcDbIndex: uniqueMember eq,pres
olcDbIndex: sambaPrimaryGroupSID eq
olcDbIndex: sambaGroupType eq
olcDbIndex: sambaSIDList eq
olcDbIndex: sambaDomainName eq
olcDbIndex: default sub
EOF

# Couldn't authenticate
#ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ${WORK_DIR}samba_indices.ldif
ldapmodify -x -w$LDAP_ADMIN_PASSWD -D"cn=admin,cn=config"  -f ${WORK_DIR}samba_indices.ldif

}

add_samba_schema()
{
  echo -e "###### Samba Install Begin######"
  unpack_samba_schema

  add_samba_indices

cd ${WORK_DIR}
rm -rf ldif_output
mkdir ldif_output

cat> ${WORK_DIR}schema.conf <<EOF
include /etc/ldap/schema/core.schema
include /etc/ldap/schema/cosine.schema
include /etc/ldap/schema/inetorgperson.schema
include /etc/ldap/schema/nis.schema
include /etc/ldap/schema/samba.schema
EOF


slapcat -f schema.conf -F ldif_output -n 0 -H ldap:///cn={4}samba,cn=schema,cn=config -l cn=samba.ldif

cat> ${WORK_DIR}replace.txt <<EOF
s/cn={4}samba,cn=schema,cn=config/cn=samba,cn=schema,cn=config/g
s/cn: {4}samba/cn: samba/
/structuralObjectClass: olcSchemaConfig/,/modifyTimestamp:.*/d
EOF

sed -f ${WORK_DIR}replace.txt cn\=samba.ldif > cn\=samba.ldif.4
# Couldn't authenticate
#ldapadd -Q -Y EXTERNAL -H ldapi:/// -f cn\=samba.ldif.4
ldapadd   -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config"  -f cn\=samba.ldif.4 -h 127.0.0.1

#Couldn't authenticate
#ldapsearch  -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn={4}samba,cn=schema,cn=config objectClass: olcSchemaConfig


## Tests
ldapsearch  -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config" -b cn={4}samba,cn=schema,cn=config objectClass: olcSchemaConfig 


# Couldn't authenticate

#ldapsearch  -Q -LLL -Y EXTERNAL -H ldapi:/// -b olcDatabase={1}hdb,cn=config 
ldapsearch  -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config"  -b olcDatabase={1}hdb,cn=config 
echo -e "###### Samba Install End ######\n"

}

ldap_acl()
{

echo -e "#### ACL Setting Begin ####"
cat > ${WORK_DIR}olcAccess.ldif <<EOF
dn: olcDatabase={1}hdb,cn=config
changetype: modify
delete: olcAccess
olcAccess: {1}to dn.base="" by * read
-
add: olcAccess
olcAccess: to attrs=userPassword  by dn.base="${BIND_DN}" write  by * auth
olcAccess: to dn.base="ou=people,${DOMAIN_BASE}"  by dn.base="${BIND_DN}" write  by * read
olcAccess: to dn.base="ou=group,${DOMAIN_BASE}"  by dn.base="${BIND_DN}" write  by * read
EOF

# Couldn't authenticate
#ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ${WORK_DIR}olcAccess.ldif
ldapmodify -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config"  -f ${WORK_DIR}olcAccess.ldif

# Couldn't authenticate
#ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b olcDatabase={1}hdb,cn=config olcAccess
ldapsearch -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config"  -b olcDatabase={1}hdb,cn=config olcAccess


echo -e "#### ACL Setting End ####\n"
}

ldap_master()
{


echo -e "#### Replication Master Setting Begin ####"

cat > ${WORK_DIR}/provider_sync.ldif << EOF
# Add indexes to the frontend db.
dn: olcDatabase={1}hdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: entryCSN eq
-
add: olcDbIndex
olcDbIndex: entryUUID eq

#Load the syncprov and accesslog modules.
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
-
add: olcModuleLoad
olcModuleLoad: accesslog

# Accesslog database definitions
dn: olcDatabase={2}hdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcHdbConfig
olcDatabase: {2}hdb
olcDbDirectory: /var/lib/ldap/accesslog
olcSuffix: cn=accesslog
olcRootDN: ${BIND_DN}
olcDbIndex: default eq
olcDbIndex: entryCSN,objectClass,reqEnd,reqResult,reqStart

# Accesslog db syncprov.
dn: olcOverlay=syncprov,olcDatabase={2}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpNoPresent: TRUE
olcSpReloadHint: TRUE

# syncrepl Provider for primary db
dn: olcOverlay=syncprov,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpNoPresent: TRUE

# accesslog overlay definitions for primary db
dn: olcOverlay=accesslog,olcDatabase={1}hdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcAccessLogConfig
olcOverlay: accesslog
olcAccessLogDB: cn=accesslog
olcAccessLogOps: writes
olcAccessLogSuccess: TRUE
# scan the accesslog DB every day, and purge entries older than 7 days
olcAccessLogPurge: 07+00:00 01+00:00
EOF

mkdir /var/lib/ldap/accesslog
cp /var/lib/ldap/DB_CONFIG /var/lib/ldap/accesslog
chown -R openldap:openldap /var/lib/ldap/accesslog


ldapadd   -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config"  -f ${WORK_DIR}/provider_sync.ldif -h 127.0.0.1

# This couldn't authenticate EG 
#ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ${WORK_DIR}/provider_sync.ldif
/etc/init.d/slapd restart |tee -a ${INSTALL_LOG}

# Couldn't authenticate
#ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b olcDatabase={1}hdb,cn=config objectClass
ldapsearch -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config"  -b olcDatabase={1}hdb,cn=config objectClass

echo -e "#### Replication Master Setting End ####\n"
}

ldap_slave()
{

echo -e "#### Replication Slave Setting Begin ####"


cat > ${WORK_DIR}consumer_sync.ldif << EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov

dn: olcDatabase={1}hdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: entryUUID eq
-
replace: olcSyncRepl
olcSyncRepl: rid=123 provider=ldap://${LDAP_MASTER} bindmethod=simple binddn=${BIND_DN} credentials=${PASSWD} searchbase=${DOMAIN_BASE} inte
rval=00:00:03:00 scope=sub schemachecking=off type=refreshAndPersist retry="60 +" syncdata=accesslog
-
replace: olcUpdateRef
olcUpdateRef: ldap://${LDAP_MASTER}
EOF
# This couldn't authenticate
#ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ${WORK_DIR}consumer_sync.ldif
ldapadd   -x -w$LDAP_OLC_ADMIN_PASSWD -D"cn=admin,cn=config"  -f ${WORK_DIR}consumer_sync.ldif -h 127.0.0.1
echo -e "Waiting LDAP Data synchronization....." 
sleep 5
#ldapsearch -z1  -H ldap:///  -D ${BIND_DN} -w ${PASSWD} -LLL -b uid=kec,ou=People,${DOMAIN_BASE}

 if [ "$?" -eq 0 ]
 then
        echo -e "LDAP Data synchronization done!\n"
 else
        echo -e "LDAP Data synchronization not ready!\n"
 fi

echo -e "#### Replication Slave Setting End ####\n"
}




cd $(dirname "$0")
#	source ./install_ldap_funcs.sh
rm -f ${INSTALL_LOG}

reinstall_ldap $LDAP_ADMIN_PASSWD


	
#ldapsearch -z1  -H ldap:///  -D ${BIND_DN} -w ${PASSWD}  -LLL -b ${DOMAIN_BASE}
###### Config install Begin#######

olc_config |tee -a ${INSTALL_LOG}

###### Samba Install Begin######

#add_samba_schema |tee -a ${INSTALL_LOG}

###### Samba Install End ######

###### ACL Install Begin ######

#ldap_acl |tee -a ${INSTALL_LOG}

###### ACL Install End ######

##### Replication Setting Begin #####
 
 
 if [ "$ROLE" == "slave"  ]
 then
	ldap_slave |tee -a ${INSTALL_LOG}
 else
	ldap_master |tee -a ${INSTALL_LOG}
 fi


##### Replication Setting End #####
echo ""
echo "Remember password is cn=admin,$BIND_DN password is  $LDAP_ADMIN_PASSWD"
echo "Remember password is cn=admin,cn=config password is  $LDAP_OLC_ADMIN_PASSWD"

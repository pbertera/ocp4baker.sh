#!/bin/bash


# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_virtualization/getting-started-with-virtualization-in-rhel-8_configuring-and-managing-virtualization#enabling-virtualization-in-rhel8_virt-getting-started
# yum module install virt
# yum install virt-install virt-viewer libguestfs-tools-c-1
# virt-host-validate

# TODO:
# - custom storage pool
# - confgirable mem, disk and cpu vor workers and masters
# - custom name for loadbalancer

BASE_DIR=$HOME/ocp4baker

# define colors in an array
if [[ $BASH_VERSINFO -ge 4 ]]; then
    declare -A c
    c[reset]='\033[0;0m'
    c[grey]='\033[00;30m';  c[GREY]='\033[01;30m';  c[bg_GREY]='\033[40m'
    c[red]='\033[0;31m';    c[RED]='\033[1;31m';    c[bg_RED]='\033[41m'
    c[green]='\E[0;32m';  c[GREEN]='\033[1;32m';  c[bg_GREEN]='\033[42m'
    c[orange]='\033[0;33m'; c[ORANGE]='\033[1;33m'; c[bg_ORANGE]='\033[43m'
    c[blue]='\033[0;34m';   c[BLUE]='\033[1;34m';   c[bg_BLUE]='\033[44m'
    c[purple]='\033[0;35m'; c[PURPLE]='\033[1;35m'; c[bg_PURPLE]='\033[45m'
    c[cyan]='\033[0;36m';   c[CYAN]='\033[1;36m';   c[bg_CYAN]='\033[46m'
fi

############################################
# OCP virtual net configuration
############################################
#BR_NAME="ocpbr0"
#BR_ADDR="192.168.133.1"
#BR_NETMASK="255.255.255.0"
#DHCP_START="192.168.133.10"
#DHCP_END="192.168.133.100"
#NET_NAME="ocp-net"


function askQuestions {
    read -e -p "Please enter the bridge interface name: " -i "$BR_NAME" BR_NAME
    read -e -p "Please enter the bridge address: " -i "$BR_ADDR" BR_ADDR
    read -e -p "Please enter the bridge netmask: " -i "$BR_NETMASK" BR_NETMASK
    read -e -p "Please enter the dhcp pool start IP address: " -i "$DHCP_START" DHCP_START
    read -e -p "Please enter the dhcp pool end IP address: " -i "$DHCP_END" DHCP_END
    read -e -p "Please enter the virtual network name: " -i "$NET_NAME" NET_NAME
    read -e -p "Please enter the additional interface to exclude for DNSmasq: " -i "$EXCEPT_IF" EXCEPT_IF
    read -e -p "Please enter the base domain: " -i "$BASE_DOM" BASE_DOM
    read -e -p "Please enter the cluster name: " -i "$CLUSTER_NAME" CLUSTER_NAME
    read -e -p "Please enter the SSH public key path: " -i "$SSH_KEY" SSH_KEY
    read -e -p "Please paste the pull secret (get it from https://cloud.redhat.com/openshift/install/metal/user-provisioned): " -i "$PULL_SEC" PULL_SEC
    read -e -p "Please enter the Red Hat CoreOS kernel URL: " -i "$RHCOS_INSTALLER_KERNEL"  RHCOS_INSTALLER_KERNEL
    read -e -p "Please enter the Red Hat CoreOS Initramfs: " -i "$RHCOS_INSTALLER_INITRAMFS" RHCOS_INSTALLER_INITRAMFS
    read -e -p "Please enter the Red Hat CoreOS BIOS image: " -i "$RHCOS_BIOS_IMAGE" RHCOS_BIOS_IMAGE
    read -e -p "Please enter the Red Hat CoreOS version: " -i "$RHCOS_VERSION" RHCOS_VERSION
    read -e -p "Please enter the OpenShift client URL: " -i "$OCP_CLIENT" OCP_CLIENT
    read -e -p "Please enter the OpenShift install URL: " -i "$OCP_INSTALL" OCP_INSTALL
    read -e -p "Please enter the HTTP server used for the inigtion files deployment: " -i "$WEB_PORT" WEB_PORT
    read -e -p "Please enter the number of master nodes: " -i "$MASTERS" MASTERS
    read -e -p "Please enter the number of worker nodes: " -i "$WORKERS" WORKERS
    read -e -p "Please enter the RHEL 7.7 guest image download URL: " -i "$RHEL_KVM_IMAGE" RHEL_KVM_IMAGE
    read -e -p "Please enter your RHN username: " -i "$RHNUSER" RHNUSER
    read -e -s -p "Please enter your RHN password: " RHNPASS
    saveConfig
}

function saveConfig {
    cat << EOF>$CONFIG_FILE
# config create by .$0
BR_NAME="$BR_NAME"
BR_ADDR="$BR_ADDR"
BR_NETMASK="$BR_NETMASK"
DHCP_START="$DHCP_START"
DHCP_END="$DHCP_END"
NET_NAME="$NET_NAME"
EXCEPT_IF="$EXCEPT_IF"
BASE_DOM="$BASE_DOM"
CLUSTER_NAME="$CLUSTER_NAME"
SSH_KEY="$SSH_KEY"
PULL_SEC='$PULL_SEC'
RHCOS_INSTALLER_KERNEL="$RHCOS_INSTALLER_KERNEL"
RHCOS_INSTALLER_INITRAMFS="$RHCOS_INSTALLER_INITRAMFS"
RHCOS_BIOS_IMAGE="$RHCOS_BIOS_IMAGE"
RHCOS_VERSION="$RHCOS_VERSION"
OCP_CLIENT="$OCP_CLIENT"
OCP_INSTALL="$OCP_INSTALL"
WEB_PORT="$WEB_PORT"
MASTERS="$MASTERS"
WORKERS="$WORKERS"
RHEL_KVM_IMAGE="$RHEL_KVM_IMAGE"
RHNUSER="$RHNUSER"

EOF
}

bailout() {
    message red ERROR $@
    exit 1
}

message() {
    # usage:
    # print red WARNING You have encounted an error!
    #
    # returns:
    # [ WARNING ] You have encounted an error!
    #
    # use colors in the array above this function
    local COLOR=$1
    local VERB=$2
    local MSG=$(echo $@ | cut -d' ' -f3-)
    [[ "${MSG: -1}" == "?"  ]] && {
        echo -ne " [${c[$COLOR]}$VERB${c[reset]}] ${MSG::-1}"
    } || {
        echo -e " [${c[$COLOR]}$VERB${c[reset]}] $MSG"
    }

}

retry() {
    local max_attempts=${ATTEMPTS-10}
    local timeout=${TIMEOUT-10}
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        "$@"
        exitCode=$?

        if [[ $exitCode == 0 ]]; then
            break
        fi
        message red ERROR "Command failed ($@) attempt $attempt - Retrying in $timeout.."
        sleep $timeout
        attempt=$(( attempt + 1 ))
        timeout=$(( timeout * 2 ))
    done

    if [[ $exitCode != 0 ]]; then
        message red ERROR "Command failed ($@)"
    fi
    return $exitCode
}

function checkReq {
    which virsh &>/dev/null || bailout virsh not installed
    which dnsmasq &>/dev/null || bailout dnsmasq not installed
    which screen &>/dev/null || bailout screen not installed
    which python3 &>/dev/null || bailout python3 not installed
    grep 127.0.0.1 /etc/resolv.conf &> /dev/null || bailout you must use 127.0.0.1 as DNS server
    [ -f "$SSH_KEY" ] || bailout SSH key $SSH_KEY does not exist
}

function createOcpNet {
    message green INFO creating ${NET_NAME}
    cat <<EOF > /tmp/${NET_NAME}.xml
<network>
  <name>${NET_NAME}</name>
  <bridge name="${BR_NAME}"/>
  <forward/>
  <ip address="${BR_ADDR}" netmask="${BR_NETMASK}">
    <dhcp>
      <range start="${DHCP_START}" end="${DHCP_END}"/>
    </dhcp>
  </ip>
</network>
EOF
    virsh net-define /tmp/${NET_NAME}.xml
    virsh net-autostart ${NET_NAME}
    virsh net-start ${NET_NAME}
    systemctl restart libvirtd
    /bin/rm /tmp/${NET_NAME}.xml
}

function dnsmasqSkipVirNet {
    message green INFO configuring dnsmasq
    echo bind-interfaces > ${DNS_DIR}/${CLUSTER_NAME}-except-interfaces.conf
    for x in $(virsh net-list --name); do
        virsh net-info $x | awk '/Bridge:/{print "except-interface="$2}'
    done >> ${DNS_DIR}/${CLUSTER_NAME}-except-interfaces.conf
    for x in $EXCEPT_IF; do
        echo "except-interface=$x"
    done >> ${DNS_DIR}/${CLUSTER_NAME}-except-interfaces.conf
    systemctl restart dnsmasq
    systemctl enable dnsmasq
}

function dnsCheck {
    /bin/cp /etc/hosts hosts.bak
    echo "1.2.3.4 test.local" >> /etc/hosts
    systemctl restart libvirtd
    sleep 5
    
    if [ "1.2.3.4" != "$(dig +short test.local @${HOST_IP})" ]; then
        /bin/mv -f hosts.bak /etc/hosts
        bailout "libvirtd is ignoring /etc/hosts"
    fi
    if [ "test.local." != "$(dig +short -x 1.2.3.4 @${HOST_IP})" ]; then
        /bin/mv -f hosts.bak /etc/hosts
        bailout "libvirt is ignoring /etc/hosts for reverse lookup"
    fi
    /bin/mv -f hosts.bak /etc/hosts

    echo "srv-host=test.local,yayyy.local,2380,0,10" > ${DNS_DIR}/temp-test.conf
    systemctl restart dnsmasq
    sleep 5
    
    if [ "0 10 2380 yayyy.local." != "$(dig +short srv test.local)" ]; then
        /bin/rm ${DNS_DIR}/temp-test.conf
        systemctl restart dnsmasq
        bailout "host is not using dnsmasq properly"
    fi
    if [ "0 10 2380 yayyy.local." != "$(dig +short srv test.local @${HOST_IP})" ]; then
        /bin/rm ${DNS_DIR}/temp-test.conf
        systemctl restart dnsmasq
        bailout "dns server on ${HOST_IP} is not answering properly"
    fi

    message green INFO DNS check passed
    /bin/rm ${DNS_DIR}/temp-test.conf
    systemctl restart dnsmasq
    systemctl restart libvirtd
}

function downloadRHimages {
    message green INFO downloading RHEL KVM guest image
    [ "$RHEL_KVM_IMAGE" == "" ] || curl -o /var/lib/libvirt/images/${CLUSTER_NAME}-lb.qcow2 "$RHEL_KVM_IMAGE"
    
    mkdir rhcos-install
    message green INFO downloading Red Hat CoreOS kernel
    curl -o rhcos-install/vmlinuz "$RHCOS_INSTALLER_KERNEL"
    message green INFO downloading Red Hat CoreOS initramfs
    curl -o rhcos-install/initramfs.img "$RHCOS_INSTALLER_INITRAMFS"
    cat <<EOF > rhcos-install/.treeinfo
[general]
arch = x86_64
family = Red Hat CoreOS
platforms = x86_64
version = ${RHCOS_VERSION}
[images-x86_64]
initrd = initramfs.img
kernel = vmlinuz
EOF
    message green INFO downloading Red Hat CoreOS bios image
    curl -o rhcos-metal.raw.gz "$RHCOS_BIOS_IMAGE"
}

function downloadOCPClient {
    rm -f openshift-client-linux.tar.gz openshift-install-linux.tar.gz
    message green INFO downloading OCP client
    curl -o openshift-client-linux.tar.gz "$OCP_CLIENT"
    message green INFO downloading OCP install
    curl -o openshift-install-linux.tar.gz "$OCP_INSTALL"    
    tar xf openshift-client-linux.tar.gz
    tar xf openshift-install-linux.tar.gz
    rm -f README.md
}

function prepareInstall {
    rm -rf install_dir
    mkdir install_dir
    cat <<EOF > install_dir/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOM}
compute:
- hyperthreading: Disabled
  name: worker
  replicas: 0
controlPlane:
  hyperthreading: Disabled
  name: master
  replicas: $MASTERS
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '${PULL_SEC}'
sshKey: '$(cat $SSH_KEY)'
EOF
    message green INFO created install-config.yaml
   
    message green INFO creating ignition config
    ./openshift-install create ignition-configs --dir=./install_dir
    
    message green INFO starting web server listening on port $WEB_PORT
    screen -XS ${CLUSTER_NAME} quit &>/dev/null
    screen -S ${CLUSTER_NAME} -dm bash -c "python3 -m http.server ${WEB_PORT}"
    
    message green INFO opening $WEB_PORT
    iptables -I INPUT -p tcp -m tcp --dport ${WEB_PORT} -s ${HOST_NET} -j ACCEPT
    sleep 3
    curl -s http://${HOST_IP}:${WEB_PORT} >/dev/null || bailout "local HTTP server not working"
}

function spawnBootstrap {
    message green INFO creating ${CLUSTER_NAME}-bootstrap
    virt-install --name ${CLUSTER_NAME}-bootstrap \
        --disk size=50 --ram 16000 --cpu host --vcpus 4 \
        --os-type linux --os-variant rhel7.0 \
        --network network=${VIR_NET} --noreboot --noautoconsole \
        --location rhcos-install/ \
        --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${HOST_IP}:${WEB_PORT}/rhcos-metal.raw.gz coreos.inst.ignition_url=http://${HOST_IP}:${WEB_PORT}/install_dir/bootstrap.ign"
}

function spawnMasters {
    for i in $(seq 1 $MASTERS); do
        message green INFO creating ${CLUSTER_NAME}-master-${i}
        virt-install --name ${CLUSTER_NAME}-master-${i} \
            --disk size=50 --ram 16000 --cpu host --vcpus 4 \
            --os-type linux --os-variant rhel7.0 \
            --network network=${VIR_NET} --noreboot --noautoconsole \
            --location rhcos-install/ \
            --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${HOST_IP}:${WEB_PORT}/rhcos-metal.raw.gz coreos.inst.ignition_url=http://${HOST_IP}:${WEB_PORT}/install_dir/master.ign"
    done
}

function spawnWorkers {
    for i in $(seq 1 $WORKERS); do
        message green INFO creating ${CLUSTER_NAME}-worker-${i}
        virt-install --name ${CLUSTER_NAME}-worker-${i} \
            --disk size=50 --ram 8192 --cpu host --vcpus 4 \
            --os-type linux --os-variant rhel7.0 \
            --network network=${VIR_NET} --noreboot --noautoconsole \
            --location rhcos-install/ \
            --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${HOST_IP}:${WEB_PORT}/rhcos-metal.raw.gz coreos.inst.ignition_url=http://${HOST_IP}:${WEB_PORT}/install_dir/worker.ign"
    done
}

function spawnLb {
    message green INFO customizing ${CLUSTER_NAME}-lb
    virt-customize -a /var/lib/libvirt/images/${CLUSTER_NAME}-lb.qcow2 \
        --uninstall cloud-init \
        --ssh-inject root:file:$SSH_KEY --selinux-relabel \
        --sm-credentials "${RHNUSER}:password:${RHNPASS}" \
        --sm-register --sm-attach auto --install haproxy

    message green INFO creating ${CLUSTER_NAME}-lb
    virt-install --import --name ${CLUSTER_NAME}-lb \
        --disk /var/lib/libvirt/images/${CLUSTER_NAME}-lb.qcow2,target.dev=vda --memory 1024 --cpu host --vcpus 1 \
        --network network=${VIR_NET} --noreboot --noautoconsole
}

function startAllVM {
    for i in lb bootstrap; do
        message green INFO starting ${CLUSTER_NAME}-$i
        virsh start ${CLUSTER_NAME}-$i
    done
    
    for i in $(seq 1 $MASTERS); do
        message green INFO starting ${CLUSTER_NAME}-master-$i
        virsh start ${CLUSTER_NAME}-master-$i
    done
    
    for i in $(seq 1 $WORKERS); do
        message green INFO starting ${CLUSTER_NAME}-master-$i
        virsh start ${CLUSTER_NAME}-worker-$i
    done
}

function createHosts {
    # bootstrap
    message green INFO "creating DHCP reservation and dns entry for ${CLUSTER_NAME}-bootstrap"
    retry vmHasNetUp "${CLUSTER_NAME}-bootstrap"
    local IP=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1)
    local MAC=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $2}')
    [ "$IP" == "" ] && bailout "${CLUSTER_NAME}-master-${i} doesn't have an IP"
    virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config
    echo "$IP bootstrap.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts

    # masters
    for i in $(seq 1 $MASTERS); do
        message green INFO "creating DHCP reservation and dns entry for ${CLUSTER_NAME}-master-$i"
        retry vmHasNetUp "${CLUSTER_NAME}-master-${i}"
        IP=$(virsh domifaddr "${CLUSTER_NAME}-master-${i}" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1)
        MAC=$(virsh domifaddr "${CLUSTER_NAME}-master-${i}" | grep ipv4 | head -n1 | awk '{print $2}')
        [ "$IP" == "" ] && bailout "${CLUSTER_NAME}-master-${i} doesn't have an IP"
        virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config
        echo "$IP master-${i}.${CLUSTER_NAME}.${BASE_DOM}" \
        "etcd-$((i-1)).${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts
        echo "srv-host=_etcd-server-ssl._tcp.${CLUSTER_NAME}.${BASE_DOM},etcd-$((i-1)).${CLUSTER_NAME}.${BASE_DOM},2380,0,10" >> ${DNS_DIR}/${CLUSTER_NAME}.conf
    done
    
    # workers
    for i in $(seq 1 $WORKERS); do
        message green INFO "creating DHCP reservation and dns entry for ${CLUSTER_NAME}-worker-$i"
        retry vmHasNetUp "${CLUSTER_NAME}-worker-${i}"
        IP=$(virsh domifaddr "${CLUSTER_NAME}-worker-${i}" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1)
        MAC=$(virsh domifaddr "${CLUSTER_NAME}-worker-${i}" | grep ipv4 | head -n1 | awk '{print $2}')
        [ "$IP" == "" ] && bailout "${CLUSTER_NAME}-master-${i} doesn't have an IP"
        virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config
        echo "$IP worker-${i}.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts
    done
    
    # lb
    message green INFO "creating DHCP reservation and dns entry for ${CLUSTER_NAME}-lb"
    retry vmHasNetUp "${CLUSTER_NAME}-lb"
    LBIP=$(virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1)
    [ "$LBIP" == "" ] && bailout "${CLUSTER_NAME}-lb doesn't have an IP"
    MAC=$(virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $2}')
    virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$LBIP'/>" --live --config
    echo "$LBIP lb.${CLUSTER_NAME}.${BASE_DOM}" \
    "api.${CLUSTER_NAME}.${BASE_DOM}" \
    "api-int.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts
    
    echo "address=/apps.${CLUSTER_NAME}.${BASE_DOM}/${LBIP}" >> ${DNS_DIR}/${CLUSTER_NAME}.conf
    systemctl restart dnsmasq 
}

function vmHasNetUp {
    virsh domifaddr "$1" 2>/dev/null | grep ipv4 &>/dev/null 
}

function configLb {
    ssh-keygen -R lb.${CLUSTER_NAME}.${BASE_DOM} &>/dev/null
    ssh-keygen -R $LBIP &>/dev/null
    ssh -o StrictHostKeyChecking=no lb.${CLUSTER_NAME}.${BASE_DOM} true

    ssh lb.${CLUSTER_NAME}.${BASE_DOM} <<EOF

# Allow haproxy to listen on custom ports
semanage port -a -t http_port_t -p tcp 6443
semanage port -a -t http_port_t -p tcp 22623
EOF

cat << EOF > haproxy.cfg
global
  log 127.0.0.1 local2
  chroot /var/lib/haproxy
  pidfile /var/run/haproxy.pid
  maxconn 4000
  user haproxy
  group haproxy
  daemon
  stats socket /var/lib/haproxy/stats

defaults
  mode tcp
  log global
  option tcplog
  option dontlognull
  option redispatch
  retries 3
  timeout queue 1m
  timeout connect 10s
  timeout client 1m
  timeout server 1m
  timeout check 10s
  maxconn 3000
# 6443 points to control plan
frontend ${CLUSTER_NAME}-api *:6443
  default_backend master-api
backend master-api
  balance source
  server bootstrap bootstrap.${CLUSTER_NAME}.${BASE_DOM}:6443 check
EOF
    for i in $(seq 1 $MASTERS); do
        echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOM}:6443 check" >> haproxy.cfg
    done

    cat << EOF >> haproxy.cfg

# 22623 points to control plane
frontend ${CLUSTER_NAME}-mapi *:22623
  default_backend master-mapi
backend master-mapi
  balance source
  server bootstrap bootstrap.${CLUSTER_NAME}.${BASE_DOM}:22623 check
EOF
    for i in $(seq 1 $MASTERS); do
        echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOM}:22623 check" >> haproxy.cfg
    done

    cat << EOF >> haproxy.cfg
# 80 points to worker nodes
frontend ${CLUSTER_NAME}-http *:80
  default_backend ingress-http
backend ingress-http
  balance source
EOF
    for i in $(seq 1 $WORKERS); do
        echo "  server worker-${i} worker-${i}.${CLUSTER_NAME}.${BASE_DOM}:80 check" >> haproxy.cfg
    done

    cat << EOF >> haproxy.cfg
# 443 points to worker nodes
frontend ${CLUSTER_NAME}-https *:443
  default_backend infra-https
backend infra-https
  balance source
EOF
    for i in $(seq 1 $WORKERS); do
        echo "  server worker-${i} worker-${i}.${CLUSTER_NAME}.${BASE_DOM}:443 check" >> haproxy.cfg
    done
    
    scp haproxy.cfg lb.${CLUSTER_NAME}.${BASE_DOM}:/etc/haproxy/haproxy.cfg
    ssh lb.${CLUSTER_NAME}.${BASE_DOM} <<EOF
systemctl start haproxy
systemctl enable haproxy
EOF
}

function installOcp {
    message green INFO installing OpenShift
    ./openshift-install --dir=install_dir wait-for bootstrap-complete
}

function rmBootstrap {
    ssh-keygen -R lb.${CLUSTER_NAME}.${BASE_DOM} &>/dev/null
    ssh-keygen -R $LBIP &>/dev/null
    ssh -o StrictHostKeyChecking=no lb.${CLUSTER_NAME}.${BASE_DOM} <<EOF
sed -i '/bootstrap\.${CLUSTER_NAME}\.${BASE_DOM}/d' /etc/haproxy/haproxy.cfg
systemctl restart haproxy
EOF
    virsh destroy ${CLUSTER_NAME}-bootstrap
    virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage
}

function killScreen {
    screen -S ${CLUSTER_NAME} -X quit
}

function installFinish {
    ./openshift-install --dir=install_dir wait-for install-complete
}

function setEnv {
    echo "# Exectue the following commands to setup the oc client"
    echo "export KUBECONFIG=$PWD/install_dir/auth/kubeconfig"
    echo "alias oc=\'$PWD/oc\'"
    echo "source <(oc completion bash)"
}

function cleanup {
    for i in $(seq 1 $WORKERS); do
        message green INFO removing VM: $i
        virsh destroy ${CLUSTER_NAME}-worker-$i
        virsh undefine ${CLUSTER_NAME}-worker-$i --remove-all-storage
    done
    for i in $(seq 1 $MASTERS); do
        message green INFO removing VM: $i
        virsh destroy ${CLUSTER_NAME}-master-$i
        virsh undefine ${CLUSTER_NAME}-master-$i --remove-all-storage
    done
    message green INFO removing VM: ${CLUSTER_NAME}-lb
    virsh destroy ${CLUSTER_NAME}-lb
    virsh undefine ${CLUSTER_NAME}-lb --remove-all-storage
    
    message green INFO removing VM: ${CLUSTER_NAME}-bootstrap
    virsh destroy ${CLUSTER_NAME}-bootstrap
    virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage
    
    message green INFO removing net ${NET_NAME}
    virsh net-destroy ${NET_NAME}
    virsh net-undefine ${NET_NAME}

    message green INFO cleaning up /etc/hosts
    /bin/cp /etc/hosts /etc/hosts-${CLUSTER_NAME}.${BASE_DOM}
    sed -ie /${CLUSTER_NAME}\.${BASE_DOM}/d /etc/hosts
    /bin/rm ${DNS_DIR}/${CLUSTER_NAME}*

    systemctl restart dnsmasq
}

function listCommands {
    popd &>/dev/null
    grep -e ^function ${BASH_SOURCE[1]} | cut -d \  -f 2
}

usage() {
    [ "$1" != "" ] && message red ERROR $1
    echo "Usage: ${BASH_SOURCE[1]} ls | <clustername>.<basedomain> [command]"
    echo "Available commands:"
    listCommands
}

run() {
    message red INSTALL ">>>>>>>>>> Executing command $@"
    $@
}

if [ "$1" == "ls" ]; then
    ls "$BASE_DIR"
    exit
fi

CLUSTER_NAME=$(echo "$1" | grep -e "\." | cut -d. -f1)
[ "$CLUSTER_NAME" == "" ] && usage "missing cluster name" && exit 1

BASE_DOM=$(echo "$1" | grep -e "\." | cut -d. -f2-)
[ "$BASE_DOM" == "" ] && usage "missing base domain" && exit 1

message blue INFO starting installation of ${CLUSTER_NAME}.${BASE_DOM} OCP Cluster
message blue INFO install files are stored at ${BASE_DIR}/${CLUSTER_NAME}.${BASE_DOM}

mkdir -p ${BASE_DIR}/${CLUSTER_NAME}.${BASE_DOM}
pushd ${BASE_DIR}/${CLUSTER_NAME}.${BASE_DOM} &>/dev/null

CONFIG_FILE=ocp4baker.conf

############################################
# Virtual network for the nodes VMs
############################################
VIR_NET="default" #virtual new where all the VM should be placed
HOST_NET=$(ip -4 a s $(virsh net-info $VIR_NET | awk '/Bridge:/{print $2}') | awk '/inet /{print $2}')
HOST_IP=$(echo $HOST_NET | cut -d '/' -f1)
DNS_DIR="/etc/dnsmasq.d"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

if [ "$2" != "" ]; then
    COMMAND=$2
    shift; shift
    $COMMAND $@ 
else
    run askQuestions
    run checkReq
    run createOcpNet
    run dnsmasqSkipVirNet
    run dnsCheck
    run downloadRHimages
    run downloadOCPClient
    run prepareInstall
    run spawnBootstrap
    run spawnMasters
    run spawnWorkers
    run spawnLb
    run startAllVM
    run createHosts
    run configLb
    run installOcp
    run rmBootstrap
    run killScreen
    run installFinish
    run setEnv
fi

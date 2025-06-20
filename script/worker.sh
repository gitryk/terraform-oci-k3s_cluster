#!/bin/bash
set -euxo pipefail #에러날 시 스크립트 종료

##초기 변수 선언
INDEX="${node_index}"
K3S_TOKEN="${k3s_token}"
MASTER_IP="${master_ip}"
BASTION_IP="${bastion_ip}"
LB_IP="${lb_ip}"
NODE_NAME="${node_name}"
SUBNET_CIDR_PUB="${subnet_cidr_pub}"
SUBNET_CIDR_PRIV="${subnet_cidr_priv}"
DOMAIN="${domain}"
EXTRA_INSTALL="net-tools" #필요한 패키지 기입
K3S_EXEC="--disable traefik --disable servicelb  --token $K3S_TOKEN --node-name $NODE_NAME"
USER_HOME="/home/ubuntu"
GIT_ADDRESS="https://raw.githubusercontent.com/gitryk/terraform-oci-k3s_cluster/refs/heads/main/app"


function disable_ipv6 { #IPv6 비활성화
  echo -e 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1' | tee -a /etc/sysctl.conf
  sysctl -p
}

function dependency { #공통 초기화 함수
  #시간대 설정
  timedatectl set-timezone Asia/Seoul

  #의존성 및 추가 패키지 설치
  apt-get install -y $EXTRA_INSTALL
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
  apt-get update
  apt-get upgrade -y
}

function net_rule_set {
  # 기본 정책 DROP으로 설정
  iptables -F
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT
  

  # loopback 허용
  iptables -A INPUT -i lo -j ACCEPT

  # 이미 확립된 연결 허용
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT #경유하는 패킷일때 적용(안하면 외부에서 접속 불가)

  # Control-plane 노드 간 통신 허용
  iptables -A INPUT -p tcp -s $SUBNET_CIDR_PRIV -m multiport --dports 2379,2380,3260,6443,9500:9600,10250 -j ACCEPT
  iptables -A INPUT -p udp -s $SUBNET_CIDR_PRIV -m multiport --dports 8472 -j ACCEPT

  # Load Balancer 수신 허용 (8080, 8443)
  iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
  iptables -A INPUT -p tcp --dport 8443 -j ACCEPT

  # Bastion 호스트에서의 접근 허용 (SSH, 8080, 8443)
  iptables -A INPUT -p tcp -s $BASTION_IP --dport 22 -j ACCEPT
  iptables -A INPUT -p tcp -s $BASTION_IP --dport 8080 -j ACCEPT
  iptables -A INPUT -p tcp -s $BASTION_IP --dport 8443 -j ACCEPT

  # ICMP 허용 (ping)
  iptables -A INPUT -p icmp -j ACCEPT

  iptables-save > /etc/iptables/rules.v4
}

function install_k3s { #k3s 설치
  net_rule_set
  if [ "$INDEX" -eq "0" ]; then #0 = 메인 서버, 아닐 경우 일반 서버
    echo "[*] Initializing K3s cluster on $NODE_NAME"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--cluster-init $K3S_EXEC" sh -
  
    #메인 서버에 접속 시 kubectl 실행(non-root) 설정
    mkdir -p $USER_HOME/.kube
    cp /etc/rancher/k3s/k3s.yaml $USER_HOME/.kube/config
    chown -R ubuntu:ubuntu $USER_HOME/.kube

    echo 'export KUBECONFIG=$HOME/.kube/config' >> $USER_HOME/.bashrc

    echo "[*] Waiting for K3s API server to become ready..." #클러스터가 완전해 질 떄 까지 대기
      until curl -sk https://127.0.0.1:6443/healthz >/dev/null 2>&1; do
      echo "    ...API not ready yet"
      sleep 5
    done
    echo "[+] K3s API server is ready"

    apt-get install -y helm
    mkdir -p $USER_HOME/app
  else
    echo "[*] Waiting for cluster to be ready..." #메인 서버가 응답할 때까지 대기, -sk 옵션이여야 살아났을떄 401반환
    until curl -sk https://$MASTER_IP:6443/healthz >/dev/null 2>&1; do
      echo "Waiting for master API server at $MASTER_IP..."
      sleep 10
    done

    echo "[*] Joining K3s cluster from $NODE_NAME"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--server https://$MASTER_IP:6443 $K3S_EXEC" sh -
  fi
}

function install_traefik {
  #ingress-traefik 별도 설치
  helm repo add traefik https://traefik.github.io/charts
  helm repo update

  mkdir -p $USER_HOME/app/traefik
  curl -o $USER_HOME/app/traefik/values.yaml $GIT_ADDRESS/traefik/values.yaml
  curl -o $USER_HOME/app/traefik/ingressroute.yaml $GIT_ADDRESS/traefik/ingressroute.yaml

  sed -i "s|domain.com|$DOMAIN|g" $USER_HOME/app/traefik/ingressroute.yaml #디폴트 도메인을 선언한 도메인으로 수정하기

  helm install traefik traefik/traefik \
    --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --namespace traefik-service \
    --create-namespace \
    -f $USER_HOME/app/traefik/values.yaml

  kubectl apply -f $USER_HOME/app/traefik/ingressroute.yaml #helm 레포 설치와 별도로 해야 적용됨
}

function install_longhorn {
  helm repo add longhorn https://charts.longhorn.io
  helm repo update

  curl -o $USER_HOME/app/longhorn.yaml $GIT_ADDRESS/longhorn.yaml

  sed -i "s|domain.com|$DOMAIN|g" $USER_HOME/app/longhorn.yaml #디폴트 도메인을 선언한 도메인으로 수정하기

  helm install longhorn longhorn/longhorn \
    --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --namespace longhorn-system \
    --create-namespace \
    -f $USER_HOME/app/longhorn.yaml
}

disable_ipv6
dependency
install_k3s
if [ "$INDEX" -eq "0" ]; then
  install_traefik
  install_longhorn
fi

set +e #어떤 에러가 발생하더라도 cloud-init 결과물을 홈 디렉토리에 생성하도록 하기
install -o ubuntu -g ubuntu -m 644 /var/log/cloud-init-output.log $USER_HOME/init_log.txt || true
set -e

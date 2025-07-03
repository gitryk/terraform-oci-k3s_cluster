#!/bin/bash
set -euo pipefail #에러날 시 스크립트 종료

##초기 변수 선언
INDEX="${node_index}"
LB_IP="${lb_ip}"
APP_NAME="${app_name}"
NODE_NAME="${node_name}"
DOMAIN="${domain}"
NODE_IP=(${node_ip})
NODE_COUNT="${node_count}"
SUBNET_CIDR=(${subnet_cidr})

TIME_ZONE="Asia/Seoul"
EXTRA_INSTALL="net-tools" #필요한 패키지 기입

K3S_TOKEN="${k3s_token}"
K3S_EXEC="--disable traefik --disable servicelb --token $K3S_TOKEN --node-name $NODE_NAME"

GIT_ADDRESS="https://raw.githubusercontent.com/gitryk/terraform-oci-k3s_cluster/refs/heads/main/app"
USER_HOME="/home/ubuntu"
CROWDSEC_KEY=${crowdsec_key}

#Helm App Variables
HELM_APP_COUNT=3
HELM_APP=("traefik" "longhorn" "crowdsec")
HELM_REPO=("https://traefik.github.io/charts" "https://charts.longhorn.io" "https://crowdsecurity.github.io/helm-charts")


INGRESS_APP=("traefik" "longhorn")

function disable_ipv6 { #IPv6 비활성화
  echo -e 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1' | tee -a /etc/sysctl.conf
  sysctl -p
}

function dependency { #공통 초기화 함수
  #시간대 설정
  timedatectl set-timezone $TIME_ZONE

  #의존성 및 추가 패키지 설치
  apt-get update
  apt-get install -y $EXTRA_INSTALL
  apt-get upgrade -y
}

function install_k3s { #k3s 설치
  if [ "$INDEX" -eq "0" ]; then #0 = 메인 서버, 아닐 경우 일반 서버
    echo "[*] Initializing K3s cluster on $NODE_NAME"
    [ "$NODE_COUNT" -gt 1 ] && K3S_EXEC="$K3S_EXEC --cluster-init" #단일 서버일 경우 HA 선언 제거
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="$K3S_EXEC" sh -
  
    #메인 서버에 접속 시 kubectl 실행(non-root) 설정
    mkdir -p $USER_HOME/.kube
    cp /etc/rancher/k3s/k3s.yaml $USER_HOME/.kube/config
    chown -R ubuntu:ubuntu $USER_HOME/.kube

    echo 'export KUBECONFIG=$HOME/.kube/config' >> $USER_HOME/.bashrc

    echo "[*] Waiting for K3s API server to become ready..." #클러스터가 완전해 질 떄 까지 대기
      until curl -sk https://127.0.0.1:6443/healthz >/dev/null 2>&1; do
      echo "...API not ready yet"
      sleep 5
    done
    echo "[+] K3s API server is ready"
  else
    MASTER_IP=$${NODE_IP[0]}
    echo "[*] Waiting for cluster to be ready..." #메인 서버가 응답할 때까지 대기, -sk 옵션이여야 살아났을떄 401반환
    until curl -sk https://$MASTER_IP:6443/healthz >/dev/null 2>&1; do
      echo "Waiting for master API server at $MASTER_IP..."
      sleep 10
    done

    echo "[*] Joining K3s cluster from $NODE_NAME"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--server https://$MASTER_IP:6443 $K3S_EXEC" sh -
  fi
}

function install_helm {
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
  apt-get update
  apt-get install -y helm
  for ((i=0; i<$HELM_APP_COUNT; i++)); do
    local app="$${HELM_APP[$i]}"
    local repo="$${HELM_REPO[$i]}"
    echo "[*] Adding Helm repo: $app → $repo"
    helm repo add "$app" "$repo"
  done
  
  echo "[*] Updating Helm repositories..."
  helm repo update
}

function install_longhorn {
  mkdir -p /var/lib/longhorn #Create default Volume Mounting point
  fetch_app_manifests "longhorn" "values.yaml"

  NODE_CNT=$((NODE_COUNT-1))
  MAX_INDEX=$((NODE_CNT-1))
  
  for ((i=0; i<=MAX_INDEX; i++)); do
    until kubectl get node "$APP_NAME-worker-$i" 2>/dev/null | grep -q " Ready "; do
      echo "Waiting for $APP_NAME-worker-$i to join cluster..."
      sleep 5
    done
    kubectl label node $APP_NAME-worker-$i node.longhorn.io/create-default-disk=true --overwrite #longhorn용 라벨 추가
  done

  echo "[*] longhorn helm chart install...."
  helm install longhorn longhorn/longhorn \
    --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --namespace longhorn-system \
    --set defaultSettings.defaultReplicaCount=$NODE_CNT \
    --set persistence.defaultClassReplicaCount=$NODE_CNT \
    --create-namespace \
    -f $USER_HOME/app/longhorn/values.yaml

  echo "[*] Waiting For Ready longhorn-system Maximum 300s..."
  kubectl wait --namespace longhorn-system --for=condition=ready pod -l app=longhorn-manager --timeout=300s
}

function install_traefik {
  fetch_app_manifests "traefik" "values.yaml" "volume/vol.yaml" "volume/pv.yaml"
 
  echo "[*] traefik-service namespace create.."
  kubectl create namespace traefik-service
  echo "[*] traefik longhorn volume create.."
  kubectl apply -f $USER_HOME/app/traefik/volume/vol.yaml
  echo "[*] traefik pv create.."
  #kubectl apply -f $USER_HOME/app/traefik/volume/pv.yaml

  echo "[*] traefik helm chart install.."
  helm install traefik traefik/traefik \
    --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --namespace traefik-service \
    -f $USER_HOME/app/traefik/values.yaml
}

function attach_ingressroute {
  echo "[*] Adding IngressRoute..."
  for item in "$${INGRESS_APP[@]}"; do
    curl -sSL -o $USER_HOME/app/$item/ingressroute.yaml $GIT_ADDRESS/$item/ingressroute.yaml
    sed -i "s|domain.com|$DOMAIN|g" $USER_HOME/app/$item/ingressroute.yaml
    kubectl apply -f $USER_HOME/app/$item/ingressroute.yaml
    echo "[*] Applied $item IngressRoute"
  done
}

function install_crowdsec {
  fetch_app_manifests "crowdsec" "values.yaml" "volume.yaml" "configmap.yaml" "middleware.yaml"

  echo "[*] modify crowdsec values.yaml.."
  sed -i -e "s|CHANGEENROLLKEY|$CROWDSEC_KEY|g" -e "s|APPNAME|$APP_NAME|g" $USER_HOME/app/crowdsec/values.yaml #values.yaml 커스텀

  echo "[*] crowdsec pvc, configmap create.."
  kubectl create namespace crowdsec-service
  #kubectl apply -f $USER_HOME/app/crowdsec/volume.yaml
  #kubectl apply -f $USER_HOME/app/crowdsec/configmap.yaml

  echo "[*] crowdsec helm chart install.."
  helm install crowdsec crowdsec/crowdsec \
    --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --namespace crowdsec-service \
    -f $USER_HOME/app/crowdsec/values.yaml

  echo "[*] Waiting for LAPI Pod to become ready (timeout 300s)..."
  kubectl wait --namespace crowdsec-service --for=condition=ready pod -l k8s-app=crowdsec,type=lapi --timeout=300s

  LAPI_POD=$(kubectl -n crowdsec-service get pods -l 'k8s-app=crowdsec,type=lapi' -o jsonpath='{.items[0].metadata.name}')
  BOUNCER_KEY=$(kubectl -n crowdsec-service exec -i "$LAPI_POD" -- cscli bouncers add traefik-bouncer | sed -n '3p' | xargs)

  sed -i "s|MYSECRETLAPI|$BOUNCER_KEY|g" $USER_HOME/app/crowdsec/middleware.yaml #values.yaml 커스텀

  kubectl apply -f $USER_HOME/app/crowdsec/middleware.yaml
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
  iptables -A INPUT -p tcp -s $${SUBNET_CIDR[1]} -m multiport --dports 2379,2380,3260,6443,9500:9600,10250 -j ACCEPT
  iptables -A INPUT -p udp -s $${SUBNET_CIDR[1]} -m multiport --dports 8472 -j ACCEPT

  # Load Balancer 수신 허용 (8080, 8443)
  iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
  iptables -A INPUT -p tcp --dport 8443 -j ACCEPT

  BASTION_IP=$${NODE_IP[$NODE_COUNT-1]}
  # Bastion 호스트에서의 접근 허용 (SSH, 8080, 8443)
  iptables -A INPUT -p tcp -s $BASTION_IP --dport 22 -j ACCEPT
  iptables -A INPUT -p tcp -s $BASTION_IP --dport 8080 -j ACCEPT
  iptables -A INPUT -p tcp -s $BASTION_IP --dport 8443 -j ACCEPT

  # ICMP 허용 (ping)
  iptables -A INPUT -p icmp -j ACCEPT

  # 변경사항 저장
  iptables-save > /etc/iptables/rules.v4
}

function fetch_app_manifests() {
  local app=$1
  echo "[*] $app init data download.."
  shift
  while [ "$#" -gt 0 ]; do
    local file="$1"
    local target_path="$USER_HOME/app/$app/$file"

    mkdir -p "$(dirname "$target_path")"
    curl -sSL -o "$target_path" "$GIT_ADDRESS/$app/$file"

    echo "[✓] Downloaded: $target_path"
    shift
  done
}

disable_ipv6
dependency
install_k3s
net_rule_set
if [ "$INDEX" -eq "0" ]; then
  install_helm
  install_longhorn
  install_traefik  
  attach_ingressroute
  install_crowdsec  
fi

set +e #어떤 에러가 발생하더라도 cloud-init 결과물을 홈 디렉토리에 생성하도록 하기
install -o ubuntu -g ubuntu -m 644 /var/log/cloud-init-output.log $USER_HOME/init_log.txt || true
set -e

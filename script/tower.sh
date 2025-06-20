#!/bin/bash
set -euxo pipefail #에러날 시 스크립트 종료

#초기 변수 선언
EXTRA_INSTALL="net-tools"
TAIL_HOSTNAME="${app_name}-vm-tower"
TAIL_KEY="${tail_key}"
TAIL_SUBNET="${tail_subnet}"

function disable_ipv6 { #ipv6 비활성화
  echo -e 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1' | tee -a /etc/sysctl.conf
  sysctl -p
}

function dependency { #타임존 설정 후 의존성 설치
  timedatectl set-timezone Asia/Seoul
  apt-get update
  apt-get upgrade -y
  apt-get install -y $EXTRA_INSTALL
}

function install_tailscale { #tailscale 설치
  curl -fsSL https://tailscale.com/install.sh | sh
  systemctl enable --now tailscaled
  tailscale up --authkey=$TAIL_KEY --hostname=$TAIL_HOSTNAME --advertise-routes=$TAIL_SUBNET --accept-routes --accept-dns=true
}

function install_docker { #docker 설치
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo \"$${UBUNTU_CODENAME:-$${VERSION_CODENAME}}\") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

function install_rancher { #rancher 설치
  docker run --name rancher-server --privileged -d --restart=unless-stopped -p 80:80 -p 443:443 rancher/rancher

  #설치 완료시까지 대기
  until docker logs rancher-server 2>&1 | grep -q "Bootstrap Password:"; do
    echo "Waiting for Rancher to start..."
    sleep 5
  done

  #rancher 초기 비밀번호를 생성
  docker logs rancher-server 2>&1 \
    | grep "Bootstrap Password:" \
    | awk -F': ' '{print $2}' \
    | tee /home/ubuntu/rancher_init_pwd.txt > /dev/null && \

  chown ubuntu:ubuntu /home/ubuntu/rancher_init_pwd.txt
}

disable_ipv6
dependency
install_tailscale
#install_docker
#install_rancher

#내부 노드 접속용 개인키를 주입
echo "${private_key}" | base64 -d > /home/ubuntu/private.key
chown ubuntu:ubuntu /home/ubuntu/private.key
chmod 600 /home/ubuntu/private.key

set +e #어떤 에러가 발생하더라도 cloud-init 결과물을 홈 디렉토리에 생성하도록 하기
install -o ubuntu -g ubuntu -m 644 /var/log/cloud-init-output.log /home/ubuntu/init_log.txt || true
set -e

#ALpine
FROM ubuntu:22.04 AS build
LABEL maintainer="dselen@nerthus.nl"

# Declaring environment variables, change Peernet to an address you like, standard is a 24 bit subnet.
ARG wg_net="10.0.0.1"
ARG wg_port="51820"
# Following ENV variables are changable on container runtime because /entrypoint.sh handles that. See compose.yaml for more info.
ENV TZ="Europe/Moscow"
ENV global_dns="1.1.1.1"
ENV enable="none"
ENV isolate="awg0"
ENV public_ip="0.0.0.0"

#Set time zone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
# Doing package management operations, such as upgrading
RUN apt-get -y update && apt-get -y upgrade
#Install package
RUN apt-get -y install \
    bash \
    git \
    tzdata \
    iptables \
    curl \
    wget \
    iproute2 \
    procps \
    iputils-ping \
    software-properties-common \
    && apt-get remove -y linux-image-* --autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN cp -f /etc/apt/sources.list /etc/apt/sources.list.backup && \
    sed "s/# deb-src/deb-src/" /etc/apt/sources.list.backup > /etc/apt/sources.list


RUN apt-get -y update && apt-get -y upgrade
RUN mkdir -p ~/awg &&\
    cd ~/awg

RUN echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/00-amnezia.conf

RUN add-apt-repository ppa:deadsnakes/ppa

RUN apt-get -y install \
        python3-psutil \
        python3-bcrypt \
        python3-pip \
        python3-venv

RUN pip install qrcode

RUN add-apt-repository -y ppa:amnezia/ppa && \
    apt install -y amneziawg

# Doing WireGuard Dashboard installation measures. Modify the git clone command to get the preferred version, with a specific branch for example.
ENV WGDASH=/opt/wireguarddashboard
RUN mkdir -p /setup/conf && \
    mkdir /setup/app &&  \
    mkdir ${WGDASH}
COPY ./src /setup/app/src

# Set the volume to be used for WireGuard configuration persistency.
VOLUME etc/amnezia/amneziawg/
VOLUME ${WGDASH}

#Create config awg
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN out_adapt=$(ip -o -4 route show to default | awk '{print $NF}') \
  && echo -e "[Interface]\n\
Address = ${wg_net}/24\n\
PrivateKey =\n\
Jc = \n\
Jmin = \n\
Jmax = \n\
S1 = \n\
S2 = \n\
H1 = \n\
H2 = \n\
H3 = \n\
H4 = \n\
PostUp = iptables -t nat -I POSTROUTING 1 -s ${wg_net}/24 -o ${out_adapt} -j MASQUERADE\n\
PostUp = iptables -I FORWARD -i wg0 -o wg0 -j DROP\n\
PreDown = iptables -t nat -D POSTROUTING -s ${wg_net}/24 -o ${out_adapt} -j MASQUERADE\n\
PreDown = iptables -D FORWARD -i wg0 -o wg0 -j DROP\n\
ListenPort = ${wg_port}\n\
SaveConfig = true\n\
DNS = ${global_dns}" > /setup/conf/awg0.conf \
  && chmod 600 /setup/conf/awg0.conf

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -s -o /dev/null -w "%{http_code}" http://localhost:10086/signin | grep -q "401" && exit 0 || exit 1

# Copy the basic entrypoint.sh script.
COPY entrypoint.sh /entrypoint.sh

# Exposing the default WireGuard Dashboard port for web access.
EXPOSE 10086
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

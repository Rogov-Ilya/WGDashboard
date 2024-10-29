FROM golang:1.22.3 AS awg
COPY ./Amnezia /awg
WORKDIR /awg
RUN go mod download && \
    go mod verify && \
    go build -ldflags '-linkmode external -extldflags "-fno-PIC -static"' -v -o /usr/bin

#ALpine
FROM alpine:latest AS build
LABEL maintainer="dselen@nerthus.nl"

# Declaring environment variables, change Peernet to an address you like, standard is a 24 bit subnet.
ARG wg_net="10.0.0.1"
ARG wg_port="51820"

# Following ENV variables are changable on container runtime because /entrypoint.sh handles that. See compose.yaml for more info.
ENV TZ="Europe/Amsterdam"
ENV global_dns="1.1.1.1"
ENV enable="none"
ENV isolate="awg0"
ENV public_ip="0.0.0.0"

# Doing package management operations, such as upgrading
RUN apk update \
  && apk add --no-cache bash git tzdata\
  iptables ip6tables openrc curl wget iproute2\
  sudo py3-psutil py3-bcrypt py3-pip
# AWG Realise
ARG AWGTOOLS_RELEASE="1.0.20241018"
# AWG Install
RUN cd /usr/bin/ && \
    wget https://github.com/amnezia-vpn/amneziawg-tools/releases/download/v${AWGTOOLS_RELEASE}/alpine-3.19-amneziawg-tools.zip && \
    unzip -j alpine-3.19-amneziawg-tools.zip && \
    chmod +x /usr/bin/awg /usr/bin/awg-quick && \
    ln -s /usr/bin/awg /usr/bin/wg && \
    ln -s /usr/bin/awg-quick /usr/bin/wg-quick
COPY --from=awg /usr/bin/amneziawg-go /usr/bin/amneziawg-go

# Using WGDASH -- like wg_net functionally as a ARG command. But it is needed in entrypoint.sh so it needs to be exported as environment variable.
ENV WGDASH=/opt/wireguarddashboard

# Removing the Linux Image package to preserve space on the image, for this reason also deleting apt lists, to be able to install packages: run apt update.

# Doing WireGuard Dashboard installation measures. Modify the git clone command to get the preferred version, with a specific branch for example.
RUN mkdir -p /setup/conf && mkdir /setup/app && mkdir ${WGDASH}
COPY ./src /setup/app/src

# Set the volume to be used for WireGuard configuration persistency.
VOLUME etc/amnezia/amneziawg/
VOLUME ${WGDASH}
#Create config awg
RUN mkdir -p ~/awg && \
    cd ~/awg/ && \
    wget -O awgcfg.py https://gist.githubusercontent.com/remittor/8c3d9ff293b2ba4b13c367cc1a69f9eb/raw/awgcfg.py
# Generate basic WireGuard interface. Echoing the WireGuard interface config for readability, adjust if you want it for efficiency.
# Also setting the pipefail option, verbose: https://github.com/hadolint/hadolint/wiki/DL4006.
#SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#RUN out_adapt=$(ip -o -4 route show to default | awk '{print $NF}') \
#  && echo -e "[Interface]\n\
#Address = ${wg_net}/24\n\
#PrivateKey =\n\
#PostUp = iptables -t nat -I POSTROUTING 1 -s ${wg_net}/24 -o ${out_adapt} -j MASQUERADE\n\
#PostUp = iptables -I FORWARD -i awg0 -o awg0 -j DROP\n\
#PreDown = iptables -t nat -D POSTROUTING -s ${wg_net}/24 -o ${out_adapt} -j MASQUERADE\n\
#PreDown = iptables -D FORWARD -i awg0 -o awg0 -j DROP\n\
#ListenPort = ${wg_port}\n\
#SaveConfig = true\n\
#DNS = ${global_dns}" > /setup/conf/awg0.conf \
#  && chmod 600 /setup/conf/awg0.conf
CMD ["pyton","awgcfg.py --make /etc/amnezia/amneziawg/awg0.conf -i ${wg_net} -p ${wg_port}"]
# Defining a way for Docker to check the health of the container. In this case: checking the login URL.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD sh -c 'pgrep gunicorn > /dev/null && pgrep tail > /dev/null' || exit 1

# Copy the basic entrypoint.sh script.
COPY entrypoint.sh /entrypoint.sh

# Exposing the default WireGuard Dashboard port for web access.
EXPOSE 10086
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

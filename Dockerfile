FROM python:3.7.4
ENV TZ=Asia/Tokyo
COPY start.sh /usr/bin/start.sh
# kubectlのインストール
RUN set -xe \
    && DEBIAN_FRONTEND=noninteractive \
    && pip install certbot certbot-dns-sakuracloud -U pip \
    && apt-get update \
    && apt-get install -y aria2 tzdata \
    && aria2c https://storage.googleapis.com/kubernetes-release/release/v1.17.0/bin/linux/amd64/kubectl \
    && mv kubectl /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && chmod +x /usr/bin/start.sh

CMD [ "start.sh" ]
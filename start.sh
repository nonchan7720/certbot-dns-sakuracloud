#!/bin/bash

error_check () {
    if [ "$1" = "" ]; then
        echo "$2が未入力です"
        exit 1
    fi
}

delete () {
    if [ "${NAMESPACE}" != "" ]; then
        kubectl delete cm -n ${NAMESPACE} ${DOMAIN}-$1
    else
        kubectl delete cm ${DOMAIN}-$1
    fi
}

create () {
    if [ -e "/etc/letsencrypt/live/${DOMAIN}/$1.pem" ]; then
        if [ "${NAMESPACE}" != "" ]; then
            kubectl create cm -n ${NAMESPACE} ${DOMAIN}-$1 --from-file="/etc/letsencrypt/live/${DOMAIN}/$1.pem"
        else
            kubectl create cm ${DOMAIN}-$1 --from-file="/etc/letsencrypt/live/${DOMAIN}/$1.pem"
        fi
    fi
}

restart () {
    if [ "${NAMESPACE}" != "" ]; then
        kubectl patch deployment -n ${NAMESPACE} ${DEPNAME} -p \
        "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"reloaded-at\":\"`date +'%Y%m%d%H%M%S'`\"}}}}}"
    else
        kubectl patch deployment ${DEPNAME} -p \
        "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"reloaded-at\":\"`date +'%Y%m%d%H%M%S'`\"}}}}}"
    fi
}

init () {
    # 必須チェック
    error_check ${EMAIL} "EMAIL"
    error_check ${SAKURACLOUD_ACCESS_TOKEN:-""} "SAKURACLOUD_ACCESS_TOKEN"
    error_check ${SAKURACLOUD_ACCESS_TOKEN_SECRET:-""} "SAKURACLOUD_ACCESS_TOKEN_SECRET"
    
    # さくらのクラウドDNS情報ファイル作成
cat << EOF > ./.sakura
dns_sakuracloud_api_token = ${SAKURACLOUD_ACCESS_TOKEN}
dns_sakuracloud_api_secret = ${SAKURACLOUD_ACCESS_TOKEN_SECRET}
EOF
    
    # アクセス権限の変更
    chmod 0600 ./.sakura
    # TIMEOUT設定
    SLEEP_TIME_=${SLEEP_TIME:-120}
}

main() {
    # ワイルドカードドメイン設定
    local WDOMAIN="*.${DOMAIN}"
    # 証明書の取得
    # ポータルサイト参考：https://free-ssl.jp/command/
    if [ ! -e "/etc/letsencrypt/live/${DOMAIN}/" ]; then
        CERTBOT_SUBCOMMAND="certonly"
    else
        CERTBOT_SUBCOMMAND="renew"
        CERTBOT_ARGS="${CERTBOT_ARGS} --days 30"
    fi
    cmd="${CERTBOT_SUBCOMMAND} \
    --dns-sakuracloud \
    --dns-sakuracloud-credentials ./.sakura \
    --dns-sakuracloud-propagation-seconds ${SLEEP_TIME_} \
    -d ${WDOMAIN} \
    -m ${EMAIL} \
    --agree-tos \
    --no-eff-email \
    --keep-until-expiring ${CERTBOT_ARGS}"
    if [ "${DEBUG:-"N"}" = "Y" ]; then
        cmd="$cmd --dry-run"
    fi
    set $cmd
    echo $@
    certbot "$@"
    rm -f ./.sakura
    if [ ${K8S_CM:-"Y"} = "Y" ]; then
        # kubectlで削除
        delete fullchain
        delete privkey
        
        # kubectlで作成
        create fullchain
        create privkey
        # コンテナが指定されていたら
        if [ "$DEPNAME" != "" ]; then
            restart
        fi
    fi
}

init
for DOMAIN_NS_DP in ${DOMAIN_NS_DPS[@]};
do
    # ドメイン:ネームスペース:デプロイメント名
    sp=($(echo $DOMAIN_NS_DP | tr ':' ' '))
    DOMAIN=${sp[0]}
    NAMESPACE=${sp[1]}
    DEPNAME=${sp[2]}
    main
done
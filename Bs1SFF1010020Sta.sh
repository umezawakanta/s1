#!/bin/bash

# ジョブ名の設定
JOB_NAME="EAM (GIS) 提供用転送形式変換 (地形図) 起動シェル"

# ログファイルの設定
LOG_FILE="log/logfile.log"

# 設定ファイルの読み込み
source config/batchenv_sjis.sh
source config/batch.profile
source config/APFW_ENV

# コンフィグファイルのパス
CONFIG_FILE="config/Bs1SFF1010020GIS.prm"

# ユーザー権限チェック
if [ "$(id -u)" -eq 0 ] || [ "$(id -u)" -ge 60000 ]; then
    echo "エラー: root ユーザーまたは UID 60000 以上のユーザーでの実行は許可されていません。"
    exit 80
fi

# ログ出力関数
log_message() {
    local log_type=$1
    local message=$2
    local log_entry
    case $log_type in
        "START") log_entry="開始ログ: $message" ;;
        "END") log_entry="終了ログ: $message" ;;
        "ERROR") log_entry="エラーログ: $message" ;;
        *) log_entry="シェル標準出力ログ: $message" ;;
    esac
    echo "$log_entry"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $log_entry" >> "$LOG_FILE"
}

# 開始ログ
log_message "START" "$JOB_NAME を開始します。"

# 実行シェルの呼び出し
EXECUTOR_SCRIPT="sbin/Bs1SFF1010020ConversionFormatGIS.sh"
if [ -f "$EXECUTOR_SCRIPT" ]; then
    log_message "" "実行シェルを呼び出します: $EXECUTOR_SCRIPT"
    "$EXECUTOR_SCRIPT" "$CONFIG_FILE"
    EXIT_STATUS=$?
else
    log_message "ERROR" "実行シェルが見つかりません: $EXECUTOR_SCRIPT"
    EXIT_STATUS=1
fi

# 終了ステータスの処理
if [ $EXIT_STATUS -eq 0 ]; then
    log_message "END" "$JOB_NAME が正常終了しました。終了ステータス: $EXIT_STATUS"
    exit 0
elif [ $EXIT_STATUS -eq 100 ]; then
    log_message "END" "$JOB_NAME が正常終了しました（転送指示結果ファイルなし）。終了ステータス: $EXIT_STATUS"
    exit 0
else
    log_message "ERROR" "$JOB_NAME が異常終了しました。終了ステータス: $EXIT_STATUS"
    exit 1
fi
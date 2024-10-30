#!/bin/bash

# ジョブ名の設定
JOB_NAME="EAM (GIS) 提供用転送形式変換 (地形図) 起動シェル"

# ログファイルの設定
STARTER_LOG_FILE="log/starter.log"

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
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry
    case $level in
        "START") log_entry="[$level] $message" ;;
        "END") log_entry="[$level] $message" ;;
        "ERROR") log_entry="[$level] $message" ;;
        "INFO") log_entry="[$level] $message" ;;
        "WARN") log_entry="[$level] $message" ;;
        "DEBUG") log_entry="[$level] $message" ;;
        *) log_entry="[INFO] $message" ;;
    esac
    echo "$timestamp $log_entry"
    echo "$timestamp $log_entry" >> "$STARTER_LOG_FILE"
}

# 開始ログ
log_message "START" "$JOB_NAME を開始します。"

# 実行シェルの呼び出し
EXECUTOR_SCRIPT="sbin/Bs1SFF1010020ConversionFormatGIS.sh"
if [ -f "$EXECUTOR_SCRIPT" ]; then
    log_message "INFO" "実行シェルを呼び出します: $EXECUTOR_SCRIPT"
    "$EXECUTOR_SCRIPT" "$CONFIG_FILE"
    EXIT_STATUS=$?
    log_message "DEBUG" "実行シェルの終了ステータス: $EXIT_STATUS"
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
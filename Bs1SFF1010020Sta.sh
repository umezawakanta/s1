#!/bin/bash

# ジョブ名の設定
JOB_NAME="EAM (GIS) 提供用転送形式変換 (地形図) 起動シェル"

# ログファイルの設定
STARTER_LOG_FILE="log/starter.log"

# 設定ファイルの読み込み
source config/batchenv_sjis.sh
source config/batch.profile
source config/APFW_ENV

# 環境情報ファイルのパス
CONFIG_FILE="config/Bs1SFF1010020GIS.prm"
source $CONFIG_FILE

# ユーザー権限チェック
if [ "$(id -u)" -eq 0 ] || [ "$(id -u)" -ge 60000 ]; then
    echo "エラー: root ユーザーまたは UID 60000 以上のユーザーでの実行は許可されていません。"
    exit 80
fi

# ログレベルの定義
declare -A LOG_LEVELS=(
  ["DEBUG"]=0
  ["INFO"]=1
  ["WARN"]=2
  ["ERROR"]=3
)

# メッセージをログに記録する関数
log_message() {
    local level=$1
    local message=$2
    local file_name=${BASH_SOURCE[1]##*/}
    local line_number=${BASH_LINENO[0]}

    # 設定されたログレベルに基づいてメッセージをフィルタリング
    if [ "${LOG_LEVELS[$level]}" -ge "${LOG_LEVELS[$LOG_LEVEL]}" ]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local file_info=$(printf "[%-20s:%-4s]" "${file_name:0:20}" "${line_number:0:4}")
        local log_entry="$timestamp [$level] $file_info $message"
        echo "$log_entry"
        echo "$log_entry" >> "$LOG_FILE"
        
        if [ "$level" = "ERROR" ]; then
            ((ERROR_COUNT++))
        fi
    fi
}

# 開始ログ
log_message "INFO" "$JOB_NAME を開始します。"

# 実行シェルの呼び出し
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
    log_message "INFO" "$JOB_NAME が正常終了しました。終了ステータス: $EXIT_STATUS"
    exit 0
elif [ $EXIT_STATUS -eq 100 ]; then
    log_message "INFO" "$JOB_NAME が正常終了しました（転送指示結果ファイルなし）。終了ステータス: $EXIT_STATUS"
    exit 0
else
    log_message "ERROR" "$JOB_NAME が異常終了しました。終了ステータス: $EXIT_STATUS"
    exit 1
fi
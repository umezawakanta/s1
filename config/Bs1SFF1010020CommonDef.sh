#!/bin/bash

# メッセージをログに記録する関数
log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
    if [ "$level" = "ERROR" ]; then
        ((ERROR_COUNT++))
    fi
}
# ログファイルの設定
LOG_FILE="log/process.log"

log_message "INFO" "config/Bs1SFF1010020CommonDef.sh"
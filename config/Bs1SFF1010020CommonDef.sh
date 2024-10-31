#!/bin/bash

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
# ログファイルの設定
LOG_FILE="log/process.log"
LOG_LEVEL=INFO

log_message "DEBUG" "config/Bs1SFF1010020CommonDef.sh"
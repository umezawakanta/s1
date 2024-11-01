#!/bin/bash

set -e  # エラーが発生した時点でスクリプトを終了
set -u  # 未定義の変数を参照した場合にエラーを発生

# グローバル変数
COMPRESSED_FILE=""
GIS_CHIKEI_TRANS_COMP_FILE=""
ERROR_COUNT=0

# ログレベルの定義
declare -A LOG_LEVELS=(
  ["TRACE"]=1
  ["DEBUG"]=0
  ["INFO"]=2
  ["WARN"]=3
  ["ERROR"]=4
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

# コマンドをログに記録し、実行する関数
log_and_execute() {
    local command="$1"
    log_message "DEBUG" "実行コマンド: $command"
    local output
    if [ "${LOG_LEVELS[$LOG_LEVEL]}" -le "${LOG_LEVELS[DEBUG]}" ]; then
        output=$(eval "$command")
        local exit_code=$?
        log_message "DEBUG" "コマンド出力:"
        echo "$output"
    else
        output=$(eval "$command" 2>&1)
        local exit_code=$?
    fi
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR" "コマンドの実行に失敗しました。終了コード: $exit_code"
        [ "${LOG_LEVELS[$LOG_LEVEL]}" -le "${LOG_LEVELS[DEBUG]}" ] && log_message "DEBUG" "エラー出力:"
        echo "$output"
    fi
    return $exit_code
}

# ファイルの存在をチェックする関数
check_file_exists() {
    if [ ! -f "$1" ]; then
        log_message "ERROR" "ファイル $1 が存在しません"
        return 1
    fi
    return 0
}

# ディレクトリの存在をチェックする関数
check_dir_exists() {
    if [ ! -d "$1" ]; then
        log_message "ERROR" "ディレクトリ $1 が存在しません"
        return 1
    fi
    return 0
}

# ディレクトリを作成する関数
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        log_and_execute "mkdir -p \"$1\""
        log_message "DEBUG" "ディレクトリを作成しました: $1"
    fi
}

# ファイル複製
copy_files() {
    log_message "TRACE" "copy_files() start"
    log_message "DEBUG" "ファイル複製を開始します"
    
    log_message "INFO" "FROM_DIR: $FROM_DIR"
    log_message "INFO" "TO_DIR: $TO_DIR"
    log_message "INFO" "TO_DIR2: $TO_DIR2"
    
    # FROM_DIRの存在確認
    if ! check_dir_exists "$FROM_DIR"; then
        log_message "ERROR" "コピー元ディレクトリが存在しません: $FROM_DIR"
        return 1
    fi
    
    # TO_DIRとTO_DIR2の作成（存在しない場合）
    create_dir_if_not_exists "$TO_DIR"
    create_dir_if_not_exists "$TO_DIR2"
    
    # FROM_DIRの内容をTO_DIRにコピー
    log_message "DEBUG" "FROM_DIRの内容をTO_DIRにコピーします"
    if ! log_and_execute "cp -R \"$FROM_DIR\"/* \"$TO_DIR\"/"; then
        log_message "ERROR" "TO_DIRへのコピーに失敗しました"
        return 1
    fi
    
    # FROM_DIRの内容をTO_DIR2にコピー
    log_message "DEBUG" "FROM_DIRの内容をTO_DIR2にコピーします"
    if ! log_and_execute "cp -R \"$FROM_DIR\"/* \"$TO_DIR2\"/"; then
        log_message "ERROR" "TO_DIR2へのコピーに失敗しました"
        return 1
    fi
    
    log_message "INFO" "ファイル複製が完了しました"
    log_message "TRACE" "copy_files() end"
    return 0
}

# メインプロセス
main() {
    # ログファイルの設定
    LOG_FILE="log/process.log"
    LOG_LEVEL=TRACE

    # ログファイルのディレクトリを作成
    mkdir -p "$(dirname "$LOG_FILE")"
    log_message "TRACE" "main() start"
    log_message "TRACE" "（1）起動引数の個数チェック"
    # 環境情報ファイルのパスを引数から取得
    if [ $# -eq 0 ]; then
        log_message "ERROR" "環境情報ファイルのパスが指定されていません"
        exit 1
    fi

    log_message "TRACE" "（2）設定パラメータ設定"
    SHELL_PRM_FILE_PATH="$1"
    log_message "DEBUG" "SHELL_PRM_FILE_PATH: $SHELL_PRM_FILE_PATH"
    if [ ! -f "$SHELL_PRM_FILE_PATH" ]; then
        log_message "ERROR" "環境情報ファイル $SHELL_PRM_FILE_PATH が存在しません"
        exit 1
    fi

    # コンフィグファイルの読み込み
    source "$SHELL_PRM_FILE_PATH"

    # これ以降、log_message 関数が使用可能になる

    log_message "TRACE" "（3）バッチ処理共通定義の読み込み"
    # バッチ処理共通定義ファイルのパスを設定
    ${GYOMU_ROOT}/$COMMON_DEF_SCRIPT

    log_message "TRACE" "（4）環境情報ファイルの存在チェック"
    if [ ! -f "$SHELL_PRM_FILE_PATH" ]; then
        temp_log "ERROR" "環境情報ファイルが存在しません: $SHELL_PRM_FILE_PATH"
        exit 1
    fi

    log_message "TRACE" "（5）環境情報ファイルの読み込み"

    log_message "DEBUG" "環境情報ファイルを読み込みました: $SHELL_PRM_FILE_PATH"

    log_message "TRACE" "（6）業務変数の定義"
    JOB_NAME="複製"

    # 必須パラメータの確認
    required_params=(
        "FROM_DIR" "TO_DIR"
    )
    for param in "${required_params[@]}"; do
        if [ -z "${!param}" ]; then
            temp_log "ERROR" "必須パラメータ '$param' が設定されていません"
            exit 1
        fi
    done

    # GYOMU_ROOTが相対パスの場合、絶対パスに変換
    if [[ "$GYOMU_ROOT" != /* ]]; then
        GYOMU_ROOT="$(cd "$(dirname "$SHELL_PRM_FILE_PATH")/.." && pwd)"
        log_message "DEBUG" "GYOMU_ROOTを絶対パスに変換しました: $GYOMU_ROOT"
    fi

    # 各パラメータにGYOMU_ROOTを適用
    LOG_FILE="$GYOMU_ROOT/$LOG_FILE"
    FROM_DIR="$GYOMU_ROOT/$FROM_DIR"
    TO_DIR="$GYOMU_ROOT/$TO_DIR"
    TO_DIR2="$GYOMU_ROOT/$TO_DIR2"

    log_message "TRACE" "（7）開始メッセージ出力"
    log_message "INFO" "$JOB_NAME を開始します。"

    log_message "TRACE" "（8）複製処理"
    copy_files || log_message "ERROR" "複製に失敗しました"

    log_message "TRACE" "（9）終了処理"
    log_message "TRACE" "main() end"
    if [ $ERROR_COUNT -eq 0 ]; then
        log_message "INFO" "$JOB_NAME が正常に完了しました"
        exit 0
    else
        log_message "ERROR" "$JOB_NAME の処理中にエラーが発生しました。エラー数: $ERROR_COUNT"
        exit 1
    fi
}

# メインプロセスの実行（引数を渡す）
main "$@"
log_message "INFO" "スクリプトの実行が完了しました。"
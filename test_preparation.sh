#!/bin/bash

# エラー発生時にスクリプトを終了
set -e

# 未定義変数の参照時にエラーを発生
set -u

# ジョブ名の設定
JOB_NAME="EAM (GIS) 提供用転送形式変換 (地形図) テスト準備"

# ログファイルの設定
LOG_FILE="log/test_preparation.log"

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
    echo "$timestamp $log_entry" >> "$LOG_FILE"
}

# 開始ログ
log_message "START" "$JOB_NAME を開始します。"

# コンフィグファイルの読み込み
source "$CONFIG_FILE"

# 転送用圧縮ファイル格納フォルダのパスを設定
COMPRESSED_FILE_DIR="$GYOMU_ROOT/$(dirname "$GIS_CHIKEI_TRANS_FILE")"

# 転送指示結果ファイルの作成
TRANSFER_RESULT_FILE="$GYOMU_ROOT/$TRANSFER_RESULT_FILE"
log_message "INFO" "転送指示結果ファイルを作成します: $TRANSFER_RESULT_FILE"

# 転送用圧縮ファイル格納フォルダ内のファイルを検索
compressed_files=($(ls -t "$COMPRESSED_FILE_DIR"/*.tar.gz 2>/dev/null))

if [ ${#compressed_files[@]} -gt 0 ]; then
    # 転送指示結果ファイルを初期化
    > "$TRANSFER_RESULT_FILE"

    for file in "${compressed_files[@]}"; do
        file_name=$(basename "$file")
        update_date=$(date -r "$file" +%Y%m%d%H%M%S)
        local_file="/sq5nas/data/recv/SQ500ES011/$file_name"
        remote_file="$GYOMU_ROOT/FT/$file_name"
        status="0"
        comment="chikei"
        timestamp="$update_date"

        echo "$file_name,$update_date,$local_file,$remote_file,$status,$comment,$timestamp" >> "$TRANSFER_RESULT_FILE"
        log_message "INFO" "転送指示結果ファイルに追加しました: $file_name"
    done

    log_message "INFO" "転送指示結果ファイルを作成しました: $TRANSFER_RESULT_FILE"
else
    log_message "WARN" "転送用圧縮ファイルが見つかりません。サンプルデータを使用します。"
    echo "B003KY_20241029154653.tar.gz,20241029102403,/sq5nas/data/recv/SQ500ES011/B003KY_20241029154653.tar.gz,/home/kanta/s1/FT/B003KY_20241029154653.tar.gz,0,chikei,20241029102403" > "$TRANSFER_RESULT_FILE"
fi

# 実行シェルの呼び出し
EXECUTOR_SCRIPT="sbin/Bs1SFF1010020ConversionFormatGIS.sh"
if [ -f "$EXECUTOR_SCRIPT" ]; then
    log_message "INFO" "実行シェルを呼び出します: $EXECUTOR_SCRIPT"
    "$EXECUTOR_SCRIPT" "$CONFIG_FILE"
    EXIT_STATUS=$?
else
    log_message "ERROR" "実行シェルが見つかりません: $EXECUTOR_SCRIPT"
    EXIT_STATUS=1
fi

# 終了ステータスの処理
if [ $EXIT_STATUS -eq 0 ]; then
    log_message "END" "$JOB_NAME が正常終了しました。終了ステータス: $EXIT_STATUS"
else
    log_message "ERROR" "$JOB_NAME が異常終了しました。終了ステータス: $EXIT_STATUS"
fi

exit $EXIT_STATUS
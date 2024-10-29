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

# コンフィグファイルの読み込み
source "$CONFIG_FILE"

# 転送指示結果ファイルの作成
TRANSFER_RESULT_FILE="$GYOMU_ROOT/$TRANSFER_RESULT_FILE"
log_message "" "転送指示結果ファイルを作成します: $TRANSFER_RESULT_FILE"
echo "B003KY_20241029102403.tar.gz,20241029102403,/sq5nas/data/recv/SQ500ES011/B003KY_20241029102403.tar.gz,/home/kanta/s1/FT/B003KY_20241029102403.tar.gz,0,chikei,20241029102403" > "$TRANSFER_RESULT_FILE"

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
else
    log_message "ERROR" "$JOB_NAME が異常終了しました。終了ステータス: $EXIT_STATUS"
fi

exit $EXIT_STATUS
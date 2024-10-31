#!/bin/bash

# エラー発生時にスクリプトを終了
set -e

# 未定義変数の参照時にエラーを発生
set -u

# ジョブ名の設定
JOB_NAME="EAM (GIS) 提供用転送形式変換 (地形図) テスト準備 2"

# ログファイルの設定
TEST_LOG_FILE="log/test_preparation_2.log"
LOG_LEVEL=INFO

# 必要なディレクトリを作成する関数
create_required_directories() {
    local dirs=(
        "$(dirname "$TEST_LOG_FILE")"
        "result"
        $GIS_CHIKEI_TRANS_COMP_DIR
        "back"
        "inf"
        "log"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_message "DEBUG" "ディレクトリを作成しました: $dir"
        fi
    done
}

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
        echo "$log_entry" >> "$TEST_LOG_FILE"
        
        if [ "$level" = "ERROR" ]; then
            ((ERROR_COUNT++))
        fi
    fi
}

# 設定ファイルの読み込み
source config/batchenv_sjis.sh || {
    echo "エラー: batchenv_sjis.sh の読み込みに失敗しました"
    exit 1
}
source config/batch.profile || {
    echo "エラー: batch.profile の読み込みに失敗しました"
    exit 1
}
source config/APFW_ENV || {
    echo "エラー: APFW_ENV の読み込みに失敗しました"
    exit 1
}

# コンフィグファイルのパス
CONFIG_FILE="config/Bs1SFF1010020GIS.prm"

# ユーザー権限チェック
if [ "$(id -u)" -eq 0 ] || [ "$(id -u)" -ge 60000 ]; then
    echo "エラー: root ユーザーまたは UID 60000 以上のユーザーでの実行は許可されていません。"
    exit 80
fi

# 開始ログ
mkdir -p "$(dirname "$TEST_LOG_FILE")"
log_message "INFO" "$JOB_NAME を開始します。"

# コンフィグファイルの読み込み
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERROR" "コンフィグファイルが見つかりません: $CONFIG_FILE"
    exit 1
fi
source "$CONFIG_FILE"

# 必要なディレクトリを作成
create_required_directories

# GYOMU_ROOTを絶対パスに変換
if [[ "$GYOMU_ROOT" != /* ]]; then
    GYOMU_ROOT="$(cd "$GYOMU_ROOT" && pwd)"
    log_message "DEBUG" "GYOMU_ROOTを絶対パスに変換しました: $GYOMU_ROOT"
fi

# 転送用圧縮ファイル格納フォルダのパスを設定
COMPRESSED_FILE_DIR="$GYOMU_ROOT/$(dirname "$GIS_CHIKEI_TRANS_COMP_FILE")"
log_message "DEBUG" "圧縮ファイル格納フォルダ: $COMPRESSED_FILE_DIR"

# 転送指示結果ファイルの作成
GIS_CHIKEI_TRANS_RESULT_FILE="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_RESULT_FILE"
create_required_directories
log_message "INFO" "転送指示結果ファイルを作成します: $GIS_CHIKEI_TRANS_RESULT_FILE"

# 転送用圧縮ファイル格納フォルダ内のファイルを検索
if [ ! -d "$COMPRESSED_FILE_DIR" ]; then
    log_message "DEBUG" "圧縮ファイル格納フォルダを作成します"
    mkdir -p "$COMPRESSED_FILE_DIR"
fi

log_message "DEBUG" "圧縮ファイルを検索します"
shopt -s nullglob
compressed_files=("$COMPRESSED_FILE_DIR"/*.tar.gz)
shopt -u nullglob

# 転送用圧縮ファイル格納フォルダ内のファイルを検索
if [ ! -d "$COMPRESSED_FILE_DIR" ]; then
    log_message "DEBUG" "圧縮ファイル格納フォルダを作成します"
    mkdir -p "$COMPRESSED_FILE_DIR"
fi

log_message "DEBUG" "圧縮ファイルを検索します"
shopt -s nullglob
compressed_files=("$COMPRESSED_FILE_DIR"/*.tar.gz)
shopt -u nullglob

if [ ${#compressed_files[@]} -gt 0 ]; then
    log_message "DEBUG" "圧縮ファイルが見つかりました: ${#compressed_files[@]} 個"
    
    # 転送指示結果ファイルを初期化
    > "$GIS_CHIKEI_TRANS_RESULT_FILE"

    # 登録番号のカウンター
    counter=1

    for file in "${compressed_files[@]}"; do
        # 登録番号（連番）
        registration_number=$counter
        
        # 伝送カード名
        card_name=$GIS_CHIKEI_DENSO_CARD
        
        # ファイル名
        file_name=$(basename "$file")
        
        # ローカルファイル
        local_file="$GIS_CHIKEI_GIS_COMP_DIR$file_name"
        
        # リモートファイル
        remote_file="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_COMP_DIR/$file_name"
        
        # ステータス
        status="1"
        
        # コメント（chikei固定）
        comment="chikei"
        
        # タイムスタンプ（圧縮ファイル作成時のタイムスタンプ）
        timestamp=$(date -r "$file" +%Y%m%d%H%M%S)

        # 転送指示結果ファイルに追加
        # フォーマット: 登録番号,伝送カード名,ローカルファイル名,リモートファイル名,ステータス,コメント,タイムスタンプ
        echo "$registration_number,$card_name,$local_file,$remote_file,$status,$comment,$timestamp" >> "$GIS_CHIKEI_TRANS_RESULT_FILE"
        log_message "INFO" "転送指示結果ファイルに追加しました: $file_name"
        log_message "DEBUG" "追加レコード: $registration_number,$card_name,$local_file,$remote_file,$status,$comment,$timestamp"

        # カウンターをインクリメント
        ((counter++))
    done

    log_message "INFO" "転送指示結果ファイルを作成しました: $GIS_CHIKEI_TRANS_RESULT_FILE"
else
    log_message "WARN" "転送用圧縮ファイルが見つかりません。サンプルデータを使用します。"
    # サンプルデータで作成
    echo "1,$GIS_CHIKEI_DENSO_CARD,${GIS_CHIKEI_GIS_COMP_DIR}B003KY_20241030173959.tar.gz,$GYOMU_ROOT/$GIS_CHIKEI_TRANS_COMP_DIR/B003KY_20241030173959.tar.gz,0,chikei,20241030173959" > "$GIS_CHIKEI_TRANS_RESULT_FILE"
fi

# 起動シェルの呼び出し
if [ -f "$STARTER_SCRIPT" ]; then
    log_message "INFO" "起動シェルを呼び出します: $STARTER_SCRIPT"
    "$STARTER_SCRIPT" "$CONFIG_FILE"
    EXIT_STATUS=$?
    log_message "DEBUG" "起動シェルの実行が完了しました。終了ステータス: $EXIT_STATUS"
else
    log_message "ERROR" "起動シェルが見つかりません: $STARTER_SCRIPT"
    EXIT_STATUS=1
fi

# 終了ステータスの処理
if [ $EXIT_STATUS -eq 0 ]; then
    log_message "INFO" "$JOB_NAME が正常終了しました。終了ステータス: $EXIT_STATUS"
else
    log_message "ERROR" "$JOB_NAME が異常終了しました。終了ステータス: $EXIT_STATUS"
fi

exit $EXIT_STATUS
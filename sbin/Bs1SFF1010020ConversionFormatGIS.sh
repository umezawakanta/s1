#!/bin/bash

set -e  # エラーが発生した時点でスクリプトを終了
set -u  # 未定義の変数を参照した場合にエラーを発生

# グローバル変数
COMPRESSED_FILE=""
GIS_CHIKEI_TRANS_FILE=""
ERROR_COUNT=0

# メッセージをログに記録する関数
log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
    if [ "$level" = "ERROR" ]; then
        ((ERROR_COUNT++))
    fi
}

# ファイルの存在をチェックする関数
check_file_exists() {
    if [ ! -f "$1" ]; then
        log_message "ERROR" "ファイル $1 が存在しません"
        return 1
    fi
    return 0
}

# 転送指示結果ファイルの存在チェック
check_transfer_instruction_result() {
    log_message "INFO" "転送指示結果ファイルの存在確認: $TRANSFER_RESULT_FILE"
    if ! check_file_exists "$TRANSFER_RESULT_FILE"; then
        log_message "ERROR" "転送指示結果ファイル $TRANSFER_RESULT_FILE が存在しません"
        exit 1
    fi
    log_message "INFO" "転送指示結果ファイルの存在を確認しました: $TRANSFER_RESULT_FILE"
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
        mkdir -p "$1"
        log_message "INFO" "ディレクトリを作成しました: $1"
    fi
}

# シェープファイル複写
copy_shape_files() {
    log_message "INFO" "シェープファイルの複写を開始します"
    
    local copy_success=false
    
    # 8系と9系のディレクトリを検索
    for sys in sys08 sys09; do
        if [ ! -d "${SHAPE_FILES_ROOT}/${sys}" ]; then
            log_message "WARN" "${sys} ディレクトリが見つかりません: ${SHAPE_FILES_ROOT}/${sys}"
            continue
        fi
        log_message "INFO" "ディレクトリを検索 : ${SHAPE_FILES_ROOT}/${sys}"
        find "${SHAPE_FILES_ROOT}/${sys}" -type d -regex ".*/[0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]" | while read -r source_dir; do
            # 図面番号を抽出
            log_message "INFO" "図面番号を抽出"
            local drawing_number=$(echo "$source_dir" | grep -oE '[0-9]{7}$')
            log_message "WARN" "図面番号 drawing_number: $drawing_number"
            if [ -z "$drawing_number" ]; then
                log_message "WARN" "図面番号を抽出できません: $source_dir"
                continue
            fi
            
            local target_dir="${WORK_DIR}/${drawing_number}"
            log_message "INFO" "シェープファイルを複写します: $source_dir -> $target_dir"
            
            # ディレクトリ構造を作成
            create_dir_if_not_exists "$target_dir"
            
            # ファイルをコピー
            if find "$source_dir" -type f $$ -name "*.shp" -o -name "*.shx" -o -name "*.dbf" -o -name "*.prj" $$ -exec cp {} "$target_dir/" \; ; then
                log_message "INFO" "図面番号 ${drawing_number} のシェープファイルを正常に複写しました"
                copy_success=true
            else
                log_message "ERROR" "図面番号 ${drawing_number} のシェープファイルの複写に失敗しました"
            fi
        done
    done
    
    if [ "$copy_success" = false ]; then
        log_message "ERROR" "シェープファイルの複写に失敗しました"
        return 1
    fi
}

# 更新メッシュファイルリスト作成
create_update_mesh_list() {
    log_message "INFO" "更新メッシュファイルリストを作成中"
    
    create_dir_if_not_exists "$(dirname "$UPDATE_MESH_LIST")"
    
    # 更新メッシュファイルリストを初期化
    log_message "INFO" "更新メッシュファイルリストを初期化"
    : > "$UPDATE_MESH_LIST"
    
    # 各図面番号のディレクトリをループ
    log_message "INFO" "各図面番号のディレクトリをループ"
    local list_created=false
    for drawing_dir in "${WORK_DIR}"/*; do
        if [ -d "$drawing_dir" ]; then
            drawing_number=$(basename "$drawing_dir")
            echo "${drawing_number}" >> "$UPDATE_MESH_LIST"
            list_created=true
        fi
    done
    
    if [ "$list_created" = true ]; then
        log_message "INFO" "更新メッシュファイルリストを作成しました: $UPDATE_MESH_LIST"
    else
        log_message "ERROR" "更新メッシュファイルリストが空です"
        return 1
    fi
}

# 転送用圧縮ファイルの作成
create_transfer_compressed_file() {
    log_message "INFO" "転送用圧縮ファイルを作成中"
    create_dir_if_not_exists "$(dirname "$GIS_CHIKEI_TRANS_FILE")"
    if tar -czf "$GIS_CHIKEI_TRANS_FILE" -C "$(dirname "$WORK_DIR")" "$(basename "$WORK_DIR")" "$UPDATE_MESH_LIST"; then
        log_message "INFO" "転送用圧縮ファイルを作成しました: $GIS_CHIKEI_TRANS_FILE"
    else
        log_message "ERROR" "転送用圧縮ファイルの作成に失敗しました"
        return 1
    fi
}

# シェープファイル削除
delete_shape_files() {
    log_message "INFO" "シェープファイルを削除中"
    if [ -d "$WORK_DIR" ]; then
        log_message "INFO" "ファイル圧縮用ワークディレクトリを削除: $WORK_DIR"
        if rm -rf "$WORK_DIR"; then
            log_message "INFO" "シェープファイルを削除しました"
        else
            log_message "ERROR" "シェープファイルの削除に失敗しました"
            return 1
        fi
    else
        log_message "WARN" "削除するシェープファイルが見つかりません: $WORK_DIR"
    fi
}

# メインプロセス
main() {
    # コンフィグファイルのパスを引数から取得
    if [ $# -eq 0 ]; then
        echo "エラー: コンフィグファイルのパスが指定されていません"
        exit 1
    fi

    SHELL_PRM_FILE_PATH="$1"
    if [ ! -f "$SHELL_PRM_FILE_PATH" ]; then
        echo "エラー: コンフィグファイル $SHELL_PRM_FILE_PATH が存在しません"
        exit 1
    fi

    # コンフィグファイルの読み込み
    source "$SHELL_PRM_FILE_PATH"

    # 必須パラメータの確認
    required_params=(
        "LOG_FILE" "SHAPE_FILES_ROOT" "WORK_DIR" "UPDATE_MESH_LIST"
        "TRANSFER_RESULT_FILE" "TRANSFER_INFO_FILE" "GIS_CHIKEI_TRANS_FILE"
    )
    for param in "${required_params[@]}"; do
        if [ -z "${!param}" ]; then
            echo "エラー: 必須パラメータ '$param' が設定されていません"
            exit 1
        fi
    done

    # GYOMU_ROOTが相対パスの場合、絶対パスに変換
    if [[ "$GYOMU_ROOT" != /* ]]; then
        GYOMU_ROOT="$(cd "$(dirname "$SHELL_PRM_FILE_PATH")/.." && pwd)"
        log_message "INFO" "GYOMU_ROOTを絶対パスに変換しました: $GYOMU_ROOT"
    fi

    # 各パラメータにGYOMU_ROOTを適用
    LOG_FILE="$GYOMU_ROOT/$LOG_FILE"
    SHAPE_FILES_ROOT="$GYOMU_ROOT/$SHAPE_FILES_ROOT"
    WORK_DIR="$GYOMU_ROOT/$WORK_DIR"
    UPDATE_MESH_LIST="$GYOMU_ROOT/$UPDATE_MESH_LIST"
    TRANSFER_RESULT_FILE="$GYOMU_ROOT/$TRANSFER_RESULT_FILE"
    TRANSFER_INFO_FILE="$GYOMU_ROOT/$TRANSFER_INFO_FILE"
    GIS_CHIKEI_TRANS_FILE="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_FILE"

    # ログファイルのディレクトリを作成
    create_dir_if_not_exists "$(dirname "$LOG_FILE")"
    log_message "INFO" "ファイル処理を開始します"
    log_message "INFO" "コンフィグファイルを読み込みました: $SHELL_PRM_FILE_PATH"

    # 転送指示結果ファイルの存在チェック
    check_transfer_instruction_result

    # 処理の実行
    copy_shape_files || log_message "ERROR" "シェープファイルの複写に失敗しました"
    create_update_mesh_list || log_message "ERROR" "更新メッシュファイルリストの作成に失敗しました"
    create_transfer_compressed_file || log_message "ERROR" "転送用圧縮ファイルの作成に失敗しました"
    delete_shape_files || log_message "ERROR" "シェープファイルの削除に失敗しました"
    
    if [ $ERROR_COUNT -eq 0 ]; then
        log_message "INFO" "ファイル処理が正常に完了しました"
        exit 0
    else
        log_message "ERROR" "ファイル処理中にエラーが発生しました。エラー数: $ERROR_COUNT"
        exit 1
    fi
}

# メインプロセスの実行（引数を渡す）
main "$@"
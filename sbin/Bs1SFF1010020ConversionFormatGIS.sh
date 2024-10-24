#!/bin/bash

set -e  # エラーが発生した時点でスクリプトを終了
set -u  # 未定義の変数を参照した場合にエラーを発生

# グローバル変数
COMPRESSED_FILE=""
GIS_CHIKEI_TRANS_FILE=""

# メッセージをログに記録する関数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# ファイルの存在をチェックする関数
check_file_exists() {
    if [ ! -f "$1" ]; then
        log_message "エラー: ファイル $1 が存在しません"
        exit 1
    fi
}

# ディレクトリの存在をチェックする関数
check_dir_exists() {
    if [ ! -d "$1" ]; then
        log_message "エラー: ディレクトリ $1 が存在しません"
        exit 1
    fi
}

# ディレクトリを作成する関数
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        log_message "ディレクトリを作成しました: $1"
    fi
}

# エラーを処理する関数
handle_error() {
    log_message "エラーが発生しました: $1"
    exit 1
}

# 転送結果ファイルの存在確認
check_transfer_result() {
    if [ -f "$TRANSFER_RESULT_FILE" ]; then
        log_message "転送結果ファイルのチェックが完了しました"
    else
        log_message "警告: 転送結果ファイルが見つかりません: $TRANSFER_RESULT_FILE"
    fi
}

# シェープファイル複写
copy_shape_files() {
    log_message "シェープファイルの複写を開始します"
    
    # 8系店舗と9系店舗の配列
    stores_8=(2010000 2020000 2030000 2040000 2050000 2060000 2070000 2140000)
    stores_9=(2080000 2090000)
    
    for store in "${stores_8[@]}" "${stores_9[@]}"; do
        source_dir="${SHAPE_FILES_ROOT}/${store}"
        target_dir="${WORK_DIR}/${store}"
        
        if [ -d "$source_dir" ]; then
            log_message "店舗 ${store} のシェープファイルを複写します"
            
            # ディレクトリ構造を作成
            create_dir_if_not_exists "${target_dir}/大メッシュ/中メッシュ/小メッシュ"
            
            # ファイルをコピー
            find "$source_dir" -type f $$ -name "*.shp" -o -name "*.shx" -o -name "*.dbf" -o -name "*.prj" $$ -exec cp {} "${target_dir}/大メッシュ/中メッシュ/小メッシュ/" \;
            
            if [ $? -eq 0 ]; then
                log_message "店舗 ${store} のシェープファイルを正常に複写しました"
            else
                log_message "エラー: 店舗 ${store} のシェープファイルの複写に失敗しました"
            fi
        else
            log_message "警告: 店舗 ${store} のディレクトリが見つかりません: $source_dir"
        fi
    done
}

# 更新メッシュファイルリスト作成
create_update_mesh_list() {
    log_message "更新メッシュファイルリストを作成中"
    
    create_dir_if_not_exists "$(dirname "$UPDATE_MESH_LIST")"
    
    # 更新メッシュファイルリストを初期化
    : > "$UPDATE_MESH_LIST"
    
    # 各店舗のディレクトリをループ
    for store_dir in "${WORK_DIR}"/*; do
        if [ -d "$store_dir" ]; then
            store_num=$(basename "$store_dir")
            echo "${store_num}" >> "$UPDATE_MESH_LIST"
        fi
    done
    
    if [ -s "$UPDATE_MESH_LIST" ]; then
        log_message "更新メッシュファイルリストを作成しました: $UPDATE_MESH_LIST"
    else
        log_message "警告: 更新メッシュファイルリストが空です"
    fi
}

# 転送用圧縮ファイルの作成
create_transfer_compressed_file() {
    log_message "転送用圧縮ファイルを作成中"
    create_dir_if_not_exists "$(dirname "$GIS_CHIKEI_TRANS_FILE")"
    tar -czf "$GIS_CHIKEI_TRANS_FILE" -C "$(dirname "$WORK_DIR")" "$(basename "$WORK_DIR")" "$UPDATE_MESH_LIST"
    log_message "転送用圧縮ファイルを作成しました: $GIS_CHIKEI_TRANS_FILE"
}

# シェープファイル削除
delete_shape_files() {
    log_message "シェープファイルを削除中"
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        log_message "シェープファイルを削除しました"
    else
        log_message "警告: 削除するシェープファイルが見つかりません: $WORK_DIR"
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
        log_message "GYOMU_ROOTを絶対パスに変換しました: $GYOMU_ROOT"
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
    log_message "ファイル処理を開始します"
    log_message "コンフィグファイルを読み込みました: $SHELL_PRM_FILE_PATH"

    # 処理の実行
    check_transfer_result
    copy_shape_files
    create_update_mesh_list
    create_transfer_compressed_file
    delete_shape_files
    
    log_message "ファイル処理が正常に完了しました"
}

# メインプロセスの実行（引数を渡す）
main "$@"
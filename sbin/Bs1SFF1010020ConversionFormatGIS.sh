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

# コマンドをログに記録し、実行する関数
log_and_execute() {
    local command="$1"
    log_message "DEBUG" "実行コマンド: $command"
    eval "$command"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR" "コマンドの実行に失敗しました。終了コード: $exit_code"
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
        log_message "INFO" "ディレクトリを作成しました: $1"
    fi
}

# シェープファイル収集処理
collect_shape_files() {
    log_message "INFO" "シェープファイルの収集を開始します"
    
    local copy_success=false
    
    # 2010000ディレクトリのみを検索
    if [ ! -d "${SHAPE_FILES_ROOT}/2010000" ]; then
        log_message "ERROR" "2010000 ディレクトリが見つかりません: ${SHAPE_FILES_ROOT}/2010000"
        return 1
    fi
    
    log_message "INFO" "ディレクトリを検索 : ${SHAPE_FILES_ROOT}/2010000"
    log_message "DEBUG" "SHAPE_FILES_ROOT の内容:"
    log_and_execute "ls -R \"${SHAPE_FILES_ROOT}\""
    
    # 図面番号ディレクトリを検索
    for mesh_dir in "${SHAPE_FILES_ROOT}/2010000"/*; do
        if [ ! -d "$mesh_dir" ]; then
            log_message "DEBUG" "スキップされたディレクトリ: $mesh_dir"
            continue
        fi
        
        local mesh_number=$(basename "$mesh_dir")
        local target_dir="${WORK_DIR}/${mesh_number}"
        log_message "INFO" "シェープファイルを複写します: $mesh_dir -> $target_dir"
        
        # ディレクトリ構造を作成
        create_dir_if_not_exists "$target_dir"
        
        # findコマンドを構築
        local find_command="find \"$mesh_dir\" -type f -regex \".*\.\(shp\|shx\|dbf\|prj\|fix\)$\" -exec cp {} \"$target_dir/\" \\;"
        log_message "DEBUG" "find コマンドを実行: $find_command"
        
        # ファイルをコピー
        if log_and_execute "$find_command"; then
            log_message "INFO" "図面番号 ${mesh_number} のシェープファイルを正常に複写しました"
            copy_success=true
        else
            log_message "ERROR" "図面番号 ${mesh_number} のシェープファイルの複写に失敗しました"
            log_message "DEBUG" "失敗したディレクトリの内容:"
            log_and_execute "ls -R \\"$mesh_dir\\""
        fi
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
    log_and_execute ": > \"$UPDATE_MESH_LIST\""
    
    # 各図面番号のディレクトリをループ
    log_message "INFO" "各図面番号のディレクトリをループ"
    local list_created=false
    for mesh_dir in "${WORK_DIR}"/*; do
        if [ -d "$mesh_dir" ]; then
            mesh_number=$(basename "$mesh_dir")
            log_and_execute "echo \"${mesh_number}\" >> \"$UPDATE_MESH_LIST\""
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
    if log_and_execute "tar -czf \"$GIS_CHIKEI_TRANS_FILE\" -C \"$(dirname "$WORK_DIR")\" \"$(basename "$WORK_DIR")\" \"$UPDATE_MESH_LIST\""; then
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
        if log_and_execute "rm -rf \"$WORK_DIR\""; then
            log_message "INFO" "シェープファイルを削除しました"
        else
            log_message "ERROR" "シェープファイルの削除に失敗しました"
            return 1
        fi
    else
        log_message "WARN" "削除するシェープファイルが見つかりません: $WORK_DIR"
    fi
}

# 転送済みファイルのバックアップ
backup_transferred_file() {
    log_message "INFO" "転送済みファイルのバックアップを開始します"
    
    local backup_dir="${BACKUP_DIR}"
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="${backup_dir}/B003KY_${timestamp}.tar.gz"
    local transfer_result_backup="${backup_dir}/B003KyouyoTensoInfo.dat_${timestamp}"
    
    # バックアップディレクトリの作成
    create_dir_if_not_exists "$backup_dir"
    
    # 転送用圧縮ファイルのバックアップ
    if [ -f "$GIS_CHIKEI_TRANS_FILE" ]; then
        if log_and_execute "cp \"$GIS_CHIKEI_TRANS_FILE\" \"$backup_file\""; then
            log_message "INFO" "転送用圧縮ファイルをバックアップしました: $backup_file"
        else
            log_message "ERROR" "転送用圧縮ファイルのバックアップに失敗しました"
            return 1
        fi
    else
        log_message "WARN" "転送用圧縮ファイルが見つかりません: $GIS_CHIKEI_TRANS_FILE"
    fi
    
    # 転送指示結果ファイルのバックアップ
    if [ -f "$TRANSFER_RESULT_FILE" ]; then
        if log_and_execute "cp \"$TRANSFER_RESULT_FILE\" \"$transfer_result_backup\""; then
            log_message "INFO" "転送指示結果ファイルをバックアップしました: $transfer_result_backup"
        else
            log_message "ERROR" "転送指示結果ファイルのバックアップに失敗しました"
            return 1
        fi
    else
        log_message "WARN" "転送指示結果ファイルが見つかりません: $TRANSFER_RESULT_FILE"
    fi
    
    # 古いバックアップの削除（3世代より古いファイル）
    local files_to_keep=6  # 2ファイル * 3世代
    log_and_execute "ls -t \"$backup_dir\"/B003KY_*.tar.gz \"$backup_dir\"/B003KyouyoTensoInfo.dat_* 2>/dev/null | tail -n +$((files_to_keep + 1)) | xargs -r rm"
    log_message "INFO" "3世代より古いバックアップを削除しました"
}

# 転送指示結果ファイルの処理
process_transfer_instruction_result() {
    log_message "INFO" "転送指示結果ファイルの処理を開始します"

    if [ ! -f "$TRANSFER_RESULT_FILE" ]; then
        log_message "ERROR" "転送指示結果ファイルが見つかりません: $TRANSFER_RESULT_FILE"
        return 1
    fi

    log_message "DEBUG" "転送指示結果ファイルの内容:"
    log_and_execute "cat \"$TRANSFER_RESULT_FILE\""

    # 転送指示結果ファイルの読み込み
    local file_content=$(cat "$TRANSFER_RESULT_FILE")
    IFS=',' read -r file_name update_date local_file remote_file status comment timestamp <<< "$file_content"

    log_message "DEBUG" "ファイル名: $file_name"
    log_message "DEBUG" "更新日: $update_date"
    log_message "DEBUG" "ステータス: $status"

    # ステータスの確認
    if [ "$status" = "0" ]; then
        log_message "INFO" "転送が正常に完了しました（ステータス: $status）"
    else
        log_message "ERROR" "転送中にエラーが発生しました（ステータス: $status）"
    fi

    # 転送指示結果ファイルの削除
    if log_and_execute "rm \"$TRANSFER_RESULT_FILE\""; then
        log_message "INFO" "転送指示結果ファイルを削除しました: $TRANSFER_RESULT_FILE"
    else
        log_message "ERROR" "転送指示結果ファイルの削除に失敗しました: $TRANSFER_RESULT_FILE"
        return 1
    fi

    log_message "INFO" "転送指示結果ファイルの処理が完了しました"
}

# 転送指示情報の更新
update_transfer_instruction_info() {
    log_message "INFO" "転送指示情報の更新処理を開始します"

    if [ ! -f "$TRANSFER_RESULT_FILE" ]; then
        log_message "ERROR" "転送指示結果ファイルが見つかりません: $TRANSFER_RESULT_FILE"
        return 1
    fi

    log_message "DEBUG" "転送指示結果ファイルの内容:"
    log_and_execute "cat \"$TRANSFER_RESULT_FILE\""

    # 転送指示結果ファイルの最後の行を読み込む
    local last_line=$(tail -n 1 "$TRANSFER_RESULT_FILE")
    
    IFS=',' read -r file_name update_date local_file remote_file status comment timestamp <<< "$last_line"
    
    # タイムスタンプの修正
    timestamp=$(echo "$timestamp" | cut -c 1-14)
    
    log_message "INFO" "ステータス: $status"
    log_message "DEBUG" "修正後のタイムスタンプ: $timestamp"

    # ステータスが「0：正常終了」以外かチェック
    if [ "$status" != "0" ]; then
        log_message "INFO" "ステータスが正常終了以外です。転送指示情報ファイルを更新します"
        
        # 新しい行を作成
        local new_line="$file_name,$update_date,$local_file,$remote_file,$status,$comment,$timestamp"
        
        # 転送指示情報ファイルを更新
        echo "$new_line" > "$TRANSFER_INFO_FILE"
        log_message "INFO" "転送指示情報ファイルを更新しました: $TRANSFER_INFO_FILE"
    else
        log_message "INFO" "ステータスが正常終了です。転送指示情報ファイルの更新はスキップします"
    fi

    log_message "INFO" "転送指示情報の更新処理が完了しました"
}

# メインプロセス
main() {
    # 初期化エラーをキャッチするための一時的なログ関数
    temp_log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2"
    }

    temp_log "INFO" "（1）起動引数の個数チェック"
    # 環境情報ファイルのパスを引数から取得
    if [ $# -eq 0 ]; then
        echo "エラー: 環境情報ファイルのパスが指定されていません"
        exit 1
    fi

    temp_log "INFO" "（2）設定パラメータ設定"
    SHELL_PRM_FILE_PATH="$1"
    if [ ! -f "$SHELL_PRM_FILE_PATH" ]; then
        echo "エラー: コンフィグファイル $SHELL_PRM_FILE_PATH が存在しません"
        exit 1
    fi

    # コンフィグファイルの読み込み
    source "$SHELL_PRM_FILE_PATH"

    # ログファイルのディレクトリを作成
    mkdir -p "$(dirname "$LOG_FILE")"

    # これ以降、log_message 関数が使用可能になる

    log_message "INFO" "（3）バッチ処理共通定義の読み込み"
    # バッチ処理共通定義ファイルのパスを設定
    ${GYOMU_ROOT}/config/Bs1SFF1010020CommonDef.sh

    log_message "INFO" "（4）環境情報ファイルの存在チェック"
    if [ ! -f "$SHELL_PRM_FILE_PATH" ]; then
        temp_log "ERROR" "環境情報ファイルが存在しません: $SHELL_PRM_FILE_PATH"
        exit 1
    fi

    log_message "INFO" "（5）環境情報ファイルの読み込み"

    log_message "INFO" "環境情報ファイルを読み込みました: $SHELL_PRM_FILE_PATH"

    log_message "INFO" "（6）業務変数の定義"
    JOB_NAME="EAM (GIS) 提供用転送形式変換 (地形図)"

    # 必須パラメータの確認
    required_params=(
        "LOG_FILE" "SHAPE_FILES_ROOT" "WORK_DIR" "UPDATE_MESH_LIST"
        "TRANSFER_RESULT_FILE" "TRANSFER_INFO_FILE" "GIS_CHIKEI_TRANS_FILE"
        "BACKUP_DIR" "GYOMU_ROOT"
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
    BACKUP_DIR="$GYOMU_ROOT/$BACKUP_DIR"


    log_message "INFO" "（7）開始メッセージ出力"
    log_message "INFO" "$JOB_NAME を開始します。"

    log_message "INFO" "（8）転送指示結果ファイル存在チェック"
    if [ ! -f "$TRANSFER_RESULT_FILE" ]; then
        log_message "WARN" "S1ZZZZW0002 ファイル未存在。$TRANSFER_RESULT_FILE"
        log_message "INFO" "転送指示結果ファイルが存在しないため、処理をスキップして正常終了します。"
        exit 100  # 特別な終了コードを使用
    fi

    log_message "INFO" "（9）ファイル圧縮用ワークディレクトリ削除"
    if [ -d "$WORK_DIR" ]; then
        if rm -rf "$WORK_DIR"; then
            log_message "INFO" "ファイル圧縮用ワークディレクトリを削除しました: $WORK_DIR"
        else
            log_message "ERROR" "ファイル圧縮用ワークディレクトリの削除に失敗しました: $WORK_DIR"
        fi
    else
        log_message "INFO" "削除するファイル圧縮用ワークディレクトリが存在しません: $WORK_DIR"
    fi

    log_message "INFO" "（10）転送指示結果ファイル読込み"
    if [ -f "$TRANSFER_RESULT_FILE" ]; then
        # ファイルの内容を読み込む処理をここに追加
        log_message "INFO" "転送指示結果ファイルを読み込みました: $TRANSFER_RESULT_FILE"
    else
        log_message "WARN" "転送指示結果ファイルが存在しないため、読み込みをスキップします"
    fi

    log_message "INFO" "（11）転送済みファイルバックアップ"
    backup_transferred_file || log_message "ERROR" "転送済みファイルのバックアップに失敗しました"

    log_message "INFO" "（12）転送指示情報ファイル更新"
    update_transfer_instruction_info || log_message "ERROR" "転送指示情報ファイルの更新に失敗しました"

    log_message "INFO" "（13）シェープファイル収集"
    collect_shape_files || log_message "ERROR" "シェープファイルの収集に失敗しました"

    log_message "INFO" "（14）更新メッシュファイルリスト作成"
    create_update_mesh_list || log_message "ERROR" "更新メッシュファイルリストの作成に失敗しました"

    log_message "INFO" "（15）転送用圧縮ファイルの作成"
    create_transfer_compressed_file || log_message "ERROR" "転送用圧縮ファイルの作成に失敗しました"

    log_message "INFO" "（16）転送指示情報ファイル更新"
    update_transfer_instruction_info || log_message "ERROR" "転送指示情報ファイルの更新に失敗しました"

    log_message "INFO" "（17）シェープファイル削除"
    delete_shape_files || log_message "ERROR" "シェープファイルの削除に失敗しました"

    log_message "INFO" "（18）転送指示結果ファイル削除"
    if [ -f "$TRANSFER_RESULT_FILE" ]; then
        if rm "$TRANSFER_RESULT_FILE"; then
            log_message "INFO" "転送指示結果ファイルを削除しました: $TRANSFER_RESULT_FILE"
        else
            log_message "ERROR" "転送指示結果ファイルの削除に失敗しました: $TRANSFER_RESULT_FILE"
        fi
    else
        log_message "WARN" "削除する転送指示結果ファイルが存在しません: $TRANSFER_RESULT_FILE"
    fi

    log_message "INFO" "（19）終了処理"
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
log_message "INFO" "スクリプトの実行が完了しました。"  # この行を追加
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

# シェープファイル収集処理
collect_shape_files() {
    log_message "TRACE" "collect_shape_files() start"
    log_message "DEBUG" "シェープファイルの収集を開始します"
    
    local copy_success=false
    
    # 更新メッシュファイルリストを初期化
    log_message "DEBUG" "更新メッシュファイルリストを初期化"
    create_dir_if_not_exists "$(dirname "$GIS_CHIKEI_MESH_FILE")"
    log_and_execute ": > \"$GIS_CHIKEI_MESH_FILE\""
    
    # 支店番号ディレクトリを検索
    local shiten_dirs=(2010000 2020000 2030000 2040000 2050000 2060000 2070000 2080000 2090000 2140000)
    
    for shiten_dir in "${shiten_dirs[@]}"; do
        if [ ! -d "${GIS_CHIKEI_SHAPE_DIR}/$shiten_dir" ]; then
            log_message "WARN" "$shiten_dir ディレクトリが見つかりません: ${GIS_CHIKEI_SHAPE_DIR}/$shiten_dir"
            continue
        fi
        
        log_message "DEBUG" "ディレクトリを検索 : ${GIS_CHIKEI_SHAPE_DIR}/$shiten_dir"
        log_message "DEBUG" "${GIS_CHIKEI_SHAPE_DIR}/$shiten_dir の内容:"
        log_and_execute "ls -R \"${GIS_CHIKEI_SHAPE_DIR}/$shiten_dir\""
        
        # システムディレクトリを決定
        local sys_dir
        if [ "$shiten_dir" = "2080000" ] || [ "$shiten_dir" = "2090000" ]; then
            sys_dir="sys08"
        else
            sys_dir="sys09"
        fi
        # 動的に変数名を生成し、その値を取得
        local mesh_seigen_key="GIS_CHIKEI_MESH_${shiten_dir}"
        local mesh_seigen_value="${!mesh_seigen_key}"
        
        log_message "INFO" "${mesh_seigen_key}: ${mesh_seigen_value}"

        local processed_mesh_count=0

        # 図面番号ディレクトリを検索
        for mesh_dir in "${GIS_CHIKEI_SHAPE_DIR}/$shiten_dir"/*; do
            if [ ! -d "$mesh_dir" ]; then
                log_message "DEBUG" "スキップされたディレクトリ: $mesh_dir"
                continue
            fi
            
            local mesh_number=$(basename "$mesh_dir")
            
            # メッシュ番号から大メッシュ、中メッシュ、小メッシュを抽出
            local large_mesh=${mesh_number:0:3}
            local medium_mesh=${mesh_number:3:2}
            local small_mesh=${mesh_number:5:2}
            
            local target_dir="${GIS_CHIKEI_TRANS_WORK_DIR}/${sys_dir}/${large_mesh}/${medium_mesh}/${small_mesh}"
            log_message "DEBUG" "シェープファイルを複写します: $mesh_dir -> $target_dir"
            
            # ディレクトリ構造を作成
            create_dir_if_not_exists "$target_dir"
            
            # findコマンドを構築
            local find_command="find \"$mesh_dir\" -type f -regex \".*\.\(shp\|shx\|dbf\|prj\|fix\)$\" -exec cp {} \"$target_dir/\" \\;"
            log_message "DEBUG" "find コマンドを実行: $find_command"
            
            # ファイルをコピー
            if log_and_execute "$find_command"; then
                log_message "DEBUG" "図面番号 ${mesh_number} のシェープファイルを正常に複写しました"
                # 更新メッシュファイルリストに図面番号を追加
                log_and_execute "echo \"${mesh_number}\" >> \"$GIS_CHIKEI_MESH_FILE\""
                log_message "DEBUG" "更新メッシュファイルリストに追加: $mesh_number"
                copy_success=true
                
                ((processed_mesh_count++))
                log_message "DEBUG" "処理済みメッシュ数: $processed_mesh_count / $mesh_seigen_value"
                if [ "$processed_mesh_count" -ge "$mesh_seigen_value" ]; then
                    log_message "INFO" "支店 $shiten_dir の制限値 $mesh_seigen_value に達しました。次の支店に移ります。"
                    break
                fi                
            else
                log_message "ERROR" "図面番号 ${mesh_number} のシェープファイルの複写に失敗しました"
                log_message "DEBUG" "失敗したディレクトリの内容:"
                log_and_execute "ls -R \\"$mesh_dir\\""
            fi
        done
    done
    
    # 更新メッシュファイルリストの確認
    if [ -s "$GIS_CHIKEI_MESH_FILE" ]; then
        log_message "DEBUG" "更新メッシュファイルリストを作成しました: $GIS_CHIKEI_MESH_FILE"
    else
        log_message "ERROR" "更新メッシュファイルリストが空です"
        return 1
    fi
    
    if [ "$copy_success" = false ]; then
        log_message "ERROR" "シェープファイルの複写に失敗しました"
        return 1
    fi
    
    log_message "DEBUG" "シェープファイルの収集が完了しました"
    log_message "TRACE" "collect_shape_files() end"
    return 0
}

# 更新メッシュファイルリスト作成
create_update_mesh_list() {
    log_message "DEBUG" "作成した更新メッシュリストから重複した図面番号を削除してソートする"
    
    if [ ! -f "$GIS_CHIKEI_MESH_FILE" ]; then
        log_message "ERROR" "更新メッシュファイルリストが見つかりません: $GIS_CHIKEI_MESH_FILE"
        return 1
    fi
    
    # 一時ファイルを作成
    local temp_file="${GIS_CHIKEI_MESH_FILE}.tmp"
    
    # ファイルをソートし、重複を削除
    if sort -u "$GIS_CHIKEI_MESH_FILE" > "$temp_file"; then
        log_message "DEBUG" "更新メッシュファイルリストをソートし、重複を削除しました"
        
        # 元のファイルを一時ファイルで置き換え
        if mv "$temp_file" "$GIS_CHIKEI_MESH_FILE"; then
            log_message "DEBUG" "更新メッシュファイルリストを更新しました: $GIS_CHIKEI_MESH_FILE"
            
            # 処理結果の確認
            local line_count=$(wc -l < "$GIS_CHIKEI_MESH_FILE")
            log_message "DEBUG" "更新メッシュファイルリストの行数: $line_count"
            
            if [ "$line_count" -gt 0 ]; then
                log_message "DEBUG" "更新メッシュファイルリストの内容:"
                log_and_execute "cat \"$GIS_CHIKEI_MESH_FILE\""
                return 0
            else
                log_message "ERROR" "更新メッシュファイルリストが空です"
                return 1
            fi
        else
            log_message "ERROR" "更新メッシュファイルリストの更新に失敗しました"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_message "ERROR" "更新メッシュファイルリストの処理に失敗しました"
        rm -f "$temp_file"
        return 1
    fi
}

# 転送用圧縮ファイルの作成
create_transfer_compressed_file() {
    log_message "TRACE" "create_transfer_compressed_file() start"
    log_message "DEBUG" "転送用圧縮ファイルを作成中"
    create_dir_if_not_exists "$(dirname "$GIS_CHIKEI_TRANS_COMP_FILE")"
    
    # 現在のディレクトリを保存
    local current_dir=$(pwd)
        
    # WORK_DIRに移動してtar作成
    cd "$GIS_CHIKEI_TRANS_WORK_DIR" || return 1
    log_message "TRACE" "create_transfer_compressed_file() end"    
    if log_and_execute "tar -czf \"$GIS_CHIKEI_TRANS_COMP_FILE\" *"; then
        log_message "DEBUG" "転送用圧縮ファイルを作成しました: $GIS_CHIKEI_TRANS_COMP_FILE"
        cd "$current_dir" || return 1
        return 0
    else
        log_message "ERROR" "転送用圧縮ファイルの作成に失敗しました"
        rm -f "$(basename "$GIS_CHIKEI_MESH_FILE")"  # コピーしたメッシュリストを削除
        cd "$current_dir" || return 1
        return 1
    fi
}

# シェープファイル削除
delete_shape_files() {
    log_message "TRACE" "delete_shape_files() start"
    log_message "DEBUG" "シェープファイルを削除中"

    # 更新メッシュ一覧ファイルの存在確認
    if [ ! -f "$GIS_CHIKEI_MESH_FILE" ]; then
        log_message "ERROR" "更新メッシュ一覧ファイルが見つかりません: $GIS_CHIKEI_MESH_FILE"
        return 1
    fi

    # 更新メッシュ一覧ファイルから図面番号を読み込み
    log_message "DEBUG" "更新メッシュ一覧ファイルから図面番号を読み込みます"
    local mesh_numbers=()
    while IFS= read -r mesh_number; do
        mesh_numbers+=("$mesh_number")
    done < "$GIS_CHIKEI_MESH_FILE"

    if [ ${#mesh_numbers[@]} -eq 0 ]; then
        log_message "ERROR" "更新メッシュ一覧ファイルが空です"
        return 1
    fi

    log_message "DEBUG" "削除対象の図面番号: ${mesh_numbers[*]}"

    # 支店ディレクトリごとに処理
    local shiten_dirs=(2010000 2020000 2030000 2040000 2050000 2060000 2070000 2080000 2090000 2140000)
    
    for shiten_dir in "${shiten_dirs[@]}"; do
        if [ ! -d "${GIS_CHIKEI_SHAPE_DIR}/$shiten_dir" ]; then
            continue
        fi

        log_message "DEBUG" "支店ディレクトリを処理中: $shiten_dir"

        # 各図面番号について処理
        for mesh_number in "${mesh_numbers[@]}"; do
            local target_dir="${GIS_CHIKEI_SHAPE_DIR}/${shiten_dir}/${mesh_number}"
            
            if [ -d "$target_dir" ]; then
                log_message "DEBUG" "図面番号 $mesh_number のディレクトリを削除します: $target_dir"
                if rm -rf "$target_dir"; then
                    log_message "DEBUG" "図面番号 $mesh_number のディレクトリを削除しました"
                else
                    log_message "ERROR" "図面番号 $mesh_number のディレクトリの削除に失敗しました"
                    return 1
                fi
            fi
        done
    done

    # ファイル圧縮用ワークディレクトリの削除
    if [ -d "$GIS_CHIKEI_TRANS_WORK_DIR" ]; then
        log_message "DEBUG" "ファイル圧縮用ワークディレクトリを削除: $GIS_CHIKEI_TRANS_WORK_DIR"
        if log_and_execute "rm -rf \"$GIS_CHIKEI_TRANS_WORK_DIR\""; then
            log_message "DEBUG" "ワークディレクトリを削除しました"
        else
            log_message "ERROR" "ワークディレクトリの削除に失敗しました"
            return 1
        fi
    else
        log_message "WARN" "削除するワークディレクトリが見つかりません: $GIS_CHIKEI_TRANS_WORK_DIR"
    fi

    log_message "TRACE" "delete_shape_files() end"
    return 0
}

# 転送済みファイルのバックアップ
backup_transferred_file() {
    log_message "TRACE" "backup_transferred_file() start"
    log_message "DEBUG" "転送済みファイルのバックアップを開始します"
    
    # 転送指示結果ファイルの存在確認
    if [ ! -f "$GIS_CHIKEI_TRANS_RESULT_FILE" ]; then
        log_message "ERROR" "転送指示結果ファイルが見つかりません: $GIS_CHIKEI_TRANS_RESULT_FILE"
        return 1
    fi

    # バックアップディレクトリの作成
    local backup_dir="${GIS_CHIKEI_TRANS_BACK_DIR}"
    create_dir_if_not_exists "$backup_dir"

    # 転送指示結果ファイルのバックアップ名を生成（日付サフィックス付き）
    local current_date=$(date +%Y%m%d%H%M%S)
    local result_backup_name="${GIS_CHIKEI_TRANS_FILE_NAME}_${current_date}"
    
    # 転送指示結果ファイルをバックアップ
    if cp "$GIS_CHIKEI_TRANS_RESULT_FILE" "$backup_dir/$result_backup_name"; then
        log_message "DEBUG" "転送指示結果ファイルをバックアップしました: $backup_dir/$result_backup_name"
    else
        log_message "ERROR" "転送指示結果ファイルのバックアップに失敗しました"
        return 1
    fi

    # 転送指示結果ファイルを1行ずつ処理
    while IFS=',' read -r registration_number card_name local_file remote_file status comment timestamp || [ -n "$remote_file" ]; do
        # ステータスが連携済み（1）かチェック
        if [ "$status" != "1" ]; then
            log_message "INFO" "ファイルは連携済みではありません。スキップします: $remote_file"
            continue
        fi

        # リモートファイルの存在確認
        if [ ! -f "$remote_file" ]; then
            log_message "WARN" "バックアップ対象のファイルが見つかりません: $remote_file"
            continue
        fi

        # リモートファイルをバックアップディレクトリに移動
        if mv "$remote_file" "$backup_dir/"; then
            log_message "DEBUG" "連携済みファイルをバックアップしました: $remote_file -> $backup_dir/"
        else
            log_message "ERROR" "連携済みファイルのバックアップに失敗しました: $remote_file"
            return 1
        fi
    done < "$GIS_CHIKEI_TRANS_RESULT_FILE"

    # 3世代より古いバックアップの削除
    # 圧縮ファイルのバックアップ
    local tar_backup_files=("$GIS_CHIKEI_TRANS_BACK_DIR"/*.tar.gz)
    if [ ${#tar_backup_files[@]} -gt $GIS_CHIKEI_COMP_BAK_SEDAI ]; then
        IFS=$'\n' sorted_tar_files=($(ls -t "${tar_backup_files[@]}"))
        for old_file in "${sorted_tar_files[@]:$GIS_CHIKEI_COMP_BAK_SEDAI}"; do
            rm "$old_file"
            log_message "DEBUG" "古い圧縮ファイルバックアップを削除しました: $old_file"
        done
    fi

    # 転送指示結果ファイルのバックアップ
    local result_backup_files=("$GIS_CHIKEI_TRANS_BACK_DIR"/${GIS_CHIKEI_TRANS_FILE_NAME}_*)
    if [ ${#result_backup_files[@]} -gt $GIS_CHIKEI_COMP_BAK_SEDAI ]; then
        IFS=$'\n' sorted_result_files=($(ls -t "${result_backup_files[@]}"))
        for old_file in "${sorted_result_files[@]:$GIS_CHIKEI_COMP_BAK_SEDAI}"; do
            rm "$old_file"
            log_message "DEBUG" "古い転送指示結果ファイルバックアップを削除しました: $old_file"
        done
    fi

    log_message "DEBUG" "バックアップを3世代まで保持しました"
    log_message "DEBUG" "転送済みファイルのバックアップが完了しました"
    log_message "TRACE" "backup_transferred_file() end"
    return 0
}

# 転送指示情報の更新
update_transfer_instruction_info() {
    log_message "TRACE" "update_transfer_instruction_info() start"
    log_message "DEBUG" "転送指示情報の更新処理を開始します"

    if [ ! -f "$GIS_CHIKEI_TRANS_RESULT_FILE" ]; then
        log_message "ERROR" "転送指示結果ファイルが見つかりません: $GIS_CHIKEI_TRANS_RESULT_FILE"
        return 1
    fi

    log_message "DEBUG" "転送指示結果ファイルの内容:"
    log_and_execute "cat \"$GIS_CHIKEI_TRANS_RESULT_FILE\""

    # 転送指示情報ファイルを初期化
    > "$GIS_CHIKEI_TRANS_INFO_FILE"

    # 転送指示結果ファイルを1行ずつ処理
    while IFS=',' read -r registration_number card_name local_file remote_file status comment timestamp || [ -n "$remote_file" ]; do
        # タイムスタンプの修正
        timestamp=$(echo "$timestamp" | cut -c 1-14)
        
        # ステータスが「1：連携済み」以外かチェック
        if [ "$status" != "1" ]; then
            log_message "DEBUG" "ステータスが連携済み以外です。転送指示情報ファイルに追加します"
            
            # 新しい行を作成
            # 転送指示情報ファイルのステータスは0固定
            local new_line="$registration_number,$card_name,$local_file,$remote_file,0,$comment,$timestamp"
            
            # 転送指示情報ファイルに追加
            echo "$new_line" >> "$GIS_CHIKEI_TRANS_INFO_FILE"
            log_message "DEBUG" "転送指示情報ファイルに追加しました: $remote_file"
        else
            log_message "DEBUG" "ステータスが連携済みです。このファイルはスキップします: $remote_file"
        fi
    done < "$GIS_CHIKEI_TRANS_RESULT_FILE"

    if [ -s "$GIS_CHIKEI_TRANS_INFO_FILE" ]; then
        log_message "DEBUG" "転送指示情報ファイルが更新されました: $GIS_CHIKEI_TRANS_INFO_FILE"
    else
        log_message "DEBUG" "転送指示情報ファイルの更新はありませんでした"
    fi

    log_message "DEBUG" "転送指示情報の更新処理が完了しました"
    log_message "TRACE" "update_transfer_instruction_info() end"
}

# 転送指示情報の更新
update_transfer_instruction_info_after() {
    log_message "TRACE" "update_transfer_instruction_info_after() start"
    log_message "DEBUG" "転送指示情報の更新処理を開始します"

    # 転送用圧縮ファイルの存在確認
    if [ ! -f "$GIS_CHIKEI_TRANS_COMP_FILE" ]; then
        log_message "ERROR" "転送用圧縮ファイルが見つかりません: $GIS_CHIKEI_TRANS_COMP_FILE"
        return 1
    fi

    # 転送用圧縮ファイル名から情報を抽出
    local file_name=$(basename "$GIS_CHIKEI_TRANS_COMP_FILE")
    local timestamp=$(date -r "$GIS_CHIKEI_TRANS_COMP_FILE" +%Y%m%d%H%M%S)
    
    log_message "DEBUG" "ファイル名: $file_name"
    log_message "DEBUG" "タイムスタンプ: $timestamp"

    # 転送指示情報ファイルのディレクトリを作成
    create_dir_if_not_exists "$(dirname "$GIS_CHIKEI_TRANS_INFO_FILE")"

    # 登録番号を計算（ファイル内の現在のレコード数 + 1）
    local registration_number=1
    if [ -f "$GIS_CHIKEI_TRANS_INFO_FILE" ]; then
        registration_number=$(wc -l < "$GIS_CHIKEI_TRANS_INFO_FILE")
        ((registration_number++))
    fi
    
    # 伝送カード名
    local card_name=$GIS_CHIKEI_DENSO_CARD
    
    # ローカルファイル名
    local local_file="$GIS_CHIKEI_GIS_COMP_DIR$file_name"
    
    # リモートファイル名
    local remote_file="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_COMP_DIR/$file_name"
    
    # ステータス（0固定 0：未連携、1：連携済み）
    local status="0"
    
    # コメント（chikei固定）
    local comment="chikei"

    # 新しい行を作成（フォーマット: 登録番号,伝送カード名,ローカルファイル名,リモートファイル名,ステータス,コメント,タイムスタンプ）
    local new_line="$registration_number,$card_name,$local_file,$remote_file,$status,$comment,$timestamp"
    
    # 転送指示情報ファイルに追加
    echo "$new_line" >> "$GIS_CHIKEI_TRANS_INFO_FILE"
    
    if [ $? -eq 0 ]; then
        log_message "DEBUG" "転送指示情報ファイルを更新しました: $GIS_CHIKEI_TRANS_INFO_FILE"
        log_message "DEBUG" "追加したレコード: $new_line"
    else
        log_message "ERROR" "転送指示情報ファイルの更新に失敗しました"
        return 1
    fi

    log_message "DEBUG" "転送指示情報の更新処理が完了しました"
    log_message "TRACE" "update_transfer_instruction_info_after() end"
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
    if [ ! -f "$SHELL_PRM_FILE_PATH" ]; then
        log_message "ERROR" "環境情報ファイル $SHELL_PRM_FILE_PATH が存在しません"
        exit 1
    fi

    # コンフィグファイルの読み込み
    source "$SHELL_PRM_FILE_PATH"

    # これ以降、log_message 関数が使用可能になる

    log_message "TRACE" "（3）バッチ処理共通定義の読み込み"
    # バッチ処理共通定義ファイルのパスを設定
    ${GYOMU_ROOT}/config/Bs1SFF1010020CommonDef.sh

    log_message "TRACE" "（4）環境情報ファイルの存在チェック"
    if [ ! -f "$SHELL_PRM_FILE_PATH" ]; then
        temp_log "ERROR" "環境情報ファイルが存在しません: $SHELL_PRM_FILE_PATH"
        exit 1
    fi

    log_message "TRACE" "（5）環境情報ファイルの読み込み"

    log_message "DEBUG" "環境情報ファイルを読み込みました: $SHELL_PRM_FILE_PATH"

    log_message "TRACE" "（6）業務変数の定義"
    JOB_NAME="EAM (GIS) 提供用転送形式変換 (地形図)"

    # 必須パラメータの確認
    required_params=(
        "GIS_CHIKEI_SHAPE_DIR" "GIS_CHIKEI_TRANS_WORK_DIR" "GIS_CHIKEI_MESH_FILE"
        "GIS_CHIKEI_TRANS_RESULT_FILE" "GIS_CHIKEI_TRANS_INFO_FILE" "GIS_CHIKEI_TRANS_COMP_FILE"
        "GIS_CHIKEI_TRANS_BACK_DIR" "GYOMU_ROOT"
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
    GIS_CHIKEI_SHAPE_DIR="$GYOMU_ROOT/$GIS_CHIKEI_SHAPE_DIR"
    GIS_CHIKEI_TRANS_WORK_DIR="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_WORK_DIR"
    GIS_CHIKEI_MESH_FILE="$GYOMU_ROOT/$GIS_CHIKEI_MESH_FILE"
    GIS_CHIKEI_TRANS_RESULT_FILE="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_RESULT_FILE"
    GIS_CHIKEI_TRANS_INFO_FILE="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_INFO_FILE"
    GIS_CHIKEI_TRANS_COMP_FILE="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_COMP_FILE"
    GIS_CHIKEI_TRANS_BACK_DIR="$GYOMU_ROOT/$GIS_CHIKEI_TRANS_BACK_DIR"


    log_message "TRACE" "（7）開始メッセージ出力"
    log_message "INFO" "$JOB_NAME を開始します。"

    log_message "TRACE" "（8）転送指示結果ファイル存在チェック"
    if [ ! -f "$GIS_CHIKEI_TRANS_RESULT_FILE" ]; then
        log_message "WARN" "S1ZZZZW0002 ファイル未存在。$GIS_CHIKEI_TRANS_RESULT_FILE"
        log_message "INFO" "転送指示結果ファイルが存在しないため、処理をスキップして正常終了します。"
        exit 100  # 特別な終了コードを使用
    fi

    log_message "TRACE" "（9）ファイル圧縮用ワークディレクトリ削除"
    if [ -d "$GIS_CHIKEI_TRANS_WORK_DIR" ]; then
        if rm -rf "$GIS_CHIKEI_TRANS_WORK_DIR"; then
            log_message "INFO" "ファイル圧縮用ワークディレクトリを削除しました: $GIS_CHIKEI_TRANS_WORK_DIR"
        else
            log_message "ERROR" "ファイル圧縮用ワークディレクトリの削除に失敗しました: $GIS_CHIKEI_TRANS_WORK_DIR"
        fi
    else
        log_message "DEBUG" "削除するファイル圧縮用ワークディレクトリが存在しません: $GIS_CHIKEI_TRANS_WORK_DIR"
    fi

    log_message "TRACE" "（10）転送指示結果ファイル読込み"
    if [ -f "$GIS_CHIKEI_TRANS_RESULT_FILE" ]; then
        # ファイルの内容を読み込む
        local file_content
        if file_content=$(cat "$GIS_CHIKEI_TRANS_RESULT_FILE"); then
            log_message "DEBUG" "転送指示結果ファイルを読み込みました: $GIS_CHIKEI_TRANS_RESULT_FILE"
            
            # ファイルの内容を解析
            IFS=',' read -r registration_number card_name local_file remote_file status comment timestamp <<< "$file_content"
            
            log_message "DEBUG" "登録番号: $registration_number"
            log_message "DEBUG" "伝送カード名: $card_name"
            log_message "DEBUG" "ローカルファイル名: $local_file"
            log_message "DEBUG" "リモートファイル名: $remote_file"
            log_message "DEBUG" "ステータス: $status"
            log_message "DEBUG" "コメント: $comment"
            log_message "DEBUG" "タイムスタンプ: $timestamp"
            
            # ステータスの確認
            if [ "$status" = "0" ]; then
                log_message "DEBUG" "転送済み（ステータス: $status）"
            else
                log_message "DEBUG" "未転送（ステータス: $status）"
            fi
        else
            log_message "ERROR" "S1ZZZZE004 ファイルリードエラー: $GIS_CHIKEI_TRANS_RESULT_FILE"
            exit 9
        fi
    else
        log_message "ERROR" "S1ZZZZE004 ファイルリードエラー: $GIS_CHIKEI_TRANS_RESULT_FILE が存在しません"
        exit 9
    fi

    log_message "TRACE" "（11）転送済みファイルバックアップ"
    backup_transferred_file || log_message "ERROR" "転送済みファイルのバックアップに失敗しました"

    log_message "TRACE" "（12）転送指示情報ファイル更新"
    update_transfer_instruction_info || log_message "ERROR" "転送指示情報ファイルの更新に失敗しました"

    log_message "TRACE" "（13）シェープファイル収集"
    collect_shape_files || log_message "ERROR" "シェープファイルの収集に失敗しました"

    log_message "TRACE" "（14）更新メッシュファイルリスト作成"
    create_update_mesh_list || log_message "ERROR" "更新メッシュファイルリストの作成に失敗しました"

    log_message "TRACE" "（15）転送用圧縮ファイルの作成"
    create_transfer_compressed_file || log_message "ERROR" "転送用圧縮ファイルの作成に失敗しました"

    log_message "TRACE" "（16）転送指示情報ファイル更新"
    update_transfer_instruction_info_after || log_message "ERROR" "転送指示情報ファイルの更新に失敗しました"

    log_message "TRACE" "（17）シェープファイル削除"
    delete_shape_files || log_message "ERROR" "シェープファイルの削除に失敗しました"

    log_message "TRACE" "（18）転送指示結果ファイル削除"
    if [ -f "$GIS_CHIKEI_TRANS_RESULT_FILE" ]; then
        if rm "$GIS_CHIKEI_TRANS_RESULT_FILE"; then
            log_message "DEBUG" "転送指示結果ファイルを削除しました: $GIS_CHIKEI_TRANS_RESULT_FILE"
        else
            log_message "ERROR" "転送指示結果ファイルの削除に失敗しました: $GIS_CHIKEI_TRANS_RESULT_FILE"
        fi
    else
        log_message "WARN" "削除する転送指示結果ファイルが存在しません: $GIS_CHIKEI_TRANS_RESULT_FILE"
    fi

    log_message "TRACE" "（19）終了処理"
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
#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
)

NODES=(
    #"https://github.com/ltdrdata/ComfyUI-Manager"
    #"https://github.com/cubiq/ComfyUI_essentials"
)

WORKFLOWS=(

)

CHECKPOINT_MODELS=(
    #v14
    #"civitai.com/api/download/models/1761560"
    #v15
    #"civitai.com/api/download/models/2167369"
    #v16
    "civitai.com/api/download/models/2514310"
)

UNET_MODELS=(
)

LORA_MODELS=(
    #"civitai.com/api/download/models/1858609"
    #"civitai.com/api/download/models/2263757" #ass kb
    #"civitai.com/api/download/models/2263203" #hip kb
    "civitai.com/api/download/models/660065" #tug
    "civitai.com/api/download/models/1845953" #Body Type
    "civitai.com/api/download/models/1891887" #Age 
    "civitai.com/api/download/models/1785002" #Perfect 
    "civitai.com/api/download/models/1190779" #booty
    "civitai.com/api/download/models/625365" #Thigh 
    "civitai.com/api/download/models/2272010" #Thigh kb
    "civitai.com/api/download/models/1523340" #Thicc 
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function setup_syncthing_auto() {
    printf "[Syncthing] Starting setup via CLI...\n"

    # 1. ディレクトリ準備
    local SYNC_LORA_DIR="/workspace/synced_loras"
    local SYNC_OUTPUT_DIR="/workspace/synced_outputs"
    local CONF_DIR="/workspace/syncthing_conf" # 永続化しやすい場所に変更
    mkdir -p "$SYNC_LORA_DIR" "$SYNC_OUTPUT_DIR" "$CONF_DIR"
    
    # ComfyUIとのシンボリックリンク作成
    ln -sf "$SYNC_LORA_DIR" "${COMFYUI_DIR}/models/loras/synced"
    if [ -d "${COMFYUI_DIR}/output" ] && [ ! -L "${COMFYUI_DIR}/output" ]; then
        rm -rf "${COMFYUI_DIR}/output"
    fi
    ln -sf "$SYNC_OUTPUT_DIR" "${COMFYUI_DIR}/output"

    # 2. Syncthingを一旦バックグラウンドで起動（設定生成のため）
    # APIを叩くためにGUIアドレスを固定して起動
    /opt/syncthing/syncthing --no-browser --home="$CONF_DIR" --gui-address="0.0.0.0:18384" > /workspace/syncthing.log 2>&1 &
    
    # 起動を待機（最大30秒）
    printf "[Syncthing] Waiting for API to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:18384/rest/system/ping > /dev/null; then
            printf " Ready!\n"
            break
        fi
        sleep 1
    done

    # 3. CLIを使って設定を注入
    # APIキーを取得（CLI実行に必要）
    local API_KEY=$(grep -oP '(?<=<apikey>).*?(?=</apikey>)' "${CONF_DIR}/config.xml")
    export STGUIADDRESS="http://localhost:18384"
    export STAPIKEY="$API_KEY"

    # 自分のデバイスIDを指定（環境変数 MY_SYNCTHING_ID がある前提）
    # もし相手のIDを登録したい場合は、ここに相手のIDを入れる
    if [ -n "$MY_SYNCTHING_ID" ]; then
        printf "[Syncthing] Adding remote device: ${MY_SYNCTHING_ID}\n"
        syncthing cli config devices add --device-id "${MY_SYNCTHING_ID}" --name "My-Remote-Device"
        
        # フォルダの追加と共有設定
        printf "[Syncthing] Configuring folders...\n"
        
        # LoRA受信フォルダ (Receive Only)
        syncthing cli config folders add --id "lora_upload" --path "$SYNC_LORA_DIR"
        syncthing cli config folders "lora_upload" type set "receiveonly"
        syncthing cli config folders "lora_upload" devices add --device-id "${MY_SYNCTHING_ID}"
        
        # Output送信フォルダ (Send Only)
        syncthing cli config folders add --id "output_download" --path "$SYNC_OUTPUT_DIR"
        syncthing cli config folders "output_download" type set "sendonly"
        syncthing cli config folders "output_download" devices add --device-id "${MY_SYNCTHING_ID}"
        
        # 設定を反映させるための再起動（API経由）
        syncthing cli system restart
    else
        printf "[Syncthing] WARNING: MY_SYNCTHING_ID is not set. Skipping device auto-config.\n"
    fi
}


function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    # --- ここで先に Syncthing を起動！ ---
    setup_syncthing_auto
    
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif 
        [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]];then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi


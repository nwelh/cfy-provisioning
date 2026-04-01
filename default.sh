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
    #"civitai.com/api/download/models/2263757" #as kb
    #"civitai.com/api/download/models/2263203" #hi  kb
    "civitai.com/api/download/models/660065" #tug
    "civitai.com/api/download/models/1845953" #Body Type
    "civitai.com/api/download/models/1891887" #Age 
    "civitai.com/api/download/models/1785002" #Perfect 
    "civitai.com/api/download/models/1190779" #boot
    "civitai.com/api/download/models/625365" #Thigh 
    "civitai.com/api/download/models/2272010" #Thigh kb
    "civitai.com/api/download/models/1523340" #Thic
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function setup_syncthing_auto() {
    printf "[Syncthing] Configuring with CLI inside /workspace for persistence...\n"

    # 1. 永続化されるディレクトリの準備
    local MY_CONF_DIR="/workspace/syncthing_conf"
    local SYNC_LORA_DIR="/workspace/synced_loras"
    local SYNC_OUTPUT_DIR="/workspace/synced_outputs"
    mkdir -p "$MY_CONF_DIR" "$SYNC_LORA_DIR" "$SYNC_OUTPUT_DIR"
    
    # ComfyUIとのリンク作成
    ln -sf "$SYNC_LORA_DIR" "${COMFYUI_DIR}/models/loras/synced"
    [ -d "${COMFYUI_DIR}/output" ] && [ ! -L "${COMFYUI_DIR}/output" ] && rm -rf "${COMFYUI_DIR}/output"
    ln -sf "$SYNC_OUTPUT_DIR" "${COMFYUI_DIR}/output"

    # 2. CLIツール定義 (パスを固定して「起動前」に設定を流し込む)
    local ST_CLI="/opt/syncthing/syncthing cli 

    if [ -n "$MY_SYNCTHING_ID" ]; then
        printf "[Syncthing] Applying settings to: $MY_CONF_DIR\n"
        
        # 自分のデバイスを追加
        $ST_CLI config devices add --device-id "${MY_SYNCTHING_ID}" --name "My-Remote-PC"
        
        # フォルダ設定 (LoRA: 受信専用 / Output: 送信専用)
        $ST_CLI config folders add --id "lora_upload" --path "$SYNC_LORA_DIR"
        $ST_CLI config folders "lora_upload" type set "receiveonly"
        $ST_CLI config folders "lora_upload" devices add --device-id "${MY_SYNCTHING_ID}"
        
        $ST_CLI config folders add --id "output_download" --path "$SYNC_OUTPUT_DIR"
        $ST_CLI config folders "output_download" type set "sendonly"
        $ST_CLI config folders "output_download" devices add --device-id "${MY_SYNCTHING_ID}"

        # ネットワーク設定 (Vast.aiの外からGUIが見れるようにする)
        $ST_CLI config gui address set "0.0.0.0:18384"
        $ST_CLI config gui tls set false
        $ST_CLI config gui apikey set "vastaicomfykey123"
    fi

    # 3. 既存のSyncthingを停止させ、新しいホームディレクトリで起動
    # pkill -9 syncthing || true
    #sleep 1
    #printf "[Syncthing] Starting with custom home...\n"
    #/opt/syncthing/syncthing --no-browser --home="$MY_CONF_DIR" > /workspace/syncthing.log 2>&1 &
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


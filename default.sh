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


# --- ここから末尾に追記 ---

function setup_syncthing_auto() {
    if [[ -z "$MY_PC_ID" ]]; then
        printf "\n[Skip] MY_SYNCTHING_ID is not set.\n"
        return
    fi


    # 1. 実行ファイルのパスを定義
    local SYNC_BIN="/opt/syncthing/syncthing"
    
    # 万が一存在しない場合の予備処理（念のため）
    if [[ ! -f "$SYNC_BIN" ]]; then
        printf "[Syncthing] Not found at $SYNC_BIN. Trying apt install...\n"
        sudo apt-get update && sudo apt-get install -y syncthing
        SYNC_BIN="syncthing" # aptで入れた場合はパスが通るのでコマンド名だけでOK
    fi


    # 1. 既存の Syncthing プロセスを終了させる (二重起動防止)
    printf "\n[Syncthing] Stopping existing process if any...\n"
    pkill -x syncthing || true
    sleep 2

    # 2. 同期用実体フォルダの作成とリンク (前回と同様)
    local SYNC_LORA_DIR="/workspace/synced_loras"
    local SYNC_OUTPUT_DIR="/workspace/synced_outputs"
    mkdir -p "$SYNC_LORA_DIR" "$SYNC_OUTPUT_DIR"
    
    ln -sf "$SYNC_LORA_DIR" "${COMFYUI_DIR}/models/loras/synced"
    if [ -d "${COMFYUI_DIR}/output" ] && [ ! -L "${COMFYUI_DIR}/output" ]; then
        rm -rf "${COMFYUI_DIR}/output"
    fi
    ln -sf "$SYNC_OUTPUT_DIR" "${COMFYUI_DIR}/output"

    # 3. 設定ファイルの生成 (上書き)
    mkdir -p /root/.config/syncthing
    cat <<EOF > /root/.config/syncthing/config.xml
<configuration version="37">
    <folder id="lora_upload" label="LoRA Upload" path="$SYNC_LORA_DIR" type="receiveonly" rescanIntervalS="3600">
        <device id="$MY_PC_ID"></device>
    </folder>
    <folder id="output_download" label="ComfyUI Output" path="$SYNC_OUTPUT_DIR" type="sendonly" rescanIntervalS="60">
        <device id="$MY_PC_ID"></device>
    </folder>
    <device id="$MY_PC_ID" name="My-Desktop-PC"><address>dynamic</address></device>
    <gui enabled="true" tls="false"><address>0.0.0.0:8384</address></gui>
    <options><globalAnnounceEnabled>true</globalAnnounceEnabled></options>
</configuration>
EOF

    # 4. 新しい設定で再起動
    printf "[Syncthing] Restarting with custom config...  $SYNC_BIN\n"
    $SYNC_BIN --no-browser > /workspace/syncthing.log 2>&1 &
}

if [[ ! -f /.noprovisioning ]]; then
    #setup_syncthing_auto
fi

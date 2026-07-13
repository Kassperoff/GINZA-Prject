#!/usr/bin/env bash
set -e

#
# ============================================================
#   CONFIGURATION SECTION
# ============================================================
#
# ROOT_DIR — корень проекта BIN-FILE
# RECIPES_DIR — папка с рецептами сборки
# OUT_DIR — куда складываются бинарники после сборки
# MODULE_DIR — куда будет собран Magisk‑модуль
#

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RECIPES_DIR="$ROOT_DIR/build_script/recipes"
OUT_DIR="$ROOT_DIR/out"
MODULE_DIR="/home/$USER/g_MODULE"

#
# ANDROID_NDK — путь к NDK должен быть экспортирован заранее
# ANDROID_API — минимальный API для сборки (26 = Android 8)
#
: "${ANDROID_NDK:?ANDROID_NDK не установлен}"
: "${ANDROID_API:=26}"

#
# ============================================================
#   ARGUMENT PARSER
# ============================================================
#
# Поддерживаемые аргументы:
#   bin=<имя_пакета>
#   arch=<архитектура>
#   group=<группа_пакетов>
#   module=yes — собрать Magisk‑модуль
#   auto=yes — автозагрузка SDK/extra инструментов
#

for arg in "$@"; do
    case $arg in
        bin=*) BIN="${arg#*=}" ;;
        arch=*) ARCH="${arg#*=}" ;;
        group=*) GROUP="${arg#*=}" ;;
        module=*) MODULE="${arg#*=}" ;;
        auto=*) AUTO="${arg#*=}" ;;
    esac
done

if [ -z "$ARCH" ]; then
    echo "Ошибка: arch= не указан"
    exit 1
fi

#
# ============================================================
#   ARCH → TRIPLE (NDK toolchain)
# ============================================================
#
# Преобразуем архитектуру в triple для NDK:
#   aarch64 → aarch64-linux-android
#   armv7   → armv7a-linux-androideabi
#   i686    → i686-linux-android
#   x86_64  → x86_64-linux-android
#

case "$ARCH" in
    aarch64) TRIPLE="aarch64-linux-android" ;;
    armv7) TRIPLE="armv7a-linux-androideabi" ;;
    i686) TRIPLE="i686-linux-android" ;;
    x86_64) TRIPLE="x86_64-linux-android" ;;
    *)
        echo "Неизвестная архитектура: $ARCH"
        exit 1
        ;;
esac

#
# ============================================================
#   EXPORT COMPILERS
# ============================================================
#
# Устанавливаем CC, CXX, AR, STRIP для NDK
#

export CC="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${TRIPLE}${ANDROID_API}-clang"
export CXX="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${TRIPLE}${ANDROID_API}-clang++"
export AR="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
export STRIP="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

export CFLAGS="-O2 -fPIC"
export LDFLAGS="-static"

#
# ============================================================
#   GROUP DEFINITIONS
# ============================================================
#
# Группы позволяют собирать сразу набор утилит:
#   full, webui, devtools, android-tools, nettools
#

declare -A GROUPS

GROUPS[full]="curl wget2 aria2 tcpdump nmap iftop wavemon vim nano neovim zsh exa ripgrep fd fzf jq yq zip unzip tar zstd brotli xz cpio nginx luajit lualib busybox_httpd microhttpd aapt aapt2 zipalign apksigner adb fastboot smali baksmali dexdump"

GROUPS[webui]="nginx luajit lualib busybox_httpd microhttpd jq yq zip unzip"

GROUPS[devtools]="vim neovim nano zsh exa ripgrep fd fzf git jq yq"

GROUPS[android-tools]="aapt aapt2 zipalign apksigner adb fastboot smali baksmali dexdump"

GROUPS[nettools]="curl wget2 aria2 tcpdump nmap iftop wavemon"

#
# ============================================================
#   FUNCTION: fetch_android_tools
# ============================================================
#
# Скачивает:
#   - Android SDK build-tools (aapt, aapt2, zipalign, apksigner)
#   - Android platform-tools (adb, fastboot)
#

fetch_android_tools() {
    echo "----------------------------------------"
    echo "  Загрузка Android SDK build-tools и platform-tools"
    echo "----------------------------------------"

    SDK_DIR="$ROOT_DIR/sdk"
    mkdir -p "$SDK_DIR"
    cd "$SDK_DIR"

    if [ ! -d "build-tools-34" ]; then
        wget https://dl.google.com/android/repository/build-tools_r34-linux.zip -O bt.zip
        unzip bt.zip -d build-tools-34
        rm bt.zip
    fi

    if [ ! -d "platform-tools" ]; then
        wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip -O pt.zip
        unzip pt.zip -d platform-tools
        rm pt.zip
    fi

    echo "Android инструменты загружены."
}

#
# ============================================================
#   FUNCTION: fetch_extra_tools
# ============================================================
#
# Скачивает:
#   - smali.jar
#   - baksmali.jar
#

fetch_extra_tools() {
    echo "----------------------------------------"
    echo "  Загрузка дополнительных инструментов"
    echo "----------------------------------------"

    EXTRA_DIR="$ROOT_DIR/extra"
    mkdir -p "$EXTRA_DIR"
    cd "$EXTRA_DIR"

    if [ ! -f "smali.jar" ]; then
        wget https://github.com/JesusFreke/smali/releases/latest/download/smali.jar -O smali.jar
    fi

    if [ ! -f "baksmali.jar" ]; then
        wget https://github.com/JesusFreke/smali/releases/latest/download/baksmali.jar -O baksmali.jar
    fi

    echo "smali/baksmali загружены."
}

#
# ============================================================
#   FUNCTION: run_recipe
# ============================================================
#
# Запускает рецепт сборки:
#   recipes/<pkg>.sh
#

run_recipe() {
    local pkg="$1"
    local recipe="$RECIPES_DIR/$pkg.sh"

    if [ ! -f "$recipe" ]; then
        echo "Рецепт не найден: $recipe"
        exit 1
    fi

    echo "----------------------------------------"
    echo "  Сборка: $pkg ($ARCH)"
    echo "----------------------------------------"

    bash "$recipe" "$ARCH" "$OUT_DIR/$ARCH/bin"
}

#
# ============================================================
#   FUNCTION: make_module
# ============================================================
#
# Собирает Magisk‑модуль в /home/$USER/g_MODULE/
#

make_module() {
    echo "----------------------------------------"
    echo "  Генерация Magisk-модуля"
    echo "----------------------------------------"

    mkdir -p "$MODULE_DIR/system/bin"

    cp -af "$OUT_DIR/$ARCH/bin/"* "$MODULE_DIR/system/bin/"

    cat > "$MODULE_DIR/module.prop" <<EOF
id=ginza_tools
name=Ginza Tools
version=1.0
versionCode=1
author=Alex
description=Автоматически собранные бинарники BIN-FILE
EOF

    echo "#!/system/bin/sh" > "$MODULE_DIR/post-fs-data.sh"
    chmod 755 "$MODULE_DIR/post-fs-data.sh"

    echo "Модуль готов: $MODULE_DIR"
}

#
# ============================================================
#   MAIN EXECUTION LOGIC
# ============================================================
#

mkdir -p "$OUT_DIR/$ARCH/bin"

if [ "$AUTO" = "yes" ]; then
    fetch_android_tools
    fetch_extra_tools
fi

if [ -n "$GROUP" ]; then
    echo "Запуск группы: $GROUP"
    for pkg in ${GROUPS[$GROUP]}; do
        run_recipe "$pkg"
    done
elif [ -n "$BIN" ]; then
    run_recipe "$BIN"
else
    echo "Ошибка: ни bin= ни group= не указаны"
    exit 1
fi

if [ "$MODULE" = "yes" ]; then
    make_module
fi

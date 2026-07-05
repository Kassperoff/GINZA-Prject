#!/usr/bin/env bash

___uid=0
___gid=0
___mod=0755
___mof=0777

__q=${0%/*}


MODDIR=${__q%/*}
MODPATH="$MODDIR"
MODID=$(basename "$MODDIR")

BBX="$MODDIR/system/xbin/busybox"
XBIN="$MODDIR/system/xbin"
ZBIN="$MODDIR/zbin"
BBZ="$ZBIN/bin"

DIR_GR="$MODDIR/ginza_root"
DIR_WEB="$MODDIR/webroot"
SYSTEM_prop="$MODDIR/system.prop"

G_log="$MODDIR/glog.log"
Glogf="$MODDIR/glogf.log"

G_conf="$MODDIR/conf.prop"
TMP2="$MODDIR/TMP"

bord="+---------------------------------------------------------------+"

bord2="+---------------------------------------------------------------+
⟹ $(date +'%d-%m %H:%M') >> $(basename "$MODDIR") >> $(basename "$G_conf")
+----------------------------------------------------------------+"

ZMODID="/data/adb/modules/"
VMODID="/data/adb/modules/"
SMODID="/data/adb/modules/"

[ -f "$Glogf" ] || echo "$bord2" > "$Glogf"
[ -f "$G_log" ] || echo "$bord2" > "$G_log"

echo2() { >&2 echo "$@"; }

glog() {
    # glog {-r}|[NAME] [ICON] [TEXT]
    if [ "$1" = "bord" ]; then
        GL="$bord"
    else
        [ $# -eq 4 ] && [ "$1" = "-r" ] && cat "$G_log" >> "$Glogf" && echo "$bord2" > "$G_log" && shift
        [ $# -eq 3 ] || glog LOG er "$(echo "❌-($(date +'%d-%m %H:%M'))-[LOG]--Не верно переданы аргументы в glog! $#")" || return 1
        lgtxt=$3
        lgtime=$(date +'%d-%m %H:%M')
        case "$1" in
            pfsd)  lgname="POST-FS-DATA" ;;
            srv)   lgname="SERVICE" ;;
            cust)  lgname="CUSTOMINAZE" ;;
            test)  lgname="TEST" ;;
            core)  lgname="CORE" ;;
            *)     lgname="$1" ;;
        esac

        case "$2" in
            ok) lgicon="✅" ;;
            er) lgicon="❌" ;;
            st) lgicon="⚙️" ;;
            wr) lgicon="⚠️" ;;
            rr) lgicon="🌐" ;;
            ii) lgicon="⟹" ;;
            gp) lgicon="📍" ;;
            *)  lgicon="_" ;;
        esac
        GL="|$lgicon|($lgtime)-[$lgname]--$lgtxt"
    fi
    echo "$GL" >> "$G_log" ; echo "$GL"
    return 0
}

cache_clean() {
    glog CLEAN wr "$(echo "Чистка cache приложений запущена")"
    clean_cache_for_app() {
        local app_dir="$1"
        local pkg=$(basename "$app_dir")
        glog CLEAN ii "$(echo "чистка cache: $pkg")"
        find "$app_dir" -type d -name "cache" 2>/dev/null | while read -r cache_dir; do
            rm -rf "${cache_dir:?}/"* >/dev/null 2>&1
        done
    }

    for app_dir in /data/data/*; do
        [ -d "$app_dir" ] && clean_cache_for_app "$app_dir"
    done

    for app_dir in /data/media/0/Android/data/*; do
        [ -d "$app_dir" ] && clean_cache_for_app "$app_dir"
    done

    glog CLEAN wr "$(echo "Чистка cache приложений завершена")"
    return 0
}

arch_detect() {
     glog "INFO" ii "$(echo "_")"
    BIN_DIR="${0%/*}/bin"
    ARCH=$(getprop ro.product.cpu.abi)

    case "$ARCH" in
        arm64-v8a)

            if [ -f "$MODDIR" ]; then
                glog "INFO" ii "$(echo "_")"
                echo  >/dev/null 2>&1 &
            else
                glog "WARNING" er "$(echo "_")"
            fi
            ;;

        armeabi-v7a|armeabi)

            if [ -f "$MODDIR" ]; then
                 glog "INFO" ii "$(echo "_")"
                echo  >/dev/null 2>&1 &
            else
                glog "WARNING" er "$(echo "_")"
            fi
            ;;

        *)

            log "WARNING" "Unsupported architecture: $ARCH"
            glog "WARNING" er "$(echo "_ :$ARCH")"
            ;;
    esac
}

busybox_in() {
    local A result=0
    A=$(arch)
    glog INFO wr "$(echo "Установка BB")"
    mkdir -p "$XBIN"
    set_perm_recursive "$XBIN" 0 0 0755 0777
    chmod -R 755 "$XBIN"

    if [ "$A" = "$(echo "$A"|grep "arm64")" ]; then
        cp -f $BBZ/busybox8 $BBX
        log INFO ii "$(echo "Установки BB:arm64 ARH-$A")"
    elif [ "$A" = "$(echo "$A"|grep "armeabi")" ]; then
        cp -f $BBZ/busybox7 $BBX
        log INFO ii "$(echo "Установки BB:armeabi ARH-$A")"
    elif [ "$A" = "$(echo "$A"|grep "x86_64")" ]; then
        cp -f $BBZ/busybox64 $BBX
        log INFO ii "$(echo "Установки BB:x86_64 ARH-$A")"
    elif [ "$A" = "$(echo "$A"|grep "x86")" ]; then
        cp -f $BBZ/busybox86 $BBX
        log INFO ii "$(echo "Установки BB:x86 ARH-$A")"
    else
        log INFO er "$(echo "Ошибка установки BB! ARH-$A")"
        result=1
    fi

    chown 0:0 $BBX
    chmod 775 $BBX
    chcon u:object_r:system_file:s0 $BBX

    $BBX --install -s ${XBIN}/
    for applet in $($BBX --list); do
        ln -sf busybox "$XBIN/$applet"
    done

    glog INFO ok "$(echo "Установка BB завершена")"
    return $result
}

fullpath() {
    [ -e "$1" ] || return 1
    [ "${1:0:1}" = "/" ] && echo "$1" || {
        d=$(readlink -f "$(dirname "$1")")
        echo "${d%/}/$(basename "$1")"
    }
}

create_dir() {
    #   dir=$(fullpath "$1") mkdir -p
    mkdir -p "$1"
    chmod 0755 "$1"
    [ -d "$1" ] && return 0 || return 1
}

get_file_prop() {
    [ $# -lt 2 ] && return 1
    awk -F= -v p="${!#}" '
    BEGIN { f=0 }
    {
      if ($1 == p) {
        print substr($0, length($1) + 2); f=1
        exit
      }
    }
    END { exit (f)?0:1 }
  ' "${@:1:$#-1}"
}

set_perm() {
    [ $# -lt 4 ] && return 1
    uid=$1
    gid=$2
    mod=$3
    shift 3
    for ___; do
        chown "$uid:$gid" "$___" 2>/dev/null || chown "$uid.$gid" "$___"
        chmod "$mod" "$___"
    done
}


set_perm_recursive() {
    [ $# -lt 5 ] && return 1
    uid=$1
    gid=$2
    dmod=$3
    fmod=$4
    shift 4
    for ___; do
        if [ ! -d "$___" ]; then
            echo2 "CANT FIND: $___" && continue;
        fi
        chown -R $uid:$gid "$___" 2>/dev/null || chown -R $uid.$gid "$___"
        chmod -R $fmod "$___"
        find "$___" -type l -exec chmod $fmod {} +
        find "$___" -type d -exec chmod $dmod {} +
    done
}

inject() {
    local f r=0
    [ ! -f "$1" ] && return 1
    [ -n "$3" ] && f="$2" || {
        create_dir "$2" || return 1
        f="$2/$(basename "$1")"
    }
    if install -D "$1" "$f" >/dev/null 2>&1 || cp -prf "$1" "$f"; then
        set_perm $___uid $___gid $___mof "$f" || {
            echo2 "inject: Cant set permissions in: $f file"
            r=1
        }
    else
        echo2 "Cant inject: $f"
        r=1
    fi
    return $r
}

run() {
    file=$(fullpath "$2")
    var="$1"
    [ ! -f "$file" ] && return 1
    [ -z "$var" ] && return 1
    shift 2
    chmod +x "$file"
    setdefault "$var"
    "$("$file" "$@" 2>&1)"
}

update_file() {
    local TMP2 file fname tmp props result=0 force
    [ $# -lt 2 ] && return 1
    while [ $# -gt 0 ]; do
        case $1 in
        -force)
            force=true
            shift
            ;;
        *)
            break
            ;;
        esac
    done
    file=${!#}
    if [ ! -e "$file" ]; then
        echo "CANT FIND: $file" && return 1;
    fi
    rm -rf "$MODDIR/tmp"
    mkdir -p "$MODDIR/tmp"
    chmod 0755 "$MODDIR/tmp"
    fname=$(basename "$file")
    tmp="$MODDIR/tmp/$fname"
    props=$(awk '
   BEGIN { props = ""; delim = "\001"}
   index($0, "=") {
      props = props $0 delim;
   }
   END { if (props != "") print substr(props, 1, length(props) - 1) }
   ' "${@:1:$#-1}") && awk -v force="$force" -v fname="$fname" -v props="$props" -F= '
   BEGIN {
      exitcode = 1;
      n = split(props, kv_pairs, "\001");
      for (i = 1; i <= n; i++) {
         at = index(kv_pairs[i], "=")
         if (at) {
            keys[i] = substr(kv_pairs[i], 1, at - 1);
            values[i] = substr(kv_pairs[i], at + 1);
         }
      }
   }
   {
      for (i = 1; i <= n; i++) {
         if ($1 == keys[i]) {
            check[i] = 1
            if ($2 != values[i]) {
               $0 = substr($0, 1, index($0, "=") - 1) "=" values[i];
               print "Updated prop: " keys[i] > "/dev/stderr"
               exitcode = 0;
            }
            break;
         }
      }
      print;
   }
   END {
      if (force) {
         for (i = 1; i <= n; i++) {
            if (!check[i]) {
               print keys[i] "=" values[i];
               print "Added prop: " keys[i] > "/dev/stderr"
               exitcode = 0;
            }
         }
      }
      exit exitcode
   }
   ' "$file" >"$tmp" && {
        inject "$tmp" "$file" 1
        result=0
    } || {
        echo2 "update_file: No changes: $file"
        result=1
    }
    rm -rf "$MODDIR/tmp"
    return $result
}

update_file_string() {
    local TMP2 file fname tmp props result=0 force
    [ $# -lt 2 ] && return 1
    while [ $# -gt 0 ]; do
        case $1 in
        -force)
            force=true
            shift
            ;;
        *)
            break
            ;;
        esac
    done
    file=${!#}
    if [ ! -e "$file" ]; then echo "CANT FIND: $file" && return 1; fi
    rm -rf "$TMP2"
    mkdir -p "$TMP2"
    chmod 0755 "$TMP2"
    fname=$(basename "$file")
    tmp="$TMP2/$fname"
    printf -v props "%s\001" "${@:1:$#-1}"
    awk -v force="$force" -v fname="$fname" -v props="${props:0:-1}" -F= '
   BEGIN {
      exitcode = 1;
      n = split(props, kv_pairs, "\001");
      for (i = 1; i <= n; i++) {
         at = index(kv_pairs[i], "=")
         if (at) {
            keys[i] = substr(kv_pairs[i], 1, at - 1);
            values[i] = substr(kv_pairs[i], at + 1);
         }
      }
   }
   {
      for (i = 1; i <= n; i++) {
         if ($1 == keys[i]) {
            check[i] = 1
            if ($2 != values[i]) {
               $0 = substr($0, 1, index($0, "=") - 1) "=" values[i];
               print "Updated prop: " keys[i] > "/dev/stderr"
               exitcode = 0;
            }
            break;
         }
      }
      print;
   }
   END {
      if (force) {
         for (i = 1; i <= n; i++) {
            if (!check[i]) {
               print keys[i] "=" values[i];
               print "Added prop: " keys[i] > "/dev/stderr"
               exitcode = 0;
            }
         }
      }
      exit exitcode
   }
   ' "$file" >"$tmp" && {
        inject "$tmp" "$file" 1
        result=0
    } || {
        echo2 "update_file_string: No changes: $file"
        result=1
    }
    rm -rf "$TMP2"
    return $result
}

start_tmp() {
    rm -rf "$TMP2"
    create_dir "$TMP2"
}

end_tmp() {
    rm -rf "$TMP2"
    return 1
}

dynamic_install() {
    local f d o
    o=$(readlink -f "$1")
    [ ! -d "$o" ] && return 1
    while read f; do
        d=${f/"$o"/"$2"}
        [ -d "$f" ] && {
            create_dir "$d" || return 1
            continue
        }
        inject "$f" "$d" 1 || return 1
    done < <(find -L "$o" -mindepth 1)
}

pfsd2() {
    local dir gdir fsys fscr
    glog -r pfsd st "$(echo "START POST-FS-DATA")"
    cat $DIR_GR/sony/system.prop > "$SYSTEM_prop"
    for dir in $DIR_GR/*; do
    gdir=$(basename "$dir")
    fsys="$dir/system.prop"
    fscr="$dir/post-fs-data.sh"
        if [ "$(get_file_prop "$G_conf" "$gdir")" = 1 ]; then
            glog pfsd ii "$(echo "$gdir , включен")"
            [ -f "$fsys" ] && update_file -force "$fsys" "$SYSTEM_prop" && glog pfsd ok "$(echo "$gdir >> в system.prop")"
            if [ -f "$fscr" ]; then
                [ -x "$fscr" ] || chmod +x "$fscr"
                . "$fscr" && glog pfsd ok "$(echo "скрипт $gdir, запущен")"
            fi
        else glog pfsd ii "$(echo "$gdir, выключен")"
        fi
    done
    return 0
}

srv() {
    local dir
    for dir in $DIR_GR/*; do
        if [ "$(get_file_prop "$G_conf" "$(basename $dir)")" = 1 ]; then
            if [ -f "$dir/service.sh" ]; then
                [ -x "$dir/service.sh" ] || chmod +x "$dir/service.sh"
                . "$dir/service.sh" && glog srv ok "$(echo "скрипт $(basename $dir), запущен")"
            fi
        fi
    done
}

key_volpwd() {
    local m ID
    glog srv gp "$(echo "запущен анти-бутлуп")"
    en=0; xuong=0; pow=0; cham=0;
    while true; do
        keyvl="$(getevent -qlc 2 | awk '{print $3}' | sed -e "/SYN_REPORT/d" -e "/BTN_TOUCH/d" -e "/SYN_CONFIG/d")"
        [ "$keyvl" = "KEY_VOLUMEDOWN" ] && xuong=$(($xuong + 1))
        [ "$keyvl" = "KEY_VOLUMEUP" ] && len=$(($len + 1))
        [ "$keyvl" = "KEY_POWER" ] && pow=$(($pow + 1))
        [ "$keyvl" = "ABS_MT_TRACKING_ID" ] && cham=$(($cham + 1))
        # === Vol- ×4 → отключить ВСЕ модули ===
        if [ $xuong -ge 4 ]; then
            glog VOLKEY wr "$(echo "Vol- ×4 → отключаю все модули")"
            for m in /data/adb/modules/*; do
                ID=$(basename "$m")
                [ "$ID" = "$MODID" ] && continue
                [ "$ID" = "$ZMODID" ] && continue
                [ "$ID" = "$VMODID" ] && continue
                [ "$ID" = "$SMODID" ] && continue
                echo > "$m/disable"
                glog VOLKEY ii "$(echo "оключен - $ID")"
            done
            sleep 0.5
            rm -f "$MODDIR/disable"
            cache_clean
            sleep 0.5
            reboot
        fi

        if [ $len -ge 4 ]; then
            glog VOLKEY wr "$(echo "Vol+ ×4 → включаю все модули")"
            for m in /data/adb/modules/*; do
                ID=$(basename "$m")
                [ -f "$m/disable" ] && rm -f "$m/disable" && glog VOLKEY ii "$(echo "оключен - $ID")"
            done
            sleep 0.5
            reboot
        fi

        [ "$(getprop sys.boot_completed)" = 1 ] && break
        sleep 0.5
    done
}


glog bord
[ -f "$BBX" ] || busybox_in

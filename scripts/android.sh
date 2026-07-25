#!/usr/bin/env bash
# Android development toolbox — Fedora Atomic
#
# The host is rpm-ostree, so layering a JDK and the emulator's runtime deps means
# a reboot per change. Everything lives in a toolbox container instead, which
# shares $HOME, /dev (incl. /dev/kvm and /dev/dri), the Wayland/X11 sockets, and —
# because toolbox runs with --network host — the host network namespace. That last
# one is why a Metro bundler on :8081 is reachable from either side.
#
# Anything installed under $HOME (JDK, SDK, AVDs) survives `toolbox rm`; only the
# dnf packages are lost.
#
#   ./scripts/android.sh            # full setup, idempotent
#   ./scripts/android.sh emulator   # just launch the AVD
#
# iOS cannot be built on Linux at all — Xcode is macOS-only.

set -euo pipefail

CONTAINER="${ANDROID_TOOLBOX:-android}"
JDK_VERSION="17"
SDK_ROOT="$HOME/Android/Sdk"
JDK_ROOT="$HOME/.jdks"
AVD_NAME="Pixel_8_API_36"

# Keep these in step with kintra-mobile/android/build.gradle.
ANDROID_API="36"
BUILD_TOOLS="36.0.0"
NDK_VERSION="27.1.12297006"
SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis;x86_64"

# install.sh defines these and sources its scripts; `make android` runs this one
# standalone, so fall back to equivalents when they aren't already in scope.
command -v print_header  >/dev/null 2>&1 || print_header()  { echo -e "\n==> $*"; }
command -v print_success >/dev/null 2>&1 || print_success() { echo "  ✓ $*"; }
command -v print_warning >/dev/null 2>&1 || print_warning() { echo "  ! $*"; }
command -v detect_fedora_pkg_mgr >/dev/null 2>&1 || detect_fedora_pkg_mgr() {
    if command -v rpm-ostree &> /dev/null && rpm-ostree status &> /dev/null; then
        echo "rpm-ostree"
    elif command -v dnf5 &> /dev/null; then
        echo "dnf5"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    else
        echo "none"
    fi
}

tb() { toolbox run --container "$CONTAINER" "$@"; }

# Same shape as setup_aws_toolbox() in tools.sh: warn and skip rather than abort,
# so an unsupported host never breaks a full `make install`.
#
# Gated on toolbox rather than on rpm-ostree specifically — toolbox works on
# mutable Fedora too, and the container is worth having either way for the ~8 GB
# of SDK and the emulator's Qt/WebEngine dependencies.
check_host() {
    if ! command -v toolbox &> /dev/null; then
        print_warning "toolbox not found, skipping Android toolbox setup"
        if [ "$(detect_fedora_pkg_mgr)" = "none" ]; then
            print_warning "Not a Fedora host. On macOS install Android Studio directly — it bundles a JDK and SDK, and macOS builds iOS too."
        else
            print_warning "Install it with: sudo $(detect_fedora_pkg_mgr) install toolbox"
        fi
        return 1
    fi
    return 0
}

create_container() {
    if toolbox list --containers 2>/dev/null | grep -q "\b${CONTAINER}\b"; then
        print_success "toolbox '$CONTAINER' already exists"
    else
        print_header "Creating toolbox '$CONTAINER'..."
        toolbox create "$CONTAINER"
    fi
}

install_packages() {
    print_header "Installing Android toolchain packages..."
    # zsh matters: $HOME is shared, but `toolbox enter` falls back to bash when
    # your login shell isn't installed *inside* the container, and then ~/.zshrc
    # (and therefore ANDROID_HOME) never loads.
    #
    # The nss/xcb/mesa block is what the emulator's Qt + WebEngine UI links
    # against. libxkbfile is needed only in *windowed* mode — a -no-window
    # emulator boots fine without it, so never validate this setup headlessly.
    tb sudo dnf install -y \
        ruby ruby-devel gcc gcc-c++ make redhat-rpm-config zlib-devel openssl-devel \
        unzip zip which xz zsh \
        mesa-libGL mesa-dri-drivers mesa-libgbm mesa-libEGL pulseaudio-libs alsa-lib \
        gtk3 libXtst libXrender libXi libXxf86vm fontconfig freetype \
        nss nspr at-spi2-atk atk cups-libs libdrm \
        libxkbcommon libxkbcommon-x11 libxkbfile \
        libX11 libXcomposite libXcursor libXdamage libXext libXfixes libXrandr libXScrnSaver \
        pango cairo dbus-libs expat libxcb xcb-util \
        xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm
}

install_jdk() {
    # Fedora 43 ships only JDK 21/25/26, and 17 is not substitutable here: React
    # Native's Gradle plugin calls kotlinExtension.jvmToolchain(17), and the
    # project's settings.gradle has no Foojay resolver to auto-provision one, so
    # Gradle hard-fails without a real 17. Temurin also matches what CI uses.
    if compgen -G "$JDK_ROOT/jdk-${JDK_VERSION}*" >/dev/null; then
        print_success "JDK $JDK_VERSION already installed"
        return
    fi
    print_header "Installing Temurin JDK $JDK_VERSION..."
    mkdir -p "$JDK_ROOT"
    local tmp; tmp="$(mktemp -d)"
    curl -sSL --retry 5 --retry-all-errors -o "$tmp/jdk.tar.gz" \
        "https://api.adoptium.net/v3/binary/latest/${JDK_VERSION}/ga/linux/x64/jdk/hotspot/normal/eclipse"
    tar -xzf "$tmp/jdk.tar.gz" -C "$JDK_ROOT"
    rm -rf "$tmp"
}

jdk_home() { compgen -G "$JDK_ROOT/jdk-${JDK_VERSION}*" | head -1; }

install_sdk() {
    if [ -d "$SDK_ROOT/platform-tools" ]; then
        print_success "Android SDK already installed"
        return
    fi
    print_header "Installing Android SDK command-line tools..."
    # cmdline-tools gives sdkmanager/avdmanager/emulator; Android Studio is not
    # required to build or run anything.
    local tmp; tmp="$(mktemp -d)"
    curl -sSL --retry 5 -o "$tmp/cmdline.zip" \
        "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
    mkdir -p "$SDK_ROOT/cmdline-tools"
    unzip -q -o "$tmp/cmdline.zip" -d "$tmp/x"
    mv "$tmp/x/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
    rm -rf "$tmp"

    print_header "Accepting licenses and installing SDK packages (~8 GB)..."
    tb env \
        JAVA_HOME="$(jdk_home)" \
        ANDROID_HOME="$SDK_ROOT" \
        PATH="$(jdk_home)/bin:$SDK_ROOT/cmdline-tools/latest/bin:/usr/bin:/bin" \
        bash -c "yes | sdkmanager --licenses >/dev/null 2>&1; \
                 sdkmanager 'platform-tools' 'platforms;android-${ANDROID_API}' \
                            'build-tools;${BUILD_TOOLS}' 'ndk;${NDK_VERSION}' \
                            'emulator' '${SYSTEM_IMAGE}'"
}

create_avd() {
    if [ -f "$HOME/.android/avd/${AVD_NAME}.ini" ]; then
        print_success "AVD $AVD_NAME already exists"
        return
    fi
    print_header "Creating AVD $AVD_NAME..."
    tb env \
        JAVA_HOME="$(jdk_home)" \
        ANDROID_HOME="$SDK_ROOT" \
        PATH="$(jdk_home)/bin:$SDK_ROOT/cmdline-tools/latest/bin:/usr/bin:/bin" \
        bash -c "echo no | avdmanager create avd -n '${AVD_NAME}' -k '${SYSTEM_IMAGE}' -d pixel_8"
}

check_kvm() {
    print_header "Checking hardware acceleration..."
    # Without KVM the emulator silently falls back to software rendering and is
    # unusably slow, so treat this as a hard check rather than a nicety.
    if tb env ANDROID_HOME="$SDK_ROOT" PATH="$SDK_ROOT/emulator:/usr/bin:/bin" \
        emulator -accel-check 2>&1 | grep -q "is installed and usable"; then
        print_success "KVM usable"
    else
        echo "  WARNING: KVM not usable — the emulator will be extremely slow." >&2
        echo "  Check that /dev/kvm exists and is readable (it is 0666 on Fedora)." >&2
    fi
}

launch_emulator() {
    print_header "Launching $AVD_NAME..."
    # Sway tiles the emulator's windows by default, which puts its toolbars on top
    # of the device screen. config/sway/config.d/android-emulator.conf fixes that.
    tb zsh -ic "emulator -avd ${AVD_NAME} -gpu host"
}

main() {
    check_host || return 0
    case "${1:-setup}" in
        emulator) launch_emulator ;;
        setup)
            create_container
            install_packages
            install_jdk
            install_sdk
            create_avd
            check_kvm
            print_header "Done. Enter the container with: toolbox enter $CONTAINER"
            echo "  Then: cd <rn-project> && yarn start   (and in another shell) yarn android"
            ;;
        *) echo "usage: $0 [setup|emulator]" >&2; exit 1 ;;
    esac
}

main "$@"

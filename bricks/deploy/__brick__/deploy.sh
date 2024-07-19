#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source the configuration file
source .deploy-configs

# Function to configure FlutterFire
configure_flutterfire() {
    local project_id=$1
    local package_name=$2
    echo -e "${GREEN}Configuring FlutterFire for project ID: $project_id${NC}"
    if ! $FLUTTER_FIRE configure --project=$project_id --platforms android,ios -y -a $package_name -i $package_name; then
        echo -e "${RED}FlutterFire configuration failed.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    # Optionally clean and get dependencies if needed
    # flutter clean
    # flutter pub get
}

# Find APK and IPA paths
get_file_paths() {
    APK_PATH=$(find build/app/outputs/flutter-apk/ -name "*.apk" | head -n 1)
    IPA_PATH=$(find build/ios/ipa/ -name "*.ipa" | head -n 1)
}

# Function to detect the operating system
detect_os() {
    OS="unknown"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macOS"
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        OS="Windows"
    elif [[ "$OSTYPE" == "msys" ]]; then
        OS="Windows"
    elif [[ "$OSTYPE" == "win32" ]]; then
        OS="Windows"
    else
        OS="unknown"
    fi
    echo "$OS"
}

# Function to push notification on Windows using PowerShell
push_notification_windows() {
    local title="$1"
    local message="$2"
    powershell -Command "[void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); \
    \$objNotifyIcon=New-Object System.Windows.Forms.NotifyIcon; \
    \$objNotifyIcon.BalloonTipText='$message'; \
    \$objNotifyIcon.Icon=[System.Drawing.SystemIcons]::Information; \
    \$objNotifyIcon.BalloonTipTitle='$title'; \
    \$objNotifyIcon.BalloonTipIcon='None'; \
    \$objNotifyIcon.Visible=\$True; \
    \$objNotifyIcon.ShowBalloonTip(5000);"
}

# Detect the operating system
OS=$(detect_os)

# Get flutterfire commands based on the detected OS
if [[ "$OS" == "Windows" ]]; then
    echo -e "${GREEN}Running on Windows${NC}"
    FLUTTER_FIRE=flutterfire.bat
    # Windows-specific commands here
elif [[ "$OS" == "macOS" ]]; then
    echo -e "${GREEN}Running on macOS${NC}"
    FLUTTER_FIRE=flutterfire
    # macOS-specific commands here
else
    echo -e "${RED}Unsupported OS: $OS${NC}"

    read -p "Press any key to continue..."
    exit 1
fi

# Check if necessary commands are installed
if ! command -v $FLUTTER_FIRE &> /dev/null || ! command -v flutter &> /dev/null || ! command -v firebase &> /dev/null; then
    echo -e "${RED}Required commands (flutterfire, flutter, firebase) are not installed. Please install them first.${NC}"

    read -p "Press any key to continue..."
    exit 1
fi

# Prompt the user for the build flavor
echo -e "${YELLOW}Please enter the build flavor (development/production/staging):${NC}"
read FLAVOR

# Sets the target file, package name, Firebase project ID, and app IDs based on the flavor
case $FLAVOR in
  development)
    TARGET="lib/main_development.dart"
    PACKAGE_NAME=$development_package_name
    FIREBASE_PROJECT_ID=$development_firebase_project_id
    ANDROID_APP_ID=$development_android_app_id
    IOS_APP_ID=$development_ios_app_id
    ;;
  production)
    TARGET="lib/main_production.dart"
    PACKAGE_NAME=$production_package_name
    FIREBASE_PROJECT_ID=$production_firebase_project_id
    ANDROID_APP_ID=$production_android_app_id
    IOS_APP_ID=$production_ios_app_id
    ;;
  staging)
    TARGET="lib/main_staging.dart"
    PACKAGE_NAME=$staging_package_name
    FIREBASE_PROJECT_ID=$staging_firebase_project_id
    ANDROID_APP_ID=$staging_android_app_id
    IOS_APP_ID=$staging_ios_app_id
    ;;
  *)
    echo -e "${RED}Invalid flavor entered. Exiting.${NC}"

    read -p "Press any key to continue..."
    exit 1
    ;;
esac

# Prompt the user for the platform
echo -e "${YELLOW}Please enter the platform (android/ios/all):${NC}"
read PLATFORM

# Function to get the last 10 relevant git commit messages
get_git_commit_messages() {
    git log --format=%B -n 10 | grep -E "^(feat|feature|fix|chore)"
}

# Function to upload to Firebase App Distribution
upload_to_firebase() {
    local file_path=$1
    local app_id=$2
    local release_notes=$3

    local git_messages
    git_messages=$(get_git_commit_messages)
    release_notes="${release_notes}\n\nRecent changes:\n${git_messages}"
    echo -e "${GREEN}$release_notes${NC}"

    echo -e "${GREEN}Uploading ${YELLOW}$FLAVOR${GREEN} build to Firebase project ID: ${YELLOW}$FIREBASE_PROJECT_ID${NC}"
    if ! firebase appdistribution:distribute $file_path --app $app_id --release-notes "$release_notes" --groups "ThinkBIT"; then
        echo -e "${RED}Failed to upload $file_path to Firebase App Distribution.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
}

# Execute the appropriate FlutterFire config and Flutter build command based on the platform
case $PLATFORM in
  android)
    configure_flutterfire $FIREBASE_PROJECT_ID $PACKAGE_NAME
    if ! flutter build apk --release -t $TARGET --flavor $FLAVOR; then
        echo -e "${RED}Flutter build for Android failed.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    get_file_paths
    if [ -z "$APK_PATH" ]; then
        echo -e "${RED}No APK found to upload.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    upload_to_firebase $APK_PATH $ANDROID_APP_ID "New $FLAVOR build for Android"
    ;;
  ios)
    echo -e "${GREEN}Deleting existing GoogleService-Info.plist${NC}"
    rm -f ios/Runner/GoogleService-Info.plist
    configure_flutterfire $FIREBASE_PROJECT_ID $PACKAGE_NAME
    if ! flutter build ipa --release -t $TARGET --flavor $FLAVOR; then
        echo -e "${RED}Flutter build for iOS failed.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    get_file_paths
    if [ -z "$IPA_PATH" ]; then
        echo -e "${RED}No IPA found to upload.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    upload_to_firebase $IPA_PATH $IOS_APP_ID "New $FLAVOR build for iOS"
    ;;
  all)
    echo -e "${GREEN}Deleting existing GoogleService-Info.plist${NC}"
    rm -f ios/Runner/GoogleService-Info.plist
    configure_flutterfire $FIREBASE_PROJECT_ID $PACKAGE_NAME
    if ! flutter build apk --release -t $TARGET --flavor $FLAVOR; then
        echo -e "${RED}Flutter build for Android failed.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    if ! flutter build ipa --release -t $TARGET --flavor $FLAVOR; then
        echo -e "${RED}Flutter build for iOS failed.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    get_file_paths
    if [ -z "$APK_PATH" ]; then
        echo -e "${RED}No APK found to upload.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    upload_to_firebase $APK_PATH $ANDROID_APP_ID "New $FLAVOR build for Android"
    
    if [ -z "$IPA_PATH" ]; then
        echo -e "${RED}No IPA found to upload.${NC}"

        read -p "Press any key to continue..."
        exit 1
    fi
    upload_to_firebase $IPA_PATH $IOS_APP_ID "New $FLAVOR build for iOS"
    ;;
  *)
    echo -e "${RED}Invalid platform entered. Exiting.${NC}"

    read -p "Press any key to continue..."
    exit 1
    ;;
esac

# Notify the user of the completed build
echo -e "${GREEN}Build completed for flavor: ${YELLOW}$FLAVOR ${GREEN}on platform: $PLATFORM${NC}"

# Notify the user of the completed build on Windows/macOS
if [[ "$OS" == "Windows" ]]; then
    push_notification_windows "Builds for $FLAVOR" "Uploaded to Firebase Distribution"
elif [[ "$OS" == "macOS" ]]; then
    # Check if terminal-notifier is installed and notify the user
    if command -v terminal-notifier &> /dev/null; then
        terminal-notifier -title "Builds Deployed" -subtitle "Builds for $FLAVOR" -message "Uploaded to Firebase Distribution"
    else
        echo -e "${RED}terminal-notifier not installed. Skipping notification.${NC}"
    fi
else
    echo -e "${RED}Unsupported OS: $OS${NC}"

    read -p "Press any key to continue..."
    exit 1
fi

# Wait for user input before closing the window
read -p "Press any key to continue..."
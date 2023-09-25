#!/usr/bin/env bash

# Package Chat Copilot application for deployment to Azure

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIRECTORY="$SCRIPT_ROOT"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  -c, --configuration CONFIGURATION      Build configuration (default: Release)"
    echo "  -d, --dotnet DOTNET_FRAMEWORK_VERSION  Target dotnet framework (default: net6.0)"
    echo "  -r, --runtime TARGET_RUNTIME           Runtime identifier (default: linux-x64)"
    echo "  -o, --output OUTPUT_DIRECTORY          Output directory (default: $SCRIPT_ROOT)"
    echo "  -v  --version VERSION                  Version to set files to (default: 1.0.0)"
    echo "  -i  --info INFO                        Additional info to put in version details"
    echo "  -nz, --no-zip                          Do not zip package (default: false)"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -c|--configuration)
        CONFIGURATION="$2"
        shift
        shift
        ;;
        -d|--dotnet)
        DOTNET="$2"
        shift
        shift
        ;;
        -r|--runtime)
        RUNTIME="$2"
        shift
        shift
        ;;
        -o|--output)
        OUTPUT_DIRECTORY="$2"
        shift
        shift
        ;;
        -v|--version)
        VERSION="$2"
        shift
        shift
        ;;
        -i|--info)
        INFO="$2"
        shift
        shift
        ;;
        -nz|--no-zip)
        NO_ZIP=true
        shift
        ;;
        *)
        echo "Unknown option $1"
        usage
        exit 1
        ;;
    esac
done

echo  "Building backend executables..."

# Set defaults
: "${CONFIGURATION:="Release"}"
: "${DOTNET:="net6.0"}"
: "${RUNTIME:="linux-x64"}"
: "${VERSION:="0.0.0"}"
: "${INFO:=""}"
: "${OUTPUT_DIRECTORY:="$SCRIPT_ROOT"}"

PUBLISH_OUTPUT_DIRECTORY="$OUTPUT_DIRECTORY/publish"
PUBLISH_ZIP_DIRECTORY="$OUTPUT_DIRECTORY/out"
PACKAGE_FILE_PATH="$PUBLISH_ZIP_DIRECTORY/webapi.zip"

if [[ ! -d "$PUBLISH_OUTPUT_DIRECTORY" ]]; then
    mkdir -p "$PUBLISH_OUTPUT_DIRECTORY"
fi
if [[ ! -d "$PUBLISH_ZIP_DIRECTORY" ]]; then
    mkdir -p "$PUBLISH_ZIP_DIRECTORY"
fi

echo "Build configuration: $CONFIGURATION"
dotnet publish "$SCRIPT_ROOT/../../webapi/CopilotChatWebApi.csproj" --configuration $CONFIGURATION --framework $DOTNET --runtime $RUNTIME --self-contained --output "$PUBLISH_OUTPUT_DIRECTORY" /p:AssemblyVersion=$VERSION /p:FileVersion=$VERSION /p:InformationalVersion=$INFO
if [ $? -ne 0 ]; then
    exit 1
fi

echo "Building static frontend files..."

ENV_FILE_PATH="$SCRIPT_ROOT/../../webapp/.env"
echo "Writing environment variables to '$ENV_FILE_PATH'..."
echo "REACT_APP_BACKEND_URI=<-=TOKEN=->Frontend:BackendUri</-=TOKEN=->" > $ENV_FILE_PATH
echo "REACT_APP_AUTH_TYPE=AzureAd" >> $ENV_FILE_PATH
echo "REACT_APP_AAD_AUTHORITY=<-=TOKEN=->Authentication:AzureAd:Instance</-=TOKEN=->/<-=TOKEN=->Authentication:AzureAd:TenantId</-=TOKEN=->" >> $ENV_FILE_PATH
echo "REACT_APP_AAD_CLIENT_ID=<-=TOKEN=->Frontend:AadClientId</-=TOKEN=->" >> $ENV_FILE_PATH
echo "REACT_APP_AAD_API_SCOPE=api://<-=TOKEN=->Authentication:AzureAd:ClientId</-=TOKEN=->/<-=TOKEN=->Authentication:AzureAd:Scopes</-=TOKEN=->" >> $ENV_FILE_PATH
echo "REACT_APP_SK_VERSION=$VERSION" >> $ENV_FILE_PATH
echo "REACT_APP_SK_BUILD_INFO=$VERSION_INFO" >> $ENV_FILE_PATH

pushd "$SCRIPT_ROOT/../../webapp"

echo "Installing yarn dependencies..."
yarn install
if [ $? -ne 0 ]; then
    echo "Failed to install yarn dependencies"
    exit 1
fi

echo "Building webapp..."
yarn build
if [ $? -ne 0 ]; then
    echo "Failed to build webapp"
    exit 1
fi

popd

echo "Copying frontend files to package"
cp -R "$SCRIPT_ROOT/../../webapp/build" "$PUBLISH_OUTPUT_DIRECTORY/wwwroot"

# if not NO_ZIP then zip the package
if [[ -z "$NO_ZIP" ]]; then
    pushd "$PUBLISH_OUTPUT_DIRECTORY"
    echo "Compressing to $PACKAGE_FILE_PATH"
    zip -r $PACKAGE_FILE_PATH .
    popd
fi

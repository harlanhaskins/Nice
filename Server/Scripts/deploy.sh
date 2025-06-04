SCRIPTS_DIR_PATH=$(dirname $(realpath -s $0))
PACKAGE_PATH=$(dirname "$SCRIPTS_DIR_PATH")

set -x

swift build -c release --package-path "$PACKAGE_PATH"

if [[ $? -ne 0 ]]; then
  echo "Build failed; not deploying"
else
  echo "Build succeeded; deploying"
  sudo service nice restart
fi
!/bin/bash

# Script to clone a repository and run its install script

# Exit immediately if a command exits with a non-zero status.
set -e

# Define the repository URL and the directory name
REPO_URL="https://github.com/cschambers2101/node_install.git"
REPO_DIR="node_install"
INSTALL_SCRIPT="install.sh"

# Inform the user about the process
echo "Starting the process ..."
echo "Cloning and installing Node ... "

# 1. Clone the repository
if [ -d "$REPO_DIR" ]; then
  echo "Directory '$REPO_DIR' already exists. Pulling latest changes..."
  cd "$REPO_DIR"
  git pull
  cd ..
else
  echo "Cloning repository '$REPO_URL' into directory '$REPO_DIR'..."
  git clone "$REPO_URL"
fi

# 2. Navigate into the cloned repository directory
echo "Changing directory to '$REPO_DIR'..."
cd "$REPO_DIR"

# 3. Check if the install script exists
if [ ! -f "$INSTALL_SCRIPT" ]; then
  echo "Error: Install script '$INSTALL_SCRIPT' not found in the repository."
  exit 1
fi

# 4. Make the install script executable (optional, but good practice)
echo "Making '$INSTALL_SCRIPT' executable..."
chmod +x "$INSTALL_SCRIPT"

# 5. Run the install script
echo "Running '$INSTALL_SCRIPT' ..."
./"$INSTALL_SCRIPT"

echo "Process completed successfully."

# Navigate back to the original directory (optional)
cd ..

exit 0


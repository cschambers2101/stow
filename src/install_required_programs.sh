#!/bin/bash

# Check if the package list file exists
if [ ! -f "programs_to_install.txt" ]; then
    echo "Error: installed.txt not found!"
    exit 1
fi

# Update package list first
echo "Updating package list..."
sudo apt-get update

# Read each line from installed.txt and install the package
echo "Installing packages from installed.txt..."
while IFS= read -r package || [[ -n "$package" ]]; do
    # Skip empty lines or lines starting with # (comments)
    if [[ -z "$package" || "$package" =~ ^# ]]; then
        continue
    fi
    echo "Attempting to install $package..."
    sudo apt-get install -y -o Acquire::http::Pipeline-Depth "0" "$package"
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to install $package. It might not exist or there was an error."
    fi
done < "programs_to_install.txt"

echo "Script finished."
exit 0



set -euo pipefail

# Check for WSL environment
if ! grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then
	echo "This script is intended for WSL only."
	exit 1
fi

echo "Azure Kubernetes WSL Packages Installation Script"

# Update system packages
echo -e "\nUpdating system packages..."
sudo apt-get update
sudo apt-get dist-upgrade -y

# Install prerequisites
echo -e "\nInstalling prerequisites..."
sudo apt-get install -y curl ca-certificates gnupg lsb-release

# Install Azure CLI
echo -e "\nInstalling Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Helm
echo -e "\nInstalling Helm..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

# Install kubectl
echo -e "\nInstalling kubectl..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl


# Ensure snapd is installed and running before installing kubelogin
echo -e "\nChecking for snapd..."
if ! command -v snap &> /dev/null; then
	echo "snapd not found. Installing snapd..."
	sudo apt-get install -y snapd
	sudo systemctl enable --now snapd
fi

# Install kubelogin
echo -e "\nInstalling kubelogin..."
sudo snap install kubelogin

echo "All packages installed successfully."
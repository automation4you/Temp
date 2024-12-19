# Define image name
#$imageName = "mcr.microsoft.com/windows/servercore/iis"
$imageName = "testimage:latest"

########################################################################################################
# Define variables
$containerName = "iis_core_container"
$hostPort = 8080   # The port on the host machine
$containerPort = 80  # The port in the container
$GmsaJsonAccount = "ServiceA.json"

# Define web data to copy
$websiteSourcePath = "C:\temp\."  # Replace with the path to your website files on the host
$containerWebsitePath = "C:\inetpub\wwwroot"   # Default IIS web root in the container
########################################################################################################

# Ask the user whether they want to pull the IIS Docker image
$pullImage = Read-Host "Do you want to pull the IIS Docker image from the registry? (Y/N)"
if ($pullImage -eq "Y" -or $pullImage -eq "y") {
    Write-Host "Pulling IIS Docker image..." -ForegroundColor Cyan
    try {
        docker pull $imageName
        Write-Host "IIS Docker image pulled successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to pull IIS Docker image. Error: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Skipping IIS Docker image pull. Using local image if available." -ForegroundColor Yellow
}

# Display the image being used
Write-Host "Using the Docker image: $imageName" -ForegroundColor Green

# Show the locally available images
Write-Host "Listing local images..." -ForegroundColor Cyan
docker images $imageName

# Stop and remove any existing container with the same name (optional)
try {
    if ((docker ps -a -q -f "name=$containerName") -ne $null) {
        Write-Host "Stopping existing container..." -ForegroundColor Yellow
        docker stop $containerName
        Write-Host "Removing existing container..." -ForegroundColor Yellow
        docker rm $containerName
    }
} catch {
    Write-Host "Failed to stop/remove existing container. Error: $_" -ForegroundColor Red
    exit 1
}

# Run the IIS container with dynamic ports
Write-Host "Running IIS container with dynamic ports..." -ForegroundColor Cyan
try {
    docker run -d --name $containerName -p ${hostPort}:${containerPort} --security-opt "credentialspec=file://$GmsaJsonAccount" $imageName
    Write-Host "IIS container started successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to start IIS container. Error: $_" -ForegroundColor Red
    exit 1
}

# Copy the website data into the container's IIS web root directory
Write-Host "Copying website data into the container..." -ForegroundColor Cyan
try {
    docker cp $websiteSourcePath ${containerName}:$containerWebsitePath
    Write-Host "Website data copied successfully into the container at C:\inetpub\wwwroot." -ForegroundColor Green
} catch {
    Write-Host "Failed to copy website data into the container. Error: $_" -ForegroundColor Red
    exit 1
}

# Stop the DefaultAppPool before making changes
Write-Host "Stopping DefaultAppPool to configure its identity..." -ForegroundColor Cyan
try {
    docker exec $containerName powershell -Command "
        Import-Module WebAdministration
        Stop-WebAppPool 'DefaultAppPool'
    "
    Write-Host "DefaultAppPool stopped successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to stop DefaultAppPool. Error: $_" -ForegroundColor Red
    exit 1
}

# Set DefaultAppPool to run as Network Service
Write-Host "Configuring DefaultAppPool to run as Network Service..." -ForegroundColor Cyan
try {
    docker exec $containerName powershell -Command "
        Import-Module WebAdministration
        Set-ItemProperty IIS:\AppPools\DefaultAppPool -Name processModel.identityType -Value NetworkService
    "
    Write-Host "DefaultAppPool configured to run as Network Service." -ForegroundColor Green
} catch {
    Write-Host "Failed to configure DefaultAppPool as Network Service. Error: $_" -ForegroundColor Red
    exit 1
}

# Start the DefaultAppPool
Write-Host "Starting the DefaultAppPool..." -ForegroundColor Cyan
try {
    docker exec $containerName powershell -Command "
        Import-Module WebAdministration
        Start-WebAppPool 'DefaultAppPool'
    "
    Write-Host "The 'DefaultAppPool' was successfully started." -ForegroundColor Green
} catch {
    Write-Host "Failed to start the 'DefaultAppPool'. Error: $_" -ForegroundColor Red
    exit 1
}

# Check the App Pool State to verify if it's running
Write-Host "Verifying the App Pool state..." -ForegroundColor Cyan
try {
    $appPoolState = docker exec $containerName powershell -Command "
        Import-Module WebAdministration
        Get-WebAppPoolState -Name 'DefaultAppPool'
    "
    Write-Host "Verification Output: $appPoolState" -ForegroundColor Green
} catch {
    Write-Host "Failed to verify the 'DefaultAppPool' state. Error: $_" -ForegroundColor Red
    exit 1
}

# Confirm everything is working
Write-Host "IIS container is running. You can access it at http://localhost:${hostPort}" -ForegroundColor Green

# Ask the user if they want to launch a PowerShell session inside the container
$launchSession = Read-Host "Do you want to launch a PowerShell session inside the container in a new CMD window? (Y/N)"
if ($launchSession -eq "Y" -or $launchSession -eq "y") {
    Write-Host "Launching PowerShell session inside the container in a new CMD window..." -ForegroundColor Cyan
    try {
        Start-Process cmd.exe -ArgumentList "/K", "docker exec -it $containerName powershell"
    } catch {
        Write-Host "Failed to launch PowerShell session. Error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "PowerShell session not launched. User Declined." -ForegroundColor Yellow
}

# Ask the user if they want to commit the container to create a new image
$commitImage = Read-Host "Do you want to commit the container to create a new image? (Y/N)"
if ($commitImage -eq "Y" -or $commitImage -eq "y") {
    # Validate that the user provides a non-empty image name
    $newImageName = Read-Host "Enter a name for the new image (e.g., my_custom_image)"
    if (-not $newImageName) {
        Write-Host "Invalid image name. Exiting script." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Stopping the container to commit it..." -ForegroundColor Cyan
    try {
        docker stop $containerName
        Write-Host "Container stopped successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to stop container. Error: $_" -ForegroundColor Red
        exit 1
    }

    Write-Host "Committing the container to a new image..." -ForegroundColor Cyan
    try {
        docker commit $containerName $newImageName
        Write-Host "New image '$newImageName' created successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to commit container to new image. Error: $_" -ForegroundColor Red
    }

    # Restart the container if needed
    Write-Host "Restarting the container..." -ForegroundColor Cyan
    try {
        docker start $containerName
        Write-Host "Container restarted successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to restart the container. Error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Container commit skipped. Exiting script." -ForegroundColor Yellow
}
